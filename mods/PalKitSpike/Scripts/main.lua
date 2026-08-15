--[[
    PalKit -- PalKitSpike
    Mod JETABLE. Ce n'est pas la minimap : c'est une sonde de faisabilite.

    ------------------------------------------------------------------------------------
    POURQUOI CE MOD EXISTE
    ------------------------------------------------------------------------------------
    Le brief pose une contrainte non negociable : zero .pak, zero Blueprint, Lua UE4SS pur
    (SS3.1). Il la justifie en affirmant que PalMiniMap fonctionne ainsi. C'est faux --
    verification faite en aout 2026, PalMiniMap installe un PalMiniMap.pak dans LogicMods
    qui porte tout son visuel ; son Lua ne fait que la logique. Et UE4SS n'expose aucun
    binding ImGui au Lua (les tabs GUI sont reserves aux mods C++).

    Il ne reste donc qu'UNE voie pour afficher quoi que ce soit en Lua pur : instancier un
    widget UMG deja cuit dans le jeu, et l'ajouter au viewport. Sur le papier c'est jouable
    -- tout le contenu vient du jeu, rien n'est cooke, la desinstallation reste "supprimer
    le dossier". En pratique, personne ne l'a prouve pour Palworld 1.0.

    Ce mod repond a cette seule question, avant qu'une ligne de minimap ne soit ecrite.

    ------------------------------------------------------------------------------------
    METHODE
    ------------------------------------------------------------------------------------
    F5 execute 4 paliers, chacun sous garde et chacun logge separement. Meme un echec
    complet est exploitable : il nous dit OU la chaine casse, ce qui suffit a choisir la
    suite. Aucun palier n'interrompt les suivants.

    F6 retire ce que F5 a ajoute, pour reessayer sans relancer le jeu.
]]

local log    = require("log")
local safe   = require("safe")
local config = require("config")

local MOD_NAME = "PalKitSpike"
local VERSION  = "0.1.0"

local logger = log.new("Spike")

-- Etat du spike. Volontairement minimal : ce mod ne survit pas au projet.
local state = {
    createdWidget = nil,
    candidates    = {},
}

-- ------------------------------------------------------------------ configuration

local DEFAULTS = {
    debug = true, -- le spike est un outil de diagnostic : verbeux par defaut
    probe = {
        -- Cibles nommees, tirees de l'ObjectDump du 2026-08-15. C'est le changement de
        -- fond depuis le premier essai : on ne cherche plus a deviner une convention de
        -- nommage, on connait les chemins exacts. Ordre = ordre d'essai du palier 3, du
        -- plus leger (une icone seule, peu de dependances de donnees, donc le test
        -- d'affichage le plus honnete) au plus lourd (la carte entiere).
        knownClasses = {
            "/Game/Pal/Blueprint/UI/UserInterface/InGame/Compass/WBP_CompassIconBase.WBP_CompassIconBase_C",
            "/Game/Pal/Blueprint/UI/UserInterface/InGame/Compass/WBP_Ingame_Compass.WBP_Ingame_Compass_C",
            "/Game/Pal/Blueprint/UI/UserInterface/Map/WBP_Map_Body.WBP_Map_Body_C",
            "/Game/Pal/Blueprint/UI/UserInterface/Map/WBP_Map_Base.WBP_Map_Base_C",
        },
        -- Fragments de secours, appliques au nom de classe COURT (jamais au chemin :
        -- "widget" matcherait "WidgetTree" dans presque tous les chemins du jeu).
        -- Tires de la convention reelle WBP_<Domaine><Element>_C.
        namePatterns   = { "compass", "map", "minimap", "radar", "overalluilayout" },
        maxCandidates  = 40,   -- borne de log : un dump complet noierait UE4SS.log
    },
}

local cfg = config.new({ modName = MOD_NAME, defaults = DEFAULTS, logger = logger })

-- ------------------------------------------------------------------ helpers

--- Nom lisible d'un UObject, sans jamais lever.
local function nameOf(obj)
    if obj == nil then return "<nil>" end
    local ok, name = pcall(function() return obj:GetFullName() end)
    if ok and type(name) == "string" then return name end
    ok, name = pcall(function() return obj:GetFName():ToString() end)
    if ok and type(name) == "string" then return name end
    return "<sans nom>"
end

--- Nom COURT de la classe d'un objet, sans le chemin.
-- Le filtrage doit porter la-dessus, pas sur le full name : celui-ci contient le chemin
-- complet, ou le fragment "widget" matche "WidgetTree" pour a peu pres tout le jeu.
local function classNameOf(obj)
    if obj == nil then return "<nil>" end
    local ok, name = pcall(function() return obj:GetClass():GetFName():ToString() end)
    if ok and type(name) == "string" then return name end
    return "<classe inconnue>"
end

--- Un widget est-il une instance a l'ecran, ou un simple modele ?
-- Piege releve au premier essai en jeu : les objets sous /Game/....:WidgetTree.X sont les
-- archetypes portes par le CDO de chaque WidgetBlueprint -- ils existent des le chargement
-- du package, sans que rien ne soit affiche. Les instances reelles vivent sous
-- /Engine/Transient (l'arbre du GameInstance). Les "3204 UserWidget vivants" du log du
-- 2026-08-15 etaient donc, pour l'essentiel, des modeles.
local function isLiveInstance(fullName)
    return string.find(fullName, "/Engine/Transient", 1, true) ~= nil
end

--- Vrai si `name` contient l'un des fragments (comparaison insensible a la casse).
local function matchesAny(name, patterns)
    local lower = string.lower(name)
    for _, fragment in ipairs(patterns) do
        if string.find(lower, string.lower(fragment), 1, true) then
            return true, fragment
        end
    end
    return false, nil
end

--- Ajoute un candidat, sans doublon de classe.
local function addCandidate(class, name, origin)
    for _, existing in ipairs(state.candidates) do
        if existing.name == name then return false end
    end
    state.candidates[#state.candidates + 1] = { class = class, name = name, origin = origin }
    return true
end

-- ------------------------------------------------------------------ palier 1

--- Le contexte de jeu est-il utilisable ?
-- Si ce palier echoue, tous les suivants sont sans objet : soit le monde n'est pas charge,
-- soit UEHelpers ne repond pas sur ce build. En multi, c'est le cas qui impose de presser
-- INS apres le chargement du monde.
local function stage1_context()
    logger.always("INFO", "--- Palier 1 : contexte de jeu ---")

    local ok, UEHelpers = pcall(require, "UEHelpers")
    if not ok or type(UEHelpers) ~= "table" then
        logger.always("ERROR", "Palier 1 KO : UEHelpers introuvable (%s)", tostring(UEHelpers))
        return nil
    end
    logger.always("INFO", "UEHelpers charge")

    -- safe.call renvoie (ok, resultat) : on ne garde que le resultat, l'echec etant
    -- deja logge par le garde lui-meme.
    local _, pc    = safe.call(logger, "GetPlayerController",
        function() return UEHelpers:GetPlayerController() end)
    local _, world = safe.call(logger, "GetWorld",
        function() return UEHelpers:GetWorld() end)

    logger.always("INFO", "PlayerController : %s (valide=%s)",
        nameOf(pc), tostring(safe.isValid(pc)))
    logger.always("INFO", "World            : %s (valide=%s)",
        nameOf(world), tostring(safe.isValid(world)))

    -- Le pawn se lit depuis le controller : appel moteur direct, pas de parcours du tableau
    -- global des UObject (brief SS5.3 -- c'est une note de perf qui vaudra pour M1).
    local pawn = safe.get(pc, "Pawn")
    logger.always("INFO", "Pawn             : %s (valide=%s)",
        nameOf(pawn), tostring(safe.isValid(pawn)))

    if not safe.isValid(pc) then
        logger.always("ERROR", "Palier 1 KO : pas de PlayerController valide. "
            .. "Monde charge ? En multi, presser INS apres le chargement.")
        return nil
    end

    logger.always("INFO", "Palier 1 OK")
    return { controller = pc, world = world, pawn = pawn }
end

-- ------------------------------------------------------------------ palier 2

--- Quelles classes de widgets sont mobilisables, et lesquelles ressemblent a une carte ?
--
-- Le premier essai en jeu (2026-08-15) a rendu "0 classes, 0 candidates", et le palier 3
-- n'a donc jamais tourne. Trois causes, toutes corrigees ici :
--   1. FindAllOf("WidgetBlueprintGeneratedClass") renvoie 0 sur ce build, alors que
--      l'ObjectDump en compte 668 -- cette voie de decouverte est morte. On passe
--      desormais par des chemins de classes CONNUS (voie A) et par les instances
--      vivantes (voie B).
--   2. les candidats n'etaient alimentes QUE par cette liste vide : les milliers de
--      UserWidget trouves juste apres etaient logges, puis jetes.
--   3. le filtre portait sur le full name (chemin compris), pas sur le nom de classe.
local function stage2_discover()
    logger.always("INFO", "--- Palier 2 : classes de widgets mobilisables ---")

    local patterns = cfg.get("probe.namePatterns", DEFAULTS.probe.namePatterns)
    local maxLog   = cfg.get("probe.maxCandidates", DEFAULTS.probe.maxCandidates)
    local known    = cfg.get("probe.knownClasses", DEFAULTS.probe.knownClasses)

    state.candidates = {}

    -- ---------------------------------------------------------------- voie A : chemins connus
    -- StaticFindObject ne trouve que ce qui est deja charge : un echec ici signifie
    -- "package non charge pour l'instant", pas "n'existe pas". D'ou le conseil de
    -- relancer carte ouverte.
    logger.always("INFO", "Voie A -- classes nommees (ObjectDump 2026-08-15) :")
    for _, path in ipairs(known) do
        local _, class = safe.call(logger, "StaticFindObject(" .. path .. ")",
            function() return StaticFindObject(path) end)

        if safe.isValid(class) then
            addCandidate(class, nameOf(class), "connue")
            logger.always("INFO", "  trouvee : %s", path)
        else
            logger.always("WARN", "  absente (package non charge ?) : %s", path)
        end
    end

    -- ---------------------------------------------------------------- voie B : instances vivantes
    local _, live = safe.call(logger, "FindAllOf(UserWidget)",
        function() return FindAllOf("UserWidget") end)

    if type(live) ~= "table" then
        logger.always("WARN", "FindAllOf(UserWidget) n'a rien retourne")
        live = {}
    end

    -- Inventaire par classe plutot que liste d'instances : la liste repetait dix fois la
    -- meme classe, l'inventaire est directement reversable dans docs/sdk-notes.md.
    local byClass, order = {}, {}
    local liveCount, templateCount = 0, 0

    for _, widget in ipairs(live) do
        local fullName = nameOf(widget)
        if isLiveInstance(fullName) then
            liveCount = liveCount + 1
            local className = classNameOf(widget)
            if byClass[className] == nil then
                byClass[className] = { count = 0, sample = widget }
                order[#order + 1] = className
            end
            byClass[className].count = byClass[className].count + 1
        else
            templateCount = templateCount + 1
        end
    end

    logger.always("INFO", "Voie B -- %d UserWidget au total : %d instances vivantes, "
        .. "%d modeles de CDO ignores", #live, liveCount, templateCount)

    table.sort(order, function(a, b)
        if byClass[a].count ~= byClass[b].count then
            return byClass[a].count > byClass[b].count
        end
        return a < b
    end)

    logger.always("INFO", "--- Inventaire des classes vivantes (%d classes, %d listees) ---",
        #order, math.min(#order, maxLog))
    for i = 1, math.min(#order, maxLog) do
        local className = order[i]
        logger.always("INFO", "  %4d x %s", byClass[className].count, className)
    end

    -- Candidats de secours : les classes vivantes dont le nom COURT evoque une carte.
    for _, className in ipairs(order) do
        local hit, fragment = matchesAny(className, patterns)
        if hit then
            local _, cls = safe.call(logger, "GetClass",
                function() return byClass[className].sample:GetClass() end)
            if safe.isValid(cls) and addCandidate(cls, nameOf(cls), "vivante [" .. fragment .. "]") then
                logger.always("INFO", "  candidat vivant [%s] %s", fragment, className)
            end
        end
    end

    if #state.candidates == 0 then
        logger.always("WARN", "Palier 2 : aucun candidat. Le palier 3 sera saute. "
            .. "Reessayer avec la carte du jeu ouverte : les packages d'UI ne sont "
            .. "charges qu'a la premiere ouverture de l'ecran concerne.")
        return false
    end

    logger.always("INFO", "Palier 2 OK (%d candidats)", #state.candidates)
    return true
end

-- ------------------------------------------------------------------ palier 3

--- LA question du spike : peut-on instancier un widget du jeu et l'afficher ?
-- Deux voies tentees dans l'ordre.
--   A. UWidgetBlueprintLibrary::Create -- la voie propre : elle execute la construction
--      du widget comme le jeu le ferait.
--   B. StaticConstructObject -- plus brutale, contourne la construction ; testee seulement
--      si A echoue, pour distinguer "on ne peut rien construire" de "Create est indisponible".
-- Tout passe par le game thread : manipuler l'UMG depuis le thread Lua crashe.
local function stage3_instantiate(ctx)
    logger.always("INFO", "--- Palier 3 : instanciation + AddToViewport ---")

    if #state.candidates == 0 then
        logger.always("WARN", "Palier 3 saute : aucun candidat issu du palier 2")
        return
    end

    -- Les candidats sont ordonnes par le palier 2 : les classes nommees de l'ObjectDump
    -- d'abord (du plus leger au plus lourd), les trouvailles dynamiques ensuite. Prendre
    -- le premier n'est donc plus un choix arbitraire -- mais on dit lequel, et pourquoi.
    local target = state.candidates[1]
    logger.always("INFO", "Cible retenue : %s (origine : %s, sur %d candidats)",
        target.name, tostring(target.origin), #state.candidates)

    safe.gameThread(logger, "stage3", function()
        local widget = nil

        -- Voie A
        local lib = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
        if safe.isValid(lib) then
            logger.always("INFO", "WidgetBlueprintLibrary trouve, essai de Create()")
            local okA, created = pcall(function()
                return lib:Create(ctx.world, target.class, ctx.controller)
            end)
            if okA and safe.isValid(created) then
                widget = created
                logger.always("INFO", "Voie A (Create) : widget construit -> %s", nameOf(widget))
            else
                logger.always("WARN", "Voie A (Create) echouee : %s", tostring(created))
            end
        else
            logger.always("WARN", "WidgetBlueprintLibrary introuvable -- voie A indisponible")
        end

        -- Voie B
        if not widget then
            logger.always("INFO", "Essai de la voie B (StaticConstructObject)")
            local okB, created = pcall(function()
                return StaticConstructObject(target.class, ctx.controller)
            end)
            if okB and safe.isValid(created) then
                widget = created
                logger.always("INFO", "Voie B : widget construit -> %s", nameOf(widget))
            else
                logger.always("ERROR", "Voie B echouee : %s", tostring(created))
            end
        end

        if not widget then
            logger.always("ERROR", "Palier 3 KO : aucune voie n'a produit de widget. "
                .. "=> l'affichage en Lua pur est a rediscuter (arbitrage .pak).")
            return
        end

        -- Affichage
        local okAdd, addErr = pcall(function() widget:AddToViewport(0) end)
        if not okAdd then
            logger.always("ERROR", "Palier 3 : widget construit mais AddToViewport a leve : %s",
                tostring(addErr))
            return
        end

        state.createdWidget = widget
        logger.always("INFO", "Palier 3 OK : AddToViewport a repondu sans erreur.")
        logger.always("INFO", ">>> REGARDE L'ECRAN. Vois-tu quelque chose de nouveau ? <<<")
    end)
end

-- ------------------------------------------------------------------ palier 4

--- Effets de bord : le widget a-t-il vole le focus ou mis le jeu en pause ?
-- Un widget qui s'affiche mais fige le jeu est inutilisable pour une minimap ; il vaut
-- mieux le savoir maintenant.
local function stage4_sideEffects(ctx)
    logger.always("INFO", "--- Palier 4 : effets de bord ---")

    if not state.createdWidget then
        logger.always("INFO", "Palier 4 saute : aucun widget affiche")
        return
    end

    local _, inViewport = safe.call(logger, "IsInViewport",
        function() return state.createdWidget:IsInViewport() end)
    logger.always("INFO", "IsInViewport      : %s", tostring(inViewport))

    local showMouse = safe.get(ctx.controller, "bShowMouseCursor")
    logger.always("INFO", "bShowMouseCursor  : %s", tostring(showMouse))

    -- Le pawn repond-il toujours ? Un pawn devenu invalide signale un changement d'etat
    -- de jeu declenche par le widget.
    local pawn = safe.get(ctx.controller, "Pawn")
    logger.always("INFO", "Pawn encore valide: %s", tostring(safe.isValid(pawn)))

    logger.always("INFO", "Palier 4 termine. Note dans ton retour : le jeu repond-il "
        .. "toujours (deplacement, camera) ?")
end

-- ------------------------------------------------------------------ orchestration

local function runProbe()
    logger.always("INFO", "======== SPIKE DE RENDU : debut ========")

    local ctx = stage1_context()
    if not ctx then
        logger.always("ERROR", "======== SPIKE interrompu au palier 1 ========")
        return
    end

    stage2_discover()
    stage3_instantiate(ctx)
    stage4_sideEffects(ctx)

    logger.always("INFO", "======== SPIKE DE RENDU : fin ========")
    logger.always("INFO", "Renvoie UE4SS.log + une capture d'ecran.")
end

--- Retire le widget ajoute, pour pouvoir relancer F5 sans redemarrer le jeu.
local function cleanup()
    if not state.createdWidget then
        logger.always("INFO", "Rien a retirer.")
        return
    end
    safe.gameThread(logger, "cleanup", function()
        pcall(function() state.createdWidget:RemoveFromViewport() end)
        state.createdWidget = nil
        logger.always("INFO", "Widget retire. F5 peut etre represse.")
    end)
end

-- ------------------------------------------------------------------ demarrage
--
-- Chaque etape s'enregistre independamment (brief SS3.7) : si le chargement de la config
-- echoue, les keybinds doivent quand meme repondre -- sinon le spike ne renvoie rien,
-- et c'est le retour qu'on perd.

safe.call(logger, "chargement config", function() cfg.load() end)
log.setDebug(cfg.get("debug", true) == true)

logger.banner({
    mod   = VERSION,
    ue4ss = type(UE4SS) == "table" and "detecte" or "inconnu",
    game  = "Palworld 1.0.x",
})

logger.always("INFO", "Spike de rendu -- F5 lance la sonde, F6 retire le widget ajoute.")

if type(Key) ~= "table" then
    logger.fatalOnce("La table globale Key est absente : build UE4SS inattendu. "
        .. "Aucun keybind ne peut etre enregistre.")
else
    safe.keybind(logger, "F5 (sonde)", Key.F5, nil, runProbe)
    safe.keybind(logger, "F6 (nettoyage)", Key.F6, nil, cleanup)
end
