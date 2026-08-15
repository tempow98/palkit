--[[
    PalKit -- shared/query.lua
    Resolution d'objets du jeu : trouver, valider, relire.

    Ce fichier etait volontairement absent de la Phase 0 : son design dependait des noms de
    classes du jeu, qu'on ne pouvait pas deviner. Ils sont connus depuis la passe headers
    1.0 (docs/sdk-notes.md, entrees au statut "header") -- il devient ecrivable.

    Trois regles le gouvernent :

    1. RIEN N'EST GARDE SANS ETRE REVALIDE. Un UObject mis en cache peut etre detruit a tout
       moment -- changement de monde, mort du joueur, teleport. On memorise pour eviter les
       parcours couteux, mais on repasse par IsValid a chaque acces, et on re-resout si le
       cache est mort. C'est la difference entre un cache et un pointeur pendouillant.

    2. AUCUN PARCOURS DU TABLEAU UOBJECT DANS UNE BOUCLE. FindAllOf balaie l'ensemble des
       objets ; a 10 Hz dans une minimap, c'est inacceptable (brief SS3.3). Les chemins
       d'acces sont ici des chaines de proprietes depuis le PlayerController, jamais des
       recherches globales.

    3. QUERY NE MODIFIE RIEN. Pas de RegisterHook, pas d'appel qui change l'etat du jeu.
       Lire ne casse pas de sauvegarde ; c'est ce qui rend ce module sur a appeler partout.
]]

local safe = require("safe")

local query = {}

-- Le Lua d'UE4SS est en 5.4, le luac de controle sur le Pi en 5.1 : les deux noms coexistent.
local unpackArgs = table.unpack or unpack

-- Cache d'objets racines. Volontairement plat : quatre entrees, pas un systeme.
local cache = {
    helpers    = nil, -- module UEHelpers
    controller = nil,
    pawn       = nil,
    playerState= nil,
    palStorage = nil,
}

--- Vide le cache. A appeler au chargement de monde et apres un echec repete.
function query.reset()
    cache.controller  = nil
    cache.pawn        = nil
    cache.playerState = nil
    cache.palStorage  = nil
end

-- ------------------------------------------------------------------ appels proteges

--- Appelle une methode d'UObject sous garde.
-- La reflexion moteur leve des que le nom n'existe plus (cas classique apres un patch) :
-- on renvoie nil plutot que de laisser remonter.
-- @return any|nil
function query.call(obj, methodName, ...)
    if obj == nil then return nil end
    local args = { ... }
    local argCount = select("#", ...)
    local ok, result = pcall(function()
        local fn = obj[methodName]
        if type(fn) ~= "function" then return nil end
        return fn(obj, unpackArgs(args, 1, argCount))
    end)
    if ok then return result end
    return nil
end

--- Lit une propriete d'UObject sous garde. Alias lisible de safe.get.
function query.get(obj, propertyName)
    return safe.get(obj, propertyName)
end

--- Nom complet d'un UObject, sans jamais lever.
function query.nameOf(obj)
    if obj == nil then return "<nil>" end
    local ok, name = pcall(function() return obj:GetFullName() end)
    if ok and type(name) == "string" then return name end
    ok, name = pcall(function() return obj:GetFName():ToString() end)
    if ok and type(name) == "string" then return name end
    return "<sans nom>"
end

--- Convertit une FString/FName moteur en chaine Lua, sous garde.
function query.str(value)
    if value == nil then return nil end
    if type(value) == "string" then return value end
    local ok, s = pcall(function() return value:ToString() end)
    if ok and type(s) == "string" then return s end
    return tostring(value)
end

-- ------------------------------------------------------------------ recherche globale

--- FindFirstOf sous garde. A n'utiliser QUE hors boucle (voir regle 2).
function query.findFirst(logger, className)
    local ok, obj = pcall(FindFirstOf, className)
    if not ok then
        logger.error("findFirst %s : %s", className, tostring(obj))
        return nil
    end
    if not safe.isValid(obj) then return nil end
    return obj
end

--- FindAllOf sous garde. Meme avertissement, en pire : le cout croit avec la taille du monde.
-- @return table  toujours une table, vide en cas d'echec
function query.findAll(logger, className)
    local ok, objects = pcall(FindAllOf, className)
    if not ok or type(objects) ~= "table" then
        if not ok then logger.error("findAll %s : %s", className, tostring(objects)) end
        return {}
    end
    return objects
end

-- ------------------------------------------------------------------ chaine joueur

--- Module UEHelpers, charge une fois.
local function helpers(logger)
    if cache.helpers ~= nil then return cache.helpers end
    local ok, mod = pcall(require, "UEHelpers")
    if not ok or type(mod) ~= "table" then
        logger.error("UEHelpers indisponible : %s", tostring(mod))
        return nil
    end
    cache.helpers = mod
    return mod
end

--- APalPlayerController.
-- Porte d'entree de tout le reste : PlayerState, pawn, Palbox.
-- Source : ModdingKit 62fad41 -- PalPlayerController.h (docs/sdk-notes.md)
function query.controller(logger)
    if safe.isValid(cache.controller) then return cache.controller end

    local ue = helpers(logger)
    if ue == nil then return nil end

    local ok, controller = pcall(function() return ue.GetPlayerController() end)
    if not ok or not safe.isValid(controller) then
        -- Cas normal, pas une erreur : monde pas encore charge, ou -- en multi et sur
        -- serveur dedie -- mod initialise avant l'entree en jeu. Presser INS relance.
        logger.debug("PlayerController indisponible (monde charge ?)")
        return nil
    end

    cache.controller = controller
    return controller
end

--- Pawn du joueur local (APalPlayerCharacter).
-- Passe par le controller : pas de parcours d'objets.
function query.pawn(logger)
    if safe.isValid(cache.pawn) then return cache.pawn end

    local controller = query.controller(logger)
    if controller == nil then return nil end

    local pawn = query.call(controller, "K2_GetPawn")
    if not safe.isValid(pawn) then
        logger.debug("pawn indisponible (joueur mort ou en chargement ?)")
        return nil
    end

    cache.pawn = pawn
    return pawn
end

--- Position monde du joueur, en table { x, y, z }.
-- @return table|nil
function query.playerLocation(logger)
    local pawn = query.pawn(logger)
    if pawn == nil then return nil end

    local loc = query.call(pawn, "K2_GetActorLocation")
    if loc == nil then return nil end

    local ok, out = pcall(function()
        return { x = loc.X, y = loc.Y, z = loc.Z }
    end)
    if not ok then return nil end
    return out
end

--- APalPlayerState : porte les donnees persistantes du joueur, dont la Palbox.
-- Source : ModdingKit 62fad41 -- PalPlayerState.h
function query.playerState(logger)
    if safe.isValid(cache.playerState) then return cache.playerState end

    local controller = query.controller(logger)
    if controller == nil then return nil end

    -- PlayerState est une propriete moteur d'AController, pas une methode Pal.
    local playerState = safe.get(controller, "PlayerState")
    if not safe.isValid(playerState) then
        logger.debug("PlayerState indisponible")
        return nil
    end

    cache.playerState = playerState
    return playerState
end

--- UPalPlayerDataPalStorage : la Palbox, cote donnees.
-- C'est le point qui debloque M2 sans toucher a l'interface : les Pals sont lisibles meme
-- ecran ferme (docs/sdk-notes.md, chaine d'acces).
-- Source : ModdingKit 62fad41 -- PalPlayerState.h:573 GetPalStorage()
function query.palStorage(logger)
    if safe.isValid(cache.palStorage) then return cache.palStorage end

    local playerState = query.playerState(logger)
    if playerState == nil then return nil end

    local storage = query.call(playerState, "GetPalStorage")
    if not safe.isValid(storage) then
        logger.error("GetPalStorage n'a rien renvoye -- signature changee depuis la 1.0 ?")
        return nil
    end

    cache.palStorage = storage
    return storage
end

return query
