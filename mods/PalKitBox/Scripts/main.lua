--[[
    PalKit -- PalKitBox
    M2, volet lecture : exporte le contenu de la Palbox en JSON.

    ------------------------------------------------------------------------------------
    POURQUOI CE MOD PEUT EXISTER MAINTENANT
    ------------------------------------------------------------------------------------
    M2 attendait les dumps du jeu. La passe headers 1.0 (docs/sdk-notes.md) a montre que la
    Palbox est lisible depuis les donnees du joueur, sans toucher a l'interface :

        PlayerController -> PlayerState -> GetPalStorage() -> GetSlot(page, slot)
                         -> slot:GetHandle() -> :TryGetIndividualParameter()

    Consequence : ce mod ne depend NI du spike de rendu, NI d'un ecran ouvert. C'est le
    premier module reel du projet, et il tourne Palbox fermee.

    ------------------------------------------------------------------------------------
    CE QU'IL FAIT, ET CE QU'IL NE FAIT PAS
    ------------------------------------------------------------------------------------
    F7  -> parcourt toutes les pages, ecrit un JSON a cote du mod, resume dans le log.
    F8  -> meme parcours, resume dans le log seulement (aucun fichier ecrit).

    Il ne modifie RIEN. Aucun hook, aucun setter, aucune ecriture dans le jeu : un export
    rate ne peut pas abimer une sauvegarde.

    ------------------------------------------------------------------------------------
    LE JSON PORTE SES PROPRES ECHECS
    ------------------------------------------------------------------------------------
    Chaque champ vient d'une signature au statut "header" : certaine cote C++, non prouvee
    cote Lua. Plutot que d'abandonner au premier champ illisible, on collecte les echecs
    dans `warnings` et on exporte le reste. Le premier passage en jeu dira donc exactement
    quelles lignes de sdk-notes.md passent en verifie -- c'est le but de ce premier jet
    autant que l'export lui-meme.
]]

local log    = require("log")
local safe   = require("safe")
local config = require("config")
local query  = require("query")
local palio  = require("palio")

local MOD_NAME = "PalKitBox"
local VERSION  = "0.1.0"

local logger = log.new("Box")

-- ------------------------------------------------------------------ configuration

local DEFAULTS = {
    debug = false,
    keys = {
        export  = "F7", -- export JSON complet
        summary = "F8", -- resume dans le log, sans fichier
    },
    -- Garde-fou : la Palbox fait 30 pages en 1.0, mais un serveur moddé peut annoncer
    -- n'importe quoi. On ne boucle jamais sur une borne venue du jeu sans plafond.
    maxPages         = 200,
    maxSlotsPerPage  = 200,
}

local cfg = config.new({ modName = MOD_NAME, defaults = DEFAULTS, logger = logger })

-- ------------------------------------------------------------------ lecture d'un Pal

--- Collecteur d'avertissements : un champ illisible est note une fois, pas a chaque Pal.
local function newWarnings()
    local seen, list = {}, {}
    return {
        add = function(field, detail)
            if seen[field] then return end
            seen[field] = true
            list[#list + 1] = detail and (field .. " : " .. detail) or field
        end,
        list = list,
    }
end

--- Convertit un TArray moteur en table Lua. Renvoie nil si la conversion echoue.
-- UE4SS expose ForEach sur les TArray ; l'element recu est un wrapper dont il faut
-- extraire la valeur avec :get(). Les deux etapes peuvent manquer selon le build, d'ou
-- le double repli.
local function toList(arr)
    if arr == nil then return nil end

    local out = {}
    local ok = pcall(function()
        arr:ForEach(function(_, element)
            local value = element
            local gotOk, got = pcall(function() return element:get() end)
            if gotOk then value = got end
            out[#out + 1] = query.str(value)
        end)
    end)
    if ok then return out end

    -- Repli : acces indexe classique.
    out = {}
    local okLen, len = pcall(function() return #arr end)
    if not okLen or type(len) ~= "number" then return nil end
    for i = 1, len do
        local okItem, item = pcall(function() return arr[i] end)
        out[#out + 1] = okItem and query.str(item) or nil
    end
    return out
end

--- Lit un champ de FPalIndividualCharacterSaveParameter, en notant l'echec eventuel.
local function readField(saveParam, field, warnings)
    local value = safe.get(saveParam, field)
    if value == nil then
        warnings.add(field, "illisible ou absent")
        return nil
    end
    return value
end

--- Extrait un Pal depuis son UPalIndividualCharacterParameter.
-- Source de tous les noms : ModdingKit 62fad41, PalIndividualCharacterSaveParameter.h
-- et PalIndividualCharacterParameter.h (docs/sdk-notes.md).
local function readPal(param, warnings)
    local saveParam = safe.get(param, "SaveParameter")
    if saveParam == nil then
        warnings.add("SaveParameter", "propriete inaccessible -- tout le reste en depend")
        return nil
    end

    local pal = {}

    pal.species   = query.str(readField(saveParam, "CharacterID", warnings))
    pal.nickname  = query.str(readField(saveParam, "NickName", warnings))
    pal.gender    = readField(saveParam, "Gender", warnings)
    pal.level     = readField(saveParam, "Level", warnings)
    pal.rank      = readField(saveParam, "Rank", warnings)
    pal.rare      = readField(saveParam, "IsRarePal", warnings)
    pal.awakening = readField(saveParam, "bIsAwakening", warnings)

    -- IVs. Nommes Talent_* dans le jeu ; on garde le vocabulaire du jeu pour que la
    -- correspondance avec le header reste evidente a la relecture.
    pal.ivs = {
        hp      = readField(saveParam, "Talent_HP", warnings),
        melee   = readField(saveParam, "Talent_Melee", warnings),
        shot    = readField(saveParam, "Talent_Shot", warnings),
        defense = readField(saveParam, "Talent_Defense", warnings),
    }

    -- Ames (soul upgrades) : Rank_* est distinct de Rank, qui est la condensation.
    pal.souls = {
        hp         = readField(saveParam, "Rank_HP", warnings),
        attack     = readField(saveParam, "Rank_Attack", warnings),
        defence    = readField(saveParam, "Rank_Defence", warnings),
        craftSpeed = readField(saveParam, "Rank_CraftSpeed", warnings),
    }

    local passives = toList(safe.get(saveParam, "PassiveSkillList"))
    if passives == nil then
        warnings.add("PassiveSkillList", "TArray non convertible")
    else
        pal.passives = passives
    end

    -- Controle croise volontaire : le meme niveau, lu une fois en propriete et une fois
    -- par le getter. Si les deux concordent en jeu, les getters de
    -- UPalIndividualCharacterParameter sont appelables depuis le Lua -- et toute la
    -- colonne "Getter" de sdk-notes.md devient exploitable (aptitudes au travail en tete,
    -- ou seul le getter tient compte de la condensation et des passifs).
    local level = query.call(param, "GetLevel")
    if level ~= nil then pal.levelViaGetter = level end

    return pal
end

-- ------------------------------------------------------------------ parcours de la Palbox

--- Parcourt toutes les pages et renvoie le rapport complet.
-- @return table|nil rapport
local function collect()
    local storage = query.palStorage(logger)
    if storage == nil then
        logger.always("ERROR", "Palbox inaccessible. Monde charge ? En multi/serveur, presser INS.")
        return nil
    end

    local warnings = newWarnings()

    local pageNum = query.call(storage, "GetPageNum") or safe.get(storage, "PageNum")
    local slotNum = safe.get(storage, "SlotNumInPage")

    if type(pageNum) ~= "number" or type(slotNum) ~= "number" then
        logger.always("ERROR",
            "Dimensions de la Palbox illisibles (pages=%s, slots/page=%s). "
            .. "GetPageNum/SlotNumInPage ont change de signature.",
            tostring(pageNum), tostring(slotNum))
        return nil
    end

    local maxPages = cfg.get("maxPages", DEFAULTS.maxPages)
    local maxSlots = cfg.get("maxSlotsPerPage", DEFAULTS.maxSlotsPerPage)
    if pageNum > maxPages then
        logger.warn("le jeu annonce %d pages, plafonne a %d", pageNum, maxPages)
        pageNum = maxPages
    end
    if slotNum > maxSlots then
        logger.warn("le jeu annonce %d slots/page, plafonne a %d", slotNum, maxSlots)
        slotNum = maxSlots
    end

    local report = {
        meta = {
            mod        = MOD_NAME,
            version    = VERSION,
            generatedAt= os.date("%Y-%m-%d %H:%M:%S"),
            pageCount  = pageNum,
            slotsPerPage = slotNum,
        },
        pals = {},
    }

    local empty, unreadable = 0, 0

    -- Indices a base 0 cote moteur : GetSlot(pageIndex, slotIndex) suit la convention C++.
    for page = 0, pageNum - 1 do
        for slotIndex = 0, slotNum - 1 do
            local slot = query.call(storage, "GetSlot", page, slotIndex)

            if slot == nil or not safe.isValid(slot) then
                unreadable = unreadable + 1
            elseif query.call(slot, "IsEmpty") == true then
                empty = empty + 1
            else
                local handle = query.call(slot, "GetHandle")
                local param  = handle and query.call(handle, "TryGetIndividualParameter")

                if param == nil then
                    unreadable = unreadable + 1
                    warnings.add("TryGetIndividualParameter", "handle sans parametre individuel")
                else
                    local pal = readPal(param, warnings)
                    if pal then
                        pal.page   = page
                        pal.slot   = slotIndex
                        pal.locked = query.call(slot, "IsLocked") == true
                        report.pals[#report.pals + 1] = pal
                    else
                        unreadable = unreadable + 1
                    end
                end
            end
        end
    end

    report.meta.palCount        = #report.pals
    report.meta.emptySlots      = empty
    report.meta.unreadableSlots = unreadable
    report.warnings             = warnings.list

    return report
end

--- Resume lisible dans UE4SS.log.
local function logSummary(report)
    logger.always("INFO", "Palbox : %d Pals, %d slots vides, %d slots illisibles (%d pages x %d)",
        report.meta.palCount, report.meta.emptySlots, report.meta.unreadableSlots,
        report.meta.pageCount, report.meta.slotsPerPage)

    -- Trois exemples suffisent a juger si la lecture est correcte, sans noyer le log.
    for i = 1, math.min(3, #report.pals) do
        local pal = report.pals[i]
        logger.always("INFO", "  exemple %d : %s \"%s\" niv %s rang %s (page %d, slot %d)",
            i, tostring(pal.species), tostring(pal.nickname),
            tostring(pal.level), tostring(pal.rank), pal.page, pal.slot)
    end

    if #report.warnings > 0 then
        logger.always("WARN", "%d champ(s) illisible(s) -- a reporter dans docs/sdk-notes.md :",
            #report.warnings)
        for _, w in ipairs(report.warnings) do
            logger.always("WARN", "  - %s", w)
        end
    else
        logger.always("INFO", "Aucun champ illisible : toutes les entrees header sont confirmees.")
    end
end

-- ------------------------------------------------------------------ actions

local writer = nil -- cree paresseusement : inutile tant qu'aucun export n'est demande

local function runExport()
    -- Toute lecture d'UObject passe par le game thread (brief SS3.7).
    safe.gameThread(logger, "export Palbox", function()
        logger.always("INFO", "======== Export Palbox : debut ========")

        local report = collect()
        if report == nil then
            logger.always("ERROR", "======== Export interrompu ========")
            return
        end

        logSummary(report)

        if writer == nil then
            writer = palio.new({ modName = MOD_NAME, logger = logger, prefix = "palbox" })
        end
        writer.writeJson("export", report)

        logger.always("INFO", "======== Export Palbox : fin ========")
    end)
end

local function runSummary()
    safe.gameThread(logger, "resume Palbox", function()
        local report = collect()
        if report ~= nil then logSummary(report) end
    end)
end

-- ------------------------------------------------------------------ demarrage
--
-- Chaque enregistrement est independant (brief SS3.7) : un keybind rate n'emporte pas
-- l'autre, et le mod reste utilisable a moitie plutot que muet.

safe.call(logger, "chargement config", function() cfg.load() end)
log.setDebug(cfg.get("debug", false) == true)

logger.banner({
    mod   = VERSION,
    ue4ss = type(UE4SS) == "table" and "detecte" or "inconnu",
    game  = "Palworld 1.0.x",
})

if type(Key) ~= "table" then
    logger.fatalOnce("La table globale Key est absente : build UE4SS inattendu. "
        .. "Aucun keybind ne peut etre enregistre.")
else
    local exportKey  = cfg.get("keys.export", DEFAULTS.keys.export)
    local summaryKey = cfg.get("keys.summary", DEFAULTS.keys.summary)

    safe.keybind(logger, exportKey .. " (export Palbox)", Key[exportKey], nil, runExport)
    safe.keybind(logger, summaryKey .. " (resume Palbox)", Key[summaryKey], nil, runSummary)

    logger.always("INFO", "Palbox : %s exporte en JSON, %s resume dans le log.",
        exportKey, summaryKey)
end

-- Un changement de monde invalide tous les objets caches. On ne peut pas s'accrocher a un
-- evenement de chargement sans hook ; query.reset() est donc appele au demarrage, et le
-- cache se revalide de lui-meme a chaque acces (IsValid).
query.reset()
