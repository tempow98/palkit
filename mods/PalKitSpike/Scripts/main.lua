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
        -- Fragments recherches dans les noms de classes de widgets. Volontairement larges :
        -- on ne connait pas encore la convention de nommage de Palworld, c'est justement
        -- ce que le palier 2 doit reveler.
        namePatterns   = { "map", "minimap", "hud", "compass", "marker", "panel", "widget" },
        maxCandidates  = 40,   -- borne de log : un dump complet noierait UE4SS.log
        maxOnScreen    = 60,
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

--- Quelles classes de widgets sont chargees, et lesquelles ressemblent a une carte ?
-- FindAllOf("WidgetBlueprintGeneratedClass") renvoie les UClass elles-memes (les classes
-- generees SONT des instances de WidgetBlueprintGeneratedClass), pas des widgets vivants.
local function stage2_discover()
    logger.always("INFO", "--- Palier 2 : classes de widgets chargees ---")

    local patterns = cfg.get("probe.namePatterns", DEFAULTS.probe.namePatterns)
    local maxLog   = cfg.get("probe.maxCandidates", DEFAULTS.probe.maxCandidates)

    local _, classes = safe.call(logger, "FindAllOf(WidgetBlueprintGeneratedClass)",
        function() return FindAllOf("WidgetBlueprintGeneratedClass") end)

    if type(classes) ~= "table" then
        logger.always("WARN", "Aucune WidgetBlueprintGeneratedClass retournee. "
            .. "Les widgets ne sont peut-etre charges qu'a l'ouverture d'un menu : "
            .. "reessayer carte du jeu ouverte.")
        classes = {}
    end

    local total, matched = 0, 0
    state.candidates = {}

    for _, class in ipairs(classes) do
        total = total + 1
        local name = nameOf(class)
        local hit, fragment = matchesAny(name, patterns)
        if hit then
            matched = matched + 1
            if matched <= maxLog then
                logger.always("INFO", "  candidat [%s] %s", fragment, name)
            end
            state.candidates[#state.candidates + 1] = { class = class, name = name }
        end
    end

    logger.always("INFO", "%d classes de widgets chargees, %d candidates retenues%s",
        total, matched,
        matched > maxLog and string.format(" (%d premieres listees)", maxLog) or "")

    -- Widgets VIVANTS a l'ecran. Reconnaissance directement reutilisable pour M2 :
    -- c'est ici qu'on verra apparaitre les widgets de la Palbox quand elle est ouverte.
    local _, live = safe.call(logger, "FindAllOf(UserWidget)",
        function() return FindAllOf("UserWidget") end)

    if type(live) == "table" then
        local maxOnScreen = cfg.get("probe.maxOnScreen", DEFAULTS.probe.maxOnScreen)
        logger.always("INFO", "--- %d UserWidget vivants (%d premiers) ---",
            #live, math.min(#live, maxOnScreen))
        for i = 1, math.min(#live, maxOnScreen) do
            logger.always("INFO", "  vivant : %s", nameOf(live[i]))
        end
    else
        logger.always("WARN", "FindAllOf(UserWidget) n'a rien retourne")
    end

    if #state.candidates == 0 then
        logger.always("WARN", "Palier 2 : aucun candidat. Le palier 3 sera saute.")
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

    local target = state.candidates[1]
    logger.always("INFO", "Cible retenue : %s", target.name)

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
