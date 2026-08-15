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

-- Cache d'objets racines. Volontairement plat : quelques entrees, pas un systeme.
local cache = {
    helpers    = nil, -- module UEHelpers
    controller = nil,
    pawn       = nil,
    playerState= nil,
    palStorage = nil,
    palRoute   = nil, -- nom de la voie d'acces Palbox qui a abouti (voir query.palStorage)
}

--- Vide le cache. A appeler au chargement de monde et apres un echec repete.
function query.reset()
    cache.controller  = nil
    cache.pawn        = nil
    cache.playerState = nil
    cache.palStorage  = nil
    cache.palRoute    = nil
end

-- ------------------------------------------------------------------ appels proteges

--- Appelle une methode d'UObject sous garde, en disant POURQUOI ca echoue.
-- La reflexion moteur leve des que le nom n'existe plus (cas classique apres un patch) :
-- on renvoie nil plutot que de laisser remonter.
--
-- Le `logger` est optionnel, mais ne pas le passer coute cher : le premier essai en jeu du
-- 2026-08-15 a rendu "GetPalStorage n'a rien renvoye" sans jamais dire si le membre etait
-- absent, present-mais-non-appelable, ou levait -- trois causes qui appellent trois
-- corrections differentes. Les trois sont desormais distinguees, au niveau DEBUG.
-- @return any|nil
local function invoke(logger, obj, methodName, ...)
    -- Les messages passent par always("DEBUG") et non par debug() : le logger dedoublonne
    -- sur la chaine de format, or c'est la MEME ici pour toutes les methodes. Le 2e run
    -- (2026-08-15 18:13) n'a donc montre l'echec que de la premiere -- GetPageNum et
    -- GetSlot etaient supprimes, et la cause racine est restee invisible une passe de plus.
    local function say(fmt, ...)
        if not logger then return end
        if logger.always then logger.always("DEBUG", fmt, ...) else logger.debug(fmt, ...) end
    end

    if obj == nil then
        say("%s : appele sur nil", methodName)
        return nil
    end

    local args = { ... }
    local argCount = select("#", ...)

    local okIndex, fn = pcall(function() return obj[methodName] end)
    if not okIndex then
        say("%s : membre inaccessible (%s)", methodName, tostring(fn))
        return nil
    end
    if fn == nil then
        say("%s : membre absent de la classe", methodName)
        return nil
    end

    -- NE PAS exiger type(fn) == "function". UE4SS expose les UFunction comme des
    -- **userdata appelables** (metatable __call), pas comme des fonctions Lua. Exiger le
    -- type "function" rejetait donc TOUTES les methodes du jeu sans exception -- c'est la
    -- cause unique des echecs de GetPalStorage, GetPalPlayerState, GetPageNum et GetSlot
    -- des deux premiers runs. Lua sait appeler un userdata __call comme n'importe quelle
    -- fonction : on tente l'appel, et c'est lui qui tranche.
    local okCall, result = pcall(fn, obj, unpackArgs(args, 1, argCount))
    if not okCall then
        local err = tostring(result)
        if string.find(err, "attempt to call", 1, true) then
            say("%s : membre present (type %s) mais non appelable -- %s",
                methodName, type(fn), err)
        else
            say("%s a leve : %s", methodName, err)
        end
        return nil
    end
    return result
end

--- Appel silencieux. Signature historique, conservee pour les appels ou l'echec est attendu.
function query.call(obj, methodName, ...)
    return invoke(nil, obj, methodName, ...)
end

--- Appel trace : identique, mais explique son echec au niveau DEBUG.
function query.callWhy(logger, obj, methodName, ...)
    return invoke(logger, obj, methodName, ...)
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

--- UWorld courant. Sert de WorldContextObject aux UFUNCTION statiques.
-- UEHelpers expose des fonctions de module (pas de `self`) : appel avec un point.
function query.world(logger)
    local ue = helpers(logger)
    if ue == nil then return nil end

    local ok, world = pcall(function() return ue.GetWorld() end)
    if not ok or not safe.isValid(world) then return nil end
    return world
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
--
-- Deux voies, et l'ordre compte. L'ObjectDump du 2026-08-15 montre DEUX
-- `BP_PalPlayerState_C` vivants dans le monde solo (`_2147480325` et `_2147480221`), dont un
-- seul porte une `PalPlayerDataPalStorage`. La propriete moteur `PlayerState` d'AController
-- n'offre aucune garantie de designer celui-la ; le getter Pal, si -- c'est lui qui sait ce
-- qu'est un PlayerState *Pal*.
-- Source : ObjectDump 2026-08-15 + PalPlayerController.h:935 GetPalPlayerState()
function query.playerState(logger)
    if safe.isValid(cache.playerState) then return cache.playerState end

    local controller = query.controller(logger)
    if controller == nil then return nil end

    -- Voie 1 : le getter Pal dedie.
    local playerState = query.callWhy(logger, controller, "GetPalPlayerState")

    -- Voie 2 : la propriete moteur d'AController, en repli.
    if not safe.isValid(playerState) then
        logger.debug("GetPalPlayerState muet, repli sur la propriete PlayerState")
        playerState = safe.get(controller, "PlayerState")
    end

    if not safe.isValid(playerState) then
        logger.debug("PlayerState indisponible")
        return nil
    end

    cache.playerState = playerState
    return playerState
end

-- ------------------------------------------------------------------ Palbox

--- Un storage n'est retenu que s'il repond -- **jusqu'aux slots**.
--
-- La premiere version s'arretait aux dimensions (PageNum > 0). Le 2e run l'a prise en
-- defaut : une voie annoncait 32 pages x 30 slots, la sonde constatait juste apres que
-- GetSlot(0,0) rendait nil, et la voie etait quand meme retenue -- puis l'export sortait
-- "0 Pal, 960 slots illisibles" en se declarant satisfait. Des dimensions ne prouvent
-- rien : ce sont deux proprietes repliquees, lisibles meme si plus aucune methode ne
-- repond. Le seul test qui engage, c'est de sortir un slot.
-- @return boolean
local function storageAnswers(logger, storage)
    if not safe.isValid(storage) then return false end

    local pages = query.call(storage, "GetPageNum")
    if type(pages) ~= "number" then pages = safe.get(storage, "PageNum") end

    if type(pages) ~= "number" or pages <= 0 then
        logger.debug("storage ecarte : GetPageNum/PageNum = %s", tostring(pages))
        return false
    end

    if not safe.isValid(query.call(storage, "GetSlot", 0, 0)) then
        logger.debug("storage ecarte : %d pages annoncees, mais GetSlot(0,0) ne rend rien",
            pages)
        return false
    end
    return true
end

--- Voies d'acces a la Palbox, de la plus propre a la plus brutale.
--
-- Pourquoi une cascade plutot qu'un chemin unique : le premier essai en jeu (2026-08-15) a
-- rendu `GetPalStorage n'a rien renvoye` alors que la signature est bonne
-- (`PalPlayerState.h:573`, UFUNCTION BlueprintPure) et que l'instance existe bien au runtime
-- (ObjectDump : `...BP_PalPlayerState_C_2147480325.PalPlayerDataPalStorage_2147457951`).
-- Le nom n'etait donc pas en cause -- la maniere d'y arriver, si. Une cascade nommee survit
-- a ca, et le log dit laquelle a abouti : c'est ce qui alimente docs/sdk-notes.md.
local PAL_STORAGE_ROUTES = {
    {
        name = "PlayerState:GetPalStorage()",
        resolve = function(logger)
            return query.callWhy(logger, query.playerState(logger), "GetPalStorage")
        end,
    },
    {
        -- UPROPERTY(BlueprintReadWrite, Replicated) -- PalPlayerState.h:180.
        -- Une propriete se lit souvent la ou l'appel de UFunction resiste.
        name = "PlayerState.PalStorage (propriete)",
        resolve = function(logger)
            return safe.get(query.playerState(logger), "PalStorage")
        end,
    },
    {
        -- Statique, via le CDO. Contourne entierement le PlayerState -- donc aussi
        -- l'ambiguite des deux instances.
        -- Source : PalUtility.h:1182 GetPalStorageDataByPlayerUID
        name = "PalUtility.GetPalStorageDataByPlayerUID(uid)",
        resolve = function(logger)
            local controller = query.controller(logger)
            if controller == nil then return nil end

            local uid = query.callWhy(logger, controller, "GetPlayerUId")
            if uid == nil then return nil end

            local ok, cdo = pcall(StaticFindObject, "/Script/Pal.Default__PalUtility")
            if not ok or not safe.isValid(cdo) then
                logger.debug("Default__PalUtility introuvable")
                return nil
            end

            -- Le WorldContextObject accepte n'importe quel UObject rattache au monde :
            -- le controller fait un repli parfaitement valable.
            local world = query.world(logger) or controller
            return query.callWhy(logger, cdo, "GetPalStorageDataByPlayerUID", world, uid)
        end,
    },
    {
        -- Filet. Parcours global, donc hors boucle et une seule fois (regle 2 du module) :
        -- le resultat est mis en cache par query.palStorage.
        name = "FindAllOf(PalPlayerDataPalStorage)",
        resolve = function(logger)
            for _, candidate in ipairs(query.findAll(logger, "PalPlayerDataPalStorage")) do
                -- Le CDO figure toujours dans le resultat et n'a evidemment aucune page.
                if not string.find(query.nameOf(candidate), "Default__", 1, true)
                    and storageAnswers(logger, candidate) then
                    return candidate
                end
            end
            return nil
        end,
    },
}

--- UPalPlayerDataPalStorage : la Palbox, cote donnees.
-- C'est le point qui debloque M2 sans toucher a l'interface : les Pals sont lisibles meme
-- ecran ferme (docs/sdk-notes.md, chaine d'acces).
-- @return table|nil storage, string|nil nom de la voie retenue
function query.palStorage(logger)
    if safe.isValid(cache.palStorage) then return cache.palStorage, cache.palRoute end

    for _, route in ipairs(PAL_STORAGE_ROUTES) do
        local ok, storage = pcall(route.resolve, logger)
        if not ok then
            logger.debug("voie %s a leve : %s", route.name, tostring(storage))
        elseif storageAnswers(logger, storage) then
            cache.palStorage = storage
            cache.palRoute   = route.name
            logger.info("Palbox : voie retenue -- %s", route.name)
            return storage, route.name
        else
            logger.debug("voie %s : sans reponse", route.name)
        end
    end

    logger.error("Palbox introuvable : les %d voies d'acces ont echoue. "
        .. "Presser F9 (sonde) pour le detail voie par voie.", #PAL_STORAGE_ROUTES)
    return nil, nil
end

--- Les voies d'acces, exposees pour la sonde de diagnostic (PalKitBox, F9).
-- La sonde doit pouvoir les essayer TOUTES et rendre compte de chacune, la ou
-- query.palStorage s'arrete a la premiere qui repond.
query.palStorageRoutes = PAL_STORAGE_ROUTES
query.storageAnswers   = storageAnswers

return query
