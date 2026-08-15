--[[
    PalKit -- shared/log.lua
    Logging structure pour mods UE4SS Lua.

    Le log est le SEUL canal de retour du projet : Lucas lance le jeu, teste, et renvoie
    UE4SS.log. Tout ce qui n'est pas logge est invisible. D'ou le soin porte ici des le
    premier commit (brief SS9).

    Sortie : `print()`, la globale UE4SS, qui ecrit dans la console UE4SS et UE4SS.log.

    Anti-flood : une erreur qui se repete (typiquement dans un LoopAsync a 200 ms) noierait
    le fichier en quelques secondes. Chaque message porte donc une cle de dedoublonnage ;
    une meme cle n'est reemise qu'une fois par fenetre, avec le compte des occurrences
    supprimees entre-temps.
]]

local log = {}

local LEVELS = {
    FATAL = 10,
    ERROR = 20,
    WARN  = 30,
    INFO  = 40,
    DEBUG = 50,
}

log.LEVELS = LEVELS

-- Fenetre de dedoublonnage, en secondes (brief SS9 : "resumee une fois par minute").
local DEDUP_WINDOW = 60

-- Seuil global. DEBUG est coupe par defaut ; config.lua le rehausse au chargement
-- des settings si l'utilisateur a mis debug = true.
local threshold = LEVELS.INFO

--- Rehausse ou abaisse le seuil global de verbosite.
-- @param levelName string  nom de niveau ("DEBUG", "INFO", ...)
function log.setLevel(levelName)
    local lvl = LEVELS[tostring(levelName):upper()]
    if lvl then
        threshold = lvl
    end
end

--- Raccourci : active ou coupe DEBUG.
function log.setDebug(enabled)
    threshold = enabled and LEVELS.DEBUG or LEVELS.INFO
end

function log.getLevel()
    for name, value in pairs(LEVELS) do
        if value == threshold then return name end
    end
    return "INFO"
end

-- Etat de dedoublonnage, partage par tous les loggers du process.
-- [cle] = { firstSeen = os.time(), suppressed = n }
local dedup = {}

-- os.time() peut manquer dans un sandbox Lua restreint ; on degrade proprement plutot
-- que de faire tomber le logging, qui est justement ce qui nous permettrait de le voir.
local function now()
    if os and os.time then
        local ok, t = pcall(os.time)
        if ok and type(t) == "number" then return t end
    end
    return 0
end

--- Decide si un message doit sortir, et avec quel suffixe de resume.
-- @return boolean emit, string suffix
local function throttle(key)
    if not key then return true, "" end

    local t = now()
    local entry = dedup[key]

    if not entry then
        dedup[key] = { firstSeen = t, suppressed = 0 }
        return true, ""
    end

    if (t - entry.firstSeen) >= DEDUP_WINDOW then
        local suppressed = entry.suppressed
        dedup[key] = { firstSeen = t, suppressed = 0 }
        if suppressed > 0 then
            return true, string.format(" (+%d occurrences supprimees sur les %ds precedentes)",
                                       suppressed, DEDUP_WINDOW)
        end
        return true, ""
    end

    entry.suppressed = entry.suppressed + 1
    return false, ""
end

--- Cree un logger nomme.
-- @param moduleName string  ex. "Spike", "Minimap" -> prefixe [PalKit][Spike]
-- @return table
function log.new(moduleName)
    local prefix = string.format("[PalKit][%s]", tostring(moduleName or "?"))
    local self = {}

    -- Emission brute. `key` est optionnel : sans cle, pas de dedoublonnage.
    local function emit(levelName, key, message)
        if LEVELS[levelName] > threshold then return end

        local emitMsg, suffix = throttle(key)
        if not emitMsg then return end

        -- print() UE4SS ne formate pas et n'ajoute pas de retour ligne.
        print(string.format("%s[%s] %s%s\n", prefix, levelName, tostring(message), suffix))
    end

    -- Chaque niveau accepte soit (format, ...) soit rien de special : la cle de
    -- dedoublonnage vaut par defaut la chaine de format, ce qui est exactement le bon
    -- comportement (meme message repete = meme cle), sans que l'appelant y pense.
    local function makeLevel(levelName)
        return function(fmt, ...)
            local ok, message = pcall(string.format, tostring(fmt), ...)
            if not ok then
                -- Un mauvais format ne doit pas tuer l'appelant : on sort le brut.
                message = tostring(fmt)
            end
            emit(levelName, tostring(fmt), message)
        end
    end

    self.fatal = makeLevel("FATAL")
    self.error = makeLevel("ERROR")
    self.warn  = makeLevel("WARN")
    self.info  = makeLevel("INFO")
    self.debug = makeLevel("DEBUG")

    --- Variante sans dedoublonnage, pour les messages dont on veut CHAQUE occurrence
    -- (resultats de spike, lignes de version, bornes de scan).
    function self.always(levelName, fmt, ...)
        local ok, message = pcall(string.format, tostring(fmt), ...)
        if not ok then message = tostring(fmt) end
        emit(tostring(levelName):upper(), nil, message)
    end

    --- Banniere de demarrage (brief SS9 : "une ligne de version au demarrage").
    -- @param info table { mod = "0.1.0", ue4ss = "...", game = "..." }
    function self.banner(info)
        info = info or {}
        self.always("INFO", "=== PalKit %s | mod %s | UE4SS %s | jeu %s ===",
            tostring(moduleName or "?"),
            tostring(info.mod or "?"),
            tostring(info.ue4ss or "inconnu"),
            tostring(info.game or "inconnu"))
    end

    --- Echec bloquant : une seule ligne FATAL claire, puis l'appelant doit se desactiver
    -- proprement. Jamais de boucle d'echec (brief SS9).
    function self.fatalOnce(fmt, ...)
        local ok, message = pcall(string.format, tostring(fmt), ...)
        if not ok then message = tostring(fmt) end
        local key = "FATAL::" .. tostring(fmt)
        if not dedup[key] then
            dedup[key] = { firstSeen = now(), suppressed = 0 }
            print(string.format("%s[FATAL] %s\n", prefix, message))
            print(string.format("%s[FATAL] Module desactive.\n", prefix))
        end
    end

    return self
end

return log
