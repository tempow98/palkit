--[[
    PalKit -- shared/palio.lua
    Ecriture des exports sur le disque.

    Comme query.lua, ce fichier etait differe en Phase 0 : on ne savait pas encore ce qu'on
    aurait a exporter. Maintenant qu'on lit la Palbox, il faut pouvoir la deposer quelque
    part de retrouvable.

    Trois choix a justifier :

    1. ON N'ECRIT QUE DANS LE DOSSIER DU MOD. Il est resolu par config.resolveModDir() --
       la meme mecanique que pour la config, donc le meme comportement sur les deux layouts
       d'installation possibles. Ecrire ailleurs (Documents, %APPDATA%, racine du jeu)
       supposerait un chemin que le mod ne controle pas.

    2. AUCUN SOUS-DOSSIER N'EST CREE. Lua n'a pas de mkdir ; le seul moyen serait
       os.execute(), qui ouvre une console par-dessus le jeu sous Windows. Les exports
       vivent donc a plat dans le dossier du mod, prefixes, et la desinstallation reste
       "supprimer le dossier".

    3. LE NOM PORTE L'HORODATAGE. Un export n'ecrase jamais le precedent : comparer deux
       etats de la Palbox a deux moments est exactement l'usage vise.
]]

local json = require("json")
local config = require("config")

local palio = {}

--- Horodatage triable, sans caractere interdit dans un nom de fichier Windows.
local function timestamp()
    local ok, stamp = pcall(os.date, "%Y%m%d-%H%M%S")
    if ok and type(stamp) == "string" then return stamp end
    return tostring(os.time())
end

--- Assemble un chemin, en respectant le separateur deja present dans `dir`.
local function join(dir, name)
    if string.find(dir, "\\", 1, true) then
        return dir .. "\\" .. name
    end
    return dir .. "/" .. name
end

--- Cree un ecrivain d'exports pour un mod.
-- @param opts table { modName = "PalKitBox", logger = <log.new()>, prefix = "palbox" }
-- @return table
function palio.new(opts)
    opts = opts or {}
    local logger  = opts.logger
    local modName = opts.modName or "PalKit"
    local prefix  = opts.prefix or modName

    local modDir, strategy = config.resolveModDir(modName)
    if logger then
        logger.debug("exports dans %s (resolu par %s)", tostring(modDir), tostring(strategy))
    end

    local writer = {}
    writer.modDir = modDir

    --- Ecrit un fichier texte. Renvoie (chemin|nil, erreur|nil).
    -- Pas d'ecriture atomique ici, contrairement a config.lua : chaque export porte un nom
    -- unique, il n'y a donc pas de fichier existant a proteger.
    function writer.writeText(basename, content)
        local path = join(modDir, basename)

        local f, err = io.open(path, "w")
        if not f then
            if logger then logger.error("export %s : ouverture impossible : %s", path, tostring(err)) end
            return nil, tostring(err)
        end

        local ok, writeErr = pcall(function()
            f:write(content)
            f:close()
        end)
        if not ok then
            pcall(function() f:close() end)
            if logger then logger.error("export %s : ecriture interrompue : %s", path, tostring(writeErr)) end
            return nil, tostring(writeErr)
        end

        return path, nil
    end

    --- Serialise `value` en JSON et l'ecrit sous <prefix>-<label>-<horodatage>.json.
    -- @return string|nil path, string|nil err
    function writer.writeJson(label, value)
        local ok, encoded = pcall(json.encode, value, true)
        if not ok then
            -- Cas attendu : une valeur non serialisable a traverse la collecte (userdata
            -- moteur, cycle). C'est un defaut du collecteur, pas de l'IO -- on le nomme.
            if logger then logger.error("export %s : serialisation impossible : %s", tostring(label), tostring(encoded)) end
            return nil, tostring(encoded)
        end

        local name = string.format("%s-%s-%s.json", prefix, tostring(label), timestamp())
        local path, err = writer.writeText(name, encoded)
        if path and logger then
            logger.always("INFO", "export ecrit : %s", path)
        end
        return path, err
    end

    return writer
end

return palio
