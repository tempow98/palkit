--[[
    PalKit -- shared/safe.lua
    Gardes d'execution : rien ne remonte non attrape.

    Regle du brief (SS3.7) : chaque frontiere d'entree -- keybind, timer, hook moteur,
    chargement de script -- et chaque operation faillible -- reflexion moteur, IO, JSON --
    tourne dans un garde. On logge et on continue.

    Corollaire, et c'est le point qui compte : le demarrage n'est JAMAIS tout-ou-rien.
    Chaque keybind et chaque timer s'enregistre independamment, dans son propre pcall,
    de sorte qu'un echec isole n'emporte pas le mod entier. Un mod qui ne repond plus a
    rien ne renvoie aucune information exploitable ; un mod qui a perdu une touche sur
    quatre, si.

    Deux niveaux de pcall sont necessaires pour chaque frontiere :
      1. autour de l'ENREGISTREMENT (RegisterKeyBind peut lever : touche inconnue,
         deja prise, API absente sur ce build UE4SS) ;
      2. autour de l'EXECUTION du callback (une exception qui traverse la frontiere
         remonte dans le moteur -- au mieux elle est avalee, au pire elle crashe).
]]

local safe = {}

-- Traceback peut etre absent si le sandbox Lua est restreint : on degrade.
local function traceback(message)
    if debug and debug.traceback then
        local ok, tb = pcall(debug.traceback, tostring(message), 3)
        if ok then return tb end
    end
    return tostring(message)
end

--- Appelle `fn` sous garde. Ne propage jamais.
-- @param logger table   logger issu de log.new()
-- @param name string    libelle utilise dans le message d'erreur
-- @param fn function
-- @return boolean ok, any result  (result vaut nil en cas d'echec)
function safe.call(logger, name, fn, ...)
    if type(fn) ~= "function" then
        logger.error("%s : callable attendu, recu %s", name, type(fn))
        return false, nil
    end

    local results = { pcall(fn, ...) }
    if results[1] then
        return true, results[2]
    end

    logger.error("%s a leve : %s", name, traceback(results[2]))
    return false, nil
end

--- Enveloppe `fn` pour qu'elle soit toujours appelee sous garde.
-- @return function  version protegee de fn
function safe.wrap(logger, name, fn)
    return function(...)
        local _, result = safe.call(logger, name, fn, ...)
        return result
    end
end

--- Enregistre un keybind, sous garde des deux cotes.
-- Accepte les deux signatures UE4SS :
--   RegisterKeyBind(Key, Callback)
--   RegisterKeyBind(Key, {ModifierKeys}, Callback)
-- @param modifiers table|nil  ex. { ModifierKey.CONTROL }
-- @return boolean  vrai si l'enregistrement a abouti
function safe.keybind(logger, name, key, modifiers, fn)
    if key == nil then
        logger.error("keybind %s : touche nil (constante Key.* inconnue sur ce build ?)", name)
        return false
    end

    local guarded = safe.wrap(logger, "keybind " .. name, fn)

    local ok, err = pcall(function()
        if modifiers and #modifiers > 0 then
            RegisterKeyBind(key, modifiers, guarded)
        else
            RegisterKeyBind(key, guarded)
        end
    end)

    if not ok then
        logger.error("keybind %s : enregistrement impossible : %s", name, tostring(err))
        return false
    end

    logger.info("keybind %s enregistre", name)
    return true
end

--- Demarre un LoopAsync sous garde.
-- Contrat UE4SS : le callback stoppe la boucle en retournant true. Un callback qui leve
-- ne doit donc surtout pas etre interprete comme "continue" en silence -- on logge et on
-- poursuit, sauf si l'echec est repete, auquel cas on coupe la boucle pour ne pas laisser
-- tourner un timer mort a la frequence du jeu.
-- @param delayMs number
-- @param fn function  retourne true pour arreter
-- @return boolean  vrai si la boucle a demarre
function safe.loop(logger, name, delayMs, fn)
    local consecutiveFailures = 0
    local MAX_FAILURES = 10

    local guarded = function()
        local ok, shouldStop = safe.call(logger, "loop " .. name, fn)

        if ok then
            consecutiveFailures = 0
            return shouldStop == true
        end

        consecutiveFailures = consecutiveFailures + 1
        if consecutiveFailures >= MAX_FAILURES then
            logger.fatalOnce("loop %s : %d echecs consecutifs, boucle arretee",
                             name, consecutiveFailures)
            return true -- stoppe la boucle
        end
        return false
    end

    local ok, err = pcall(LoopAsync, delayMs, guarded)
    if not ok then
        logger.error("loop %s : demarrage impossible : %s", name, tostring(err))
        return false
    end

    logger.info("loop %s demarree (%d ms)", name, delayMs)
    return true
end

--- Enregistre un hook de UFunction sous garde.
-- @param ufunction string  chemin complet de la UFunction
-- @return boolean ok, integer|nil preId, integer|nil postId
function safe.hook(logger, name, ufunction, fn)
    local guarded = safe.wrap(logger, "hook " .. name, fn)

    local ok, preId, postId = pcall(RegisterHook, ufunction, guarded)
    if not ok then
        -- Cas le plus frequent : la UFunction n'existe plus sous ce nom apres un patch.
        -- C'est une information de premier ordre, pas un detail.
        logger.error("hook %s (%s) : enregistrement impossible : %s",
                     name, ufunction, tostring(preId))
        return false, nil, nil
    end

    logger.info("hook %s enregistre sur %s", name, ufunction)
    return true, preId, postId
end

--- Execute dans le game thread, sous garde.
-- Toute manipulation d'UObject/UMG doit passer par la : y toucher depuis le thread Lua
-- est une cause classique de crash.
function safe.gameThread(logger, name, fn)
    local guarded = safe.wrap(logger, "gameThread " .. name, fn)
    local ok, err = pcall(ExecuteInGameThread, guarded)
    if not ok then
        logger.error("gameThread %s : dispatch impossible : %s", name, tostring(err))
        return false
    end
    return true
end

--- Verifie qu'un UObject est valide avant usage.
-- `IsValid` est une methode des UObject exposes ; l'appeler sur nil ou sur une table
-- quelconque leve. Ce helper absorbe les deux cas.
function safe.isValid(obj)
    if obj == nil then return false end
    local ok, valid = pcall(function() return obj:IsValid() end)
    return ok and valid == true
end

--- Lit une propriete d'UObject sous garde.
-- La reflexion moteur leve des que le nom n'existe pas -- ce qui arrive a chaque patch.
-- @return any|nil
function safe.get(obj, propertyName)
    if obj == nil then return nil end
    local ok, value = pcall(function() return obj[propertyName] end)
    if ok then return value end
    return nil
end

return safe
