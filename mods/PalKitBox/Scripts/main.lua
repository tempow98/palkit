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
    F11 -> sonde : essaie les 4 voies d'acces a la Palbox et dit laquelle repond.

    Il ne modifie AUCUNE DONNEE : pas un setter, pas un hook, pas une ecriture de
    sauvegarde. Un export rate ne peut pas abimer une partie.

    Une nuance, ajoutee au run 5 et arbitree avec Lucas : le mod appelle
    `RequestPalBoxSyncPage_ToServer` page par page. C'est la fonction que l'ecran Palbox
    utilise lui-meme quand le joueur tourne les pages, et elle ne fait que *demander
    l'envoi* de donnees qui existent deja cote serveur. Sans elle, l'export ne contient
    qu'une page sur 32 : le jeu ne replique que la page synchronisee (run 4 : 30 Pals lus
    sur 727 slots occupes). L'etat de synchronisation est restaure en fin de parcours, et
    `syncPages = false` dans settings.json rend au mod un comportement strictement passif.

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
local query     = require("query")
local palio     = require("palio")
local json      = require("json") -- pour json.array : marquer les listes vides comme listes
local palfilter = require("palfilter") -- M2 v1 : filtres, tri, dominance

local MOD_NAME = "PalKitBox"
local VERSION  = "0.1.0"

local logger = log.new("Box")

-- ------------------------------------------------------------------ configuration

local DEFAULTS = {
    debug = false,
    keys = {
        export  = "F7", -- export JSON complet
        summary = "F8", -- resume dans le log, sans fichier
        -- F11 et pas F9 : ton PalKitDump occupe deja F9 (dump d'objets) et F10 (acteurs).
        -- Au 2e run, une pression sur F9 declenchait les deux -- un dump de 127 Mo qui fige
        -- le jeu, juste avant la sonde. Surchargeable dans settings.json.
        probe   = "F11", -- sonde de diagnostic : quelle voie d'acces a la Palbox repond ?
        search  = "F12", -- execute les requetes de `queries` ci-dessous
    },

    -- M2 v1 -- LES REQUETES SE DECLARENT ICI, dans settings.json.
    --
    -- Il n'y a pas de champ de saisie en jeu, et il n'y en aura pas tant que la brique de
    -- rendu n'est pas ecrite. Plutot que d'attendre, les requetes sont declaratives : on
    -- edite settings.json, on presse F12, on lit le resultat. C'est aussi ce qui les rend
    -- rejouables a l'identique et versionnables.
    --
    -- Criteres : species (sous-chaine), speciesExact, levelMin/levelMax, ivTotalMin,
    -- ivMin { hp, melee, shot, defense }, gender (1 male / 2 femelle), rankMin,
    -- rare, awakening, locked, passives (tous), passivesAny (au moins un), page.
    -- Tri : sort = { { field = "ivTotal", desc = true }, ... }  -- champ ou "ivTotal".
    -- `dominated = true` remplace le filtre par la recherche des doublons domines.
    queries = {
        {
            name  = "meilleurs IVs",
            sort  = { { field = "ivTotal", desc = true } },
            limit = 20,
        },
        {
            name     = "legendaires",
            criteria = { passives = { "Legend" } },
            sort     = { { field = "ivTotal", desc = true } },
        },
        {
            name     = "rares",
            criteria = { rare = true },
            sort     = { { field = "level", desc = true } },
        },
        {
            -- Le coeur de M2 : ceux qu'on peut condenser ou relacher sans rien perdre.
            name      = "doublons domines",
            dominated = true,
        },
    },
    -- Garde-fou : la Palbox fait 30 pages en 1.0, mais un serveur moddé peut annoncer
    -- n'importe quoi. On ne boucle jamais sur une borne venue du jeu sans plafond.
    maxPages         = 200,
    maxSlotsPerPage  = 200,

    -- Le jeu ne replique que la page synchronisee : sans cette passe, l'export ne contient
    -- qu'une page sur 32 (constate au run 4). On appelle donc, page par page, la fonction
    -- que l'ecran Palbox utilise lui-meme -- RequestPalBoxSyncPage_ToServer. Aucune donnee
    -- n'est modifiee, mais l'etat de synchronisation change : mettre `false` rend au mod un
    -- comportement strictement passif, au prix d'un export limite a la page courante.
    syncPages        = true,
    syncDelayMs      = 250, -- attente de la reponse serveur, par page
}

local cfg = config.new({ modName = MOD_NAME, defaults = DEFAULTS, logger = logger })

-- ------------------------------------------------------------------ lecture d'un Pal

--- Collecteur d'avertissements : un champ illisible est note une fois, pas a chaque Pal.
-- `note` sert aux constats qui ne sont pas des echecs (quelle API a repondu, par exemple) :
-- les melanger aux avertissements ferait passer un export sain pour un export degrade.
-- `counts` compte les occurrences : sans lui, un échec sur 1 Pal et un échec sur 727 se
-- ressemblent dans le log. Au run 4, seize champs étaient signalés comme illisibles alors
-- que 30 Pals sortaient parfaitement -- la fréquence était la seule information qui
-- distinguait « cas isolé » de « rien ne marche ».
local function newWarnings()
    local seen, list, notes, counts = {}, {}, {}, {}
    return {
        add = function(field, detail)
            counts[field] = (counts[field] or 0) + 1
            if seen[field] then return end
            seen[field] = true
            list[#list + 1] = detail and (field .. " : " .. detail) or field
        end,
        note = function(message)
            if seen[message] then return end
            seen[message] = true
            notes[#notes + 1] = message
        end,
        list   = list,
        notes  = notes,
        counts = counts,
    }
end

-- `query.toList` et `query.scalar` vivent dans shared/query.lua : tout mod qui lit des
-- donnees du jeu en a besoin, et les y placer les rend testables hors jeu pour de vrai.
local toList = query.toList


local scalar = query.scalar


--- Lit un champ de FPalIndividualCharacterSaveParameter, en notant l'echec eventuel.
local function readField(saveParam, field, warnings)
    local value = safe.get(saveParam, field)
    if value == nil then
        warnings.add(field, "illisible ou absent")
        return nil
    end

    local converted = scalar(value)
    if converted == nil then
        warnings.add(field, string.format(
            "type %s non convertible (ni ToString, ni get, ni GetValue)", type(value)))
        return nil
    end
    return converted
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

    -- Le getter d'abord, la propriété du struct ensuite. Un TArray lu sur un struct n'a pas
    -- toujours d'UObject propriétaire -- c'est ce que disait l'erreur du run 4, « Tried
    -- calling a member function but the UObject instance is nullptr » -- alors que le
    -- retour d'une UFUNCTION est un vrai wrapper.
    local passives, via, detail = toList(query.call(param, "GetPassiveSkillList"))
    if passives == nil or #passives == 0 then
        local fallback, viaProp, detailProp = toList(safe.get(saveParam, "PassiveSkillList"))
        if fallback ~= nil then
            passives, via, detail = fallback, (viaProp and viaProp .. " (propriete)"), detailProp
        end
    elseif via then
        via = via .. " (getter)"
    end

    if passives == nil then
        warnings.add("PassiveSkillList", "TArray non convertible -- " .. tostring(detail))
    else
        pal.passives = passives
        -- La voie qui a marche est notee une fois : elle vaudra pour tous les TArray du
        -- jeu (EquipWaza, MasteredWaza, CraftSpeeds...), donc pour tout M2 v1.
        warnings.note("TArray lus via " .. tostring(via))
    end

    -- Controle croise volontaire : le meme niveau, lu une fois en propriete et une fois
    -- par le getter. Si les deux concordent en jeu, les getters de
    -- UPalIndividualCharacterParameter sont appelables depuis le Lua -- et toute la
    -- colonne "Getter" de sdk-notes.md devient exploitable (aptitudes au travail en tete,
    -- ou seul le getter tient compte de la condensation et des passifs).
    -- Passe par scalar comme tout le reste : un getter peut rendre un userdata, et c'est
    -- exactement ce qui a fait perdre l'export complet du run 3.
    local level = scalar(query.call(param, "GetLevel"))
    if level ~= nil then pal.levelViaGetter = level end

    return pal
end

-- ------------------------------------------------------------------ parcours de la Palbox

--- Parcourt toutes les pages et renvoie le rapport complet.
-- @return table|nil rapport
--- Rassemble les slots de la Palbox depuis TOUTES les sources connues, dédoublonnés.
--
-- Pourquoi ne pas se contenter de la pagination : au run 4, `GetSlot(page, slot)` a rendu
-- 960 slots dont **une seule page** portait des données. Les 697 autres slots occupés
-- étaient des coquilles — le jeu ne réplique côté client que la page synchronisée
-- (`SyncPageIndex` / `bIsForceSyncAllSlot` dans `UPalPlayerDataPalStorage`).
--
-- Les deux premières sources contournent la pagination sans rien écrire :
--   * `TargetContainer` est le conteneur complet (`Num()`, `Get(i)`) ;
--   * `CachedNonEmptySlots_InServer` est la liste tenue côté serveur — et en solo, le
--     joueur *est* le serveur.
-- L'union dédoublonnée par nom d'objet garantit qu'on ne rate rien et qu'on ne compte
-- rien deux fois.
-- @return table liste de { slot, page, index, source }
local function gatherSlots(storage, pageNum, slotNum, warnings)
    local slots, seen = {}, {}

    local function keep(slot, page, index, source)
        if not safe.isValid(slot) then return false end
        local id = query.nameOf(slot)
        if seen[id] then return false end
        seen[id] = true
        slots[#slots + 1] = { slot = slot, page = page, index = index, source = source }
        return true
    end

    -- Source 1 : le conteneur complet.
    local container = safe.get(storage, "TargetContainer")
    if safe.isValid(container) then
        local total = query.callWhy(logger, container, "Num")
        if type(total) == "number" and total > 0 then
            local added = 0
            for i = 0, total - 1 do
                local slot = query.call(container, "Get", i)
                -- Les indices du conteneur sont continus : page et rang s'en déduisent.
                if keep(slot, math.floor(i / slotNum), i % slotNum, "container") then
                    added = added + 1
                end
            end
            warnings.note(string.format("TargetContainer : %d slots sur %d annonces",
                added, total))
        end
    end

    -- Source 2 : le cache serveur. `keepObjects` : ce sont des slots, pas des noms.
    local cached, viaCache = toList(safe.get(storage, "CachedNonEmptySlots_InServer"), true)
    if cached ~= nil and #cached > 0 then
        local added = 0
        for _, slot in ipairs(cached) do
            -- Ces slots portent leur propre position : on la lit plutôt que de la deviner.
            local index = safe.get(slot, "SlotIndex")
            index = type(index) == "number" and index or 0
            if keep(slot, math.floor(index / slotNum), index % slotNum, "cache serveur") then
                added = added + 1
            end
        end
        warnings.note(string.format("CachedNonEmptySlots_InServer : %d entrees, %d nouvelles "
            .. "(via %s)", #cached, added, tostring(viaCache)))
    end

    -- Source 3 : la pagination, qui reste la référence pour les positions.
    for page = 0, pageNum - 1 do
        for index = 0, slotNum - 1 do
            keep(query.call(storage, "GetSlot", page, index), page, index, "pagination")
        end
    end

    return slots
end

local function collect()
    local storage, route = query.palStorage(logger)
    if storage == nil then
        logger.always("ERROR", "Palbox inaccessible. Monde charge ? En multi/serveur, presser INS. "
            .. "Presser F9 pour savoir laquelle des voies d'acces echoue, et pourquoi.")
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
            -- Quelle voie d'acces a repondu : l'information qui fait passer la ligne
            -- correspondante de docs/sdk-notes.md en verifie.
            storageRoute = route,
        },
        pals = {},
    }

    local empty, unreadable, partial = 0, 0, 0

    --- Lit les slots d'une page. Les slots sont re-resolus a chaque appel : apres une
    -- resynchronisation, rien ne garantit que les objets memorises soient encore ceux que
    -- le jeu utilise.
    local function readPage(page)
        for slotIndex = 0, slotNum - 1 do
            local slot = query.call(storage, "GetSlot", page, slotIndex)
            local entry = { source = "page synchronisee" }

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
                        pal.source = entry.source
                        pal.locked = query.call(slot, "IsLocked") == true
                        report.pals[#report.pals + 1] = pal

                        -- Un Pal sans espece n'est pas un Pal lu : c'est une coquille.
                        -- Le run 4 en a produit 697 sur 727 et les a comptes comme lus,
                        -- ce qui a masque le vrai probleme (voir plus bas) derriere un
                        -- resume rassurant. L'espece est le champ temoin : s'il manque,
                        -- rien d'utile n'a ete lu.
                        if pal.species == nil then partial = partial + 1 end
                    else
                        unreadable = unreadable + 1
                    end
                end
            end
        end
    end

    --- Ferme le rapport et le rend a l'appelant.
    local function finish(onDone)
        report.meta.slotsOccupied    = #report.pals
        report.meta.palCount         = #report.pals - partial
        report.meta.partialPals      = partial
        report.meta.emptySlots       = empty
        report.meta.unreadableSlots  = unreadable
        -- Marquees comme listes : sans ca, un export sans avertissement sort `"warnings": {}`
        -- et un export degrade `"warnings": [...]`. Un champ qui change de type selon son
        -- contenu est un piege pour qui lit le fichier.
        report.warnings              = json.array(warnings.list)
        report.notes                 = json.array(warnings.notes)
        report.fieldFailures         = warnings.counts
        onDone(report)
    end

    -- ---------------------------------------------------------------- parcours des pages
    --
    -- Le jeu ne replique que la page synchronisee : lire les 32 pages d'affilee ne rend que
    -- des coquilles (run 4 : 30 Pals sur 727). On appelle donc, page par page, la fonction
    -- que l'ecran Palbox appelle lui-meme quand le joueur tourne les pages :
    -- APalPlayerState::RequestPalBoxSyncPage_ToServer -- UFUNCTION(BlueprintCallable,
    -- Reliable, Server), presente au runtime (ObjectDump 2026-08-15).
    --
    -- Ce n'est PAS une modification de sauvegarde : on demande l'envoi de donnees qui
    -- existent deja cote serveur. Mais c'est un appel qui change l'etat de synchronisation,
    -- donc hors du read-only strict du brief SS3.2 -- arbitre avec Lucas le 2026-08-15.
    -- La page d'origine est restauree a la fin, et `syncPages = false` rend au mod son
    -- comportement strictement passif.
    local playerState = query.playerState(logger)
    local syncEnabled = cfg.get("syncPages", DEFAULTS.syncPages) == true
        and pageNum > 1 and safe.isValid(playerState)

    if not syncEnabled then
        if cfg.get("syncPages", DEFAULTS.syncPages) ~= true then
            warnings.note("syncPages desactive : seule la page courante sera lisible")
        end
        readPage(0)
        for page = 1, pageNum - 1 do readPage(page) end
        return function(onDone) finish(onDone) end
    end

    local originalPage = safe.get(storage, "SyncPageIndex")
    local delayMs = cfg.get("syncDelayMs", DEFAULTS.syncDelayMs)

    -- Renvoie un lanceur : la lecture est asynchrone, l'appelant fournit la suite.
    return function(onDone)
        local page = 0

        local function step()
            if page >= pageNum then
                -- Remettre le jeu dans l'etat ou on l'a trouve.
                if type(originalPage) == "number" then
                    query.call(playerState, "RequestPalBoxSyncPage_ToServer", originalPage)
                    warnings.note(string.format("page de synchronisation restauree a %d",
                        originalPage))
                end
                finish(onDone)
                return
            end

            local current = page
            page = page + 1

            query.callWhy(logger, playerState, "RequestPalBoxSyncPage_ToServer", current)

            -- Laisser la reponse du serveur arriver avant de lire.
            local ok = pcall(ExecuteWithDelay, delayMs, function()
                safe.gameThread(logger, "lecture page " .. current, function()
                    readPage(current)
                    step()
                end)
            end)

            if not ok then
                logger.always("WARN", "ExecuteWithDelay indisponible : lecture immediate, "
                    .. "les pages non encore repliquees resteront vides.")
                readPage(current)
                step()
            end
        end

        logger.always("INFO", "Parcours des %d pages avec resynchronisation (%d ms/page, "
            .. "~%.0f s au total).", pageNum, delayMs, pageNum * delayMs / 1000)
        step()
    end
end

--- Resume lisible dans UE4SS.log.
local function logSummary(report)
    logger.always("INFO", "Palbox : %d Pals lus, %d coquilles vides, %d slots libres, "
        .. "%d slots illisibles (%d pages x %d)",
        report.meta.palCount, report.meta.partialPals, report.meta.emptySlots,
        report.meta.unreadableSlots, report.meta.pageCount, report.meta.slotsPerPage)

    -- Le diagnostic qui manquait au run 4 : un slot occupé dont aucun champ ne sort n'est
    -- pas un Pal, et la répartition par page dit *pourquoi*.
    if report.meta.partialPals > 0 then
        local pagesOk = {}
        for _, pal in ipairs(report.pals) do
            if pal.species ~= nil then pagesOk[pal.page] = (pagesOk[pal.page] or 0) + 1 end
        end
        local pageList, count = {}, 0
        for page in pairs(pagesOk) do
            count = count + 1
            pageList[#pageList + 1] = page
        end
        table.sort(pageList)

        logger.always("WARN", "%d slots occupes n'ont rendu AUCUN champ (%.0f %%).",
            report.meta.partialPals,
            100 * report.meta.partialPals / math.max(1, report.meta.slotsOccupied))
        logger.always("WARN", "Pages reellement lisibles : %d sur %d%s",
            count, report.meta.pageCount,
            count > 0 and (" (" .. table.concat(pageList, ", ", 1, math.min(#pageList, 8)) .. ")") or "")
        if count <= 1 then
            logger.always("WARN", "Une seule page repond : le jeu ne REPLIQUE que la page "
                .. "synchronisee (SyncPageIndex). Les autres slots existent mais leurs "
                .. "donnees ne sont pas cote client.")
        end
    end

    -- Trois exemples suffisent a juger si la lecture est correcte, sans noyer le log.
    for i = 1, math.min(3, #report.pals) do
        local pal = report.pals[i]
        logger.always("INFO", "  exemple %d : %s \"%s\" niv %s rang %s (page %d, slot %d)",
            i, tostring(pal.species), tostring(pal.nickname),
            tostring(pal.level), tostring(pal.rank), pal.page, pal.slot)
    end

    if #report.warnings > 0 then
        logger.always("WARN", "%d champ(s) illisible(s) -- a reporter dans docs/sdk-notes.md "
            .. "(entre parentheses : sur combien de Pals) :", #report.warnings)
        for _, w in ipairs(report.warnings) do
            -- La fréquence sépare le cas isolé du blocage général : sans elle, les deux
            -- s'affichent à l'identique.
            local field = string.match(w, "^([^ :]+)")
            local n = field and report.fieldFailures[field]
            logger.always("WARN", "  - %s%s", w, n and string.format("  (x%d)", n) or "")
        end
    elseif report.meta.palCount == 0 then
        -- Le faux vert du 2e run : "aucun champ illisible" sur zero Pal lu. La liste des
        -- avertissements est vide parce qu'aucun champ n'a jamais ete TENTE -- ce qui est
        -- l'inverse d'une confirmation. Un export sans Pal est un echec, et doit le dire.
        logger.always("ERROR", "ECHEC : aucun Pal lu. La liste d'avertissements est vide "
            .. "parce qu'aucun champ n'a pu etre tente, pas parce que tout est confirme.")
        if report.meta.unreadableSlots > 0 then
            logger.always("ERROR", "  %d slots sur %d n'ont pas repondu : c'est l'acces aux "
                .. "slots qui casse, pas la lecture des champs. Presser F9.",
                report.meta.unreadableSlots,
                report.meta.pageCount * report.meta.slotsPerPage)
        end
    else
        logger.always("INFO", "Aucun champ illisible sur %d Pals lus : toutes les entrees "
            .. "header sont confirmees.", report.meta.palCount)
    end
end

-- ------------------------------------------------------------------ M2 v1 : requetes

--- Une ligne lisible pour un Pal, dans le log.
local function palLine(pal)
    return string.format("%-26s niv %-3s IV=%-3d %s%s",
        tostring(pal.species), tostring(pal.level), palfilter.ivTotal(pal),
        pal.rare and "[rare] " or "",
        table.concat(pal.passives or {}, ", "))
end

--- Execute une requete declaree dans settings.json.
-- @return table { name, count, pals } pour le rapport JSON
local function runQuery(query, pals)
    local name = tostring(query.name or "sans nom")

    -- Recherche de doublons : une requete a part entiere, pas un filtre.
    if query.dominated then
        local dominated = palfilter.findDominated(pals, { ignoreGender = query.ignoreGender })

        logger.always("INFO", "--- %s : %d Pal(s) domine(s) ---", name, #dominated)
        for index = 1, math.min(#dominated, query.limit or 15) do
            local entry = dominated[index]
            logger.always("INFO", "  p%d/s%-2d %s", entry.pal.page, entry.pal.slot,
                palLine(entry.pal))
            logger.always("INFO", "      domine par p%d/s%-2d IV=%d%s",
                entry.by.page, entry.by.slot, palfilter.ivTotal(entry.by),
                entry.equal and "  (identiques)" or "")
        end
        if #dominated > (query.limit or 15) then
            logger.always("INFO", "  ... et %d autre(s), tous dans le JSON",
                #dominated - (query.limit or 15))
        end

        local rows = {}
        for _, entry in ipairs(dominated) do
            rows[#rows + 1] = {
                species = entry.pal.species,
                page = entry.pal.page, slot = entry.pal.slot,
                ivTotal = palfilter.ivTotal(entry.pal),
                dominatedByPage = entry.by.page, dominatedBySlot = entry.by.slot,
                dominatedByIvTotal = palfilter.ivTotal(entry.by),
                identical = entry.equal or false,
            }
        end
        return { name = name, kind = "dominated", count = #dominated,
                 results = json.array(rows) }
    end

    local matched = palfilter.filter(pals, query.criteria)
    local sorted  = palfilter.top(matched, query.sort, query.limit)

    logger.always("INFO", "--- %s : %d resultat(s)%s ---", name, #matched,
        query.limit and #matched > query.limit
            and string.format(", %d affiches", query.limit) or "")
    for index = 1, math.min(#sorted, 15) do
        logger.always("INFO", "  %2d. %s", index, palLine(sorted[index]))
    end

    return { name = name, kind = "filter", count = #matched,
             results = json.array(sorted) }
end

-- ------------------------------------------------------------------ sonde de diagnostic
--
-- Pourquoi cette touche existe : le premier essai en jeu (2026-08-15) a rendu une seule
-- ligne -- "GetPalStorage n'a rien renvoye" -- alors que la signature est bonne
-- (PalPlayerState.h:573) et que l'instance existe bel et bien au runtime (ObjectDump :
-- ...BP_PalPlayerState_C_2147480325.PalPlayerDataPalStorage_2147457951). Un echec qui ne
-- distingue pas "mauvais objet", "membre non appelable" et "objet vide" ne se corrige
-- qu'a l'aveugle. F9 essaie TOUTES les voies et rend compte de chacune.

--- Nom + classe d'un UObject, en une ligne. Les deux comptent : l'ObjectDump montre deux
-- BP_PalPlayerState_C vivants, que seul le nom complet distingue.
local function describe(obj)
    if obj == nil then return "<nil>" end
    if not safe.isValid(obj) then return "<invalide> " .. query.nameOf(obj) end

    local class = query.call(obj, "GetClass")
    local className = class and query.nameOf(class) or "<classe inconnue>"
    return string.format("%s [classe %s]", query.nameOf(obj), className)
end

--- Verifie qu'un storage est REELLEMENT exploitable, pas seulement valide.
-- C'est l'etape qui compte : un UObject valide dont GetSlot ne repond pas ferait echouer
-- l'export 960 slots plus loin en se declarant satisfait -- ce qui est arrive au 2e run.
-- @return boolean  vrai seulement si un slot a pu etre sorti du storage
local function probeStorageDepth(storage)
    local pages   = query.callWhy(logger, storage, "GetPageNum")
    local pagesP  = safe.get(storage, "PageNum")
    local slots   = safe.get(storage, "SlotNumInPage")

    logger.always("INFO", "    GetPageNum()      : %s", tostring(pages))
    logger.always("INFO", "    .PageNum          : %s", tostring(pagesP))
    logger.always("INFO", "    .SlotNumInPage    : %s", tostring(slots))

    local slot = query.callWhy(logger, storage, "GetSlot", 0, 0)
    logger.always("INFO", "    GetSlot(0,0)      : %s", describe(slot))
    if not safe.isValid(slot) then
        logger.always("WARN", "    -> les slots ne repondent pas : voie INEXPLOITABLE "
            .. "(des dimensions lisibles ne prouvent rien : ce sont deux proprietes)")
        return false
    end

    local isEmpty = query.callWhy(logger, slot, "IsEmpty")
    logger.always("INFO", "    slot:IsEmpty()    : %s", tostring(isEmpty))

    -- A partir d'ici la voie est exploitable : le reste renseigne sur la lecture d'un Pal,
    -- mais un premier slot vide n'a rien d'anormal et ne disqualifie pas la voie.
    local handle = query.callWhy(logger, slot, "GetHandle")
    logger.always("INFO", "    slot:GetHandle()  : %s", describe(handle))
    if not safe.isValid(handle) then return true end

    local param = query.callWhy(logger, handle, "TryGetIndividualParameter")
    logger.always("INFO", "    parametre individuel : %s", describe(param))
    if not safe.isValid(param) then return true end

    -- Le controle final : un champ reellement lu. S'il sort, toute la chaine tient.
    local saveParam = safe.get(param, "SaveParameter")
    local species   = saveParam and query.str(safe.get(saveParam, "CharacterID"))
    logger.always("INFO", "    SaveParameter.CharacterID : %s", tostring(species))
    return true
end

local function runDiagnostics()
    safe.gameThread(logger, "sonde Palbox", function()
        -- La sonde a besoin des messages DEBUG de query.callWhy : c'est tout son interet.
        local previousLevel = log.getLevel()
        log.setDebug(true)

        logger.always("INFO", "======== Sonde Palbox : debut ========")

        local controller = query.controller(logger)
        logger.always("INFO", "PlayerController : %s", describe(controller))
        logger.always("INFO", "World            : %s", describe(query.world(logger)))

        if controller == nil then
            logger.always("ERROR", "Pas de PlayerController : monde charge ? En multi, presser INS.")
            logger.always("INFO", "======== Sonde Palbox : fin ========")
            log.setLevel(previousLevel)
            return
        end

        -- Les deux PlayerState, cote a cote. S'ils different, la cause racine est trouvee.
        local viaGetter = query.callWhy(logger, controller, "GetPalPlayerState")
        local viaProp   = safe.get(controller, "PlayerState")
        logger.always("INFO", "PlayerState via GetPalPlayerState() : %s", describe(viaGetter))
        logger.always("INFO", "PlayerState via .PlayerState       : %s", describe(viaProp))
        if safe.isValid(viaGetter) and safe.isValid(viaProp)
            and query.nameOf(viaGetter) ~= query.nameOf(viaProp) then
            logger.always("WARN", "Les deux voies designent des objets DIFFERENTS "
                .. "-- c'est la cause la plus probable de l'echec du 15/08.")
        end

        -- Toutes les voies, meme apres qu'une ait abouti : on veut la carte complete.
        query.reset()
        local winner = nil

        for index, route in ipairs(query.palStorageRoutes) do
            logger.always("INFO", "--- Voie %d/%d : %s ---",
                index, #query.palStorageRoutes, route.name)

            local ok, storage = pcall(route.resolve, logger)
            if not ok then
                logger.always("ERROR", "    a leve : %s", tostring(storage))
            elseif not safe.isValid(storage) then
                logger.always("WARN", "    aucun objet")
            else
                logger.always("INFO", "    objet : %s", describe(storage))
                -- Le verdict vient de la sonde en profondeur, pas d'un second test
                -- independant : au 2e run, les deux se contredisaient a une ligne
                -- d'intervalle -- "voie inexploitable" suivi de "voie retenue".
                if probeStorageDepth(storage) and winner == nil then
                    winner = route.name
                end
            end
        end

        if winner then
            logger.always("INFO", "VERDICT : voie retenue -- %s", winner)
            logger.always("INFO", "F7 devrait desormais produire l'export.")
        else
            logger.always("ERROR", "VERDICT : aucune voie n'aboutit. "
                .. "Renvoyer ce log : les lignes DEBUG ci-dessus disent, pour chaque voie, "
                .. "si le membre est absent, non appelable, ou s'il leve.")
        end

        logger.always("INFO", "======== Sonde Palbox : fin ========")
        log.setLevel(previousLevel)
    end)
end

-- ------------------------------------------------------------------ ecriture

--- Dernier filet avant serialisation : ecarte ce que le JSON ne sait pas encoder.
--
-- `scalar` traite deja les champs connus a la lecture ; cette passe couvre ce qui aurait
-- echappe. La regle du run 3 : **une valeur exotique ne doit jamais coûter l'export
-- entier** -- 723 Pals correctement lus avaient ete perdus sur un seul champ. Ce qui est
-- ecarte est nomme par son chemin, donc corrigeable au prochain passage.
-- @return any nettoye
local function sanitize(value, path, dropped)
    local t = type(value)
    if value == nil or t == "number" or t == "string" or t == "boolean" then
        return value
    end

    if t == "table" then
        local out = {}
        for key, item in pairs(value) do
            local keyType = type(key)
            if keyType == "string" or keyType == "number" then
                local clean = sanitize(item, path .. "." .. tostring(key), dropped)
                if clean ~= nil then out[key] = clean end
            else
                dropped[#dropped + 1] = path .. " (cle de type " .. keyType .. ")"
            end
        end
        return out
    end

    local converted = scalar(value)
    if converted == nil then
        dropped[#dropped + 1] = string.format("%s (%s)", path, t)
    end
    return converted
end

-- ------------------------------------------------------------------ actions

local writer = nil -- cree paresseusement : inutile tant qu'aucun export n'est demande

local function runExport()
    -- Toute lecture d'UObject passe par le game thread (brief SS3.7).
    safe.gameThread(logger, "export Palbox", function()
        logger.always("INFO", "======== Export Palbox : debut ========")

        -- `collect` rend un LANCEUR, pas un rapport : le parcours resynchronise les pages
        -- une par une et doit attendre le serveur entre chaque. Tout ce qui suit la lecture
        -- vit donc dans la continuation.
        local start = collect()
        if start == nil then
            logger.always("ERROR", "======== Export interrompu ========")
            return
        end

        start(function(report)
        logSummary(report)

        local dropped = {}
        local clean = sanitize(report, "report", dropped)

        if #dropped > 0 then
            logger.always("WARN", "%d valeur(s) non encodable(s) ecartee(s) avant ecriture "
                .. "-- l'export part quand meme :", #dropped)
            for index = 1, math.min(#dropped, 10) do
                logger.always("WARN", "  - %s", dropped[index])
            end
            clean.warnings[#clean.warnings + 1] =
                string.format("%d valeur(s) non encodable(s) ecartee(s), voir le log", #dropped)
        end

        if writer == nil then
            writer = palio.new({ modName = MOD_NAME, logger = logger, prefix = "palbox" })
        end
        writer.writeJson("export", clean)

        logger.always("INFO", "======== Export Palbox : fin ========")
        end)
    end)
end

--- M2 v1 : lit la Palbox, puis execute toutes les requetes declarees.
local function runSearch()
    safe.gameThread(logger, "recherche Palbox", function()
        logger.always("INFO", "======== Recherche Palbox : debut ========")

        local start = collect()
        if start == nil then
            logger.always("ERROR", "======== Recherche interrompue ========")
            return
        end

        start(function(report)
            local queries = cfg.get("queries", DEFAULTS.queries)
            if type(queries) ~= "table" or #queries == 0 then
                logger.always("WARN", "Aucune requete declaree dans settings.json (`queries`).")
                logger.always("INFO", "======== Recherche Palbox : fin ========")
                return
            end

            logger.always("INFO", "Base : %d Pals lus. %d requete(s) a executer.",
                report.meta.palCount, #queries)

            -- Les coquilles fausseraient tout : un Pal sans espece ne peut ni etre filtre
            -- ni etre compare. On requete sur ce qui a vraiment ete lu.
            local base = {}
            for _, pal in ipairs(report.pals) do
                if pal.species ~= nil then base[#base + 1] = pal end
            end

            local out = {
                meta = {
                    mod = MOD_NAME, version = VERSION,
                    generatedAt = os.date("%Y-%m-%d %H:%M:%S"),
                    palCount = #base,
                },
                queries = {},
            }

            for _, q in ipairs(queries) do
                local ok, result = safe.call(logger, "requete " .. tostring(q.name),
                    runQuery, q, base)
                if ok and result then out.queries[#out.queries + 1] = result end
            end
            out.queries = json.array(out.queries)

            if writer == nil then
                writer = palio.new({ modName = MOD_NAME, logger = logger, prefix = "palbox" })
            end
            local dropped = {}
            writer.writeJson("recherche", sanitize(out, "recherche", dropped))

            logger.always("INFO", "======== Recherche Palbox : fin ========")
        end)
    end)
end

local function runSummary()
    safe.gameThread(logger, "resume Palbox", function()
        local start = collect()
        if start ~= nil then start(logSummary) end
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
    local probeKey   = cfg.get("keys.probe", DEFAULTS.keys.probe)

    safe.keybind(logger, exportKey .. " (export Palbox)", Key[exportKey], nil, runExport)
    safe.keybind(logger, summaryKey .. " (resume Palbox)", Key[summaryKey], nil, runSummary)
    safe.keybind(logger, probeKey .. " (sonde Palbox)", Key[probeKey], nil, runDiagnostics)

    local searchKey = cfg.get("keys.search", DEFAULTS.keys.search)
    safe.keybind(logger, searchKey .. " (recherche)", Key[searchKey], nil, runSearch)

    logger.always("INFO", "Palbox : %s exporte en JSON, %s resume dans le log, "
        .. "%s diagnostique les voies d'acces, %s execute les requetes.",
        exportKey, summaryKey, probeKey, searchKey)
end

-- Un changement de monde invalide tous les objets caches. On ne peut pas s'accrocher a un
-- evenement de chargement sans hook ; query.reset() est donc appele au demarrage, et le
-- cache se revalide de lui-meme a chaque acces (IsValid).
query.reset()
