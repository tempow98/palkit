--[[
    PalKit -- shared/config.lua
    Config persistee en JSON a cote du mod (brief SS3.6).

    Deux exigences structurent ce fichier.

    1. AUCUN CHEMIN EN DUR (brief SS2). Le layout d'installation a bouge entre l'Early Access
       et la 1.0, et les deux coexistent selon les machines :
         Palworld\Mods\NativeMods\UE4SS\Mods\<Mod>\Scripts\
         Palworld\Pal\Binaries\Win64\ue4ss\Mods\<Mod>\Scripts\
       On resout donc le dossier a l'execution, par strategies successives, et on logge
       celle qui a abouti -- c'est precisement l'information qu'on veut voir remonter du
       premier lancement chez Lucas.

    2. FUSION EN PROFONDEUR avec les defauts. Une cle ajoutee par une version ulterieure de
       PalKit doit apparaitre avec sa valeur par defaut sans ecraser ce que l'utilisateur a
       deja regle. La config survit donc aux mises a jour du mod, pas seulement a celles du
       jeu.
]]

local json = require("json")

local config = {}

-- ---------------------------------------------------------------- resolution du chemin

--- Strategie 1 : deduire le dossier du mod de `package.path`.
-- UE4SS ajoute le dossier Scripts/ du mod courant a package.path au chargement. C'est la
-- source la plus fiable parce qu'elle designe LE mod en train de tourner, sans supposer
-- quoi que ce soit du layout d'installation.
local function fromPackagePath()
    if type(package) ~= "table" or type(package.path) ~= "string" then
        return nil
    end
    -- Entrees de la forme  <...>\Mods\<Mod>\Scripts\?.lua
    for entry in string.gmatch(package.path, "[^;]+") do
        local dir = string.match(entry, "^(.*[/\\][Ss]cripts)[/\\]%?%.lua$")
        if dir then
            -- On remonte d'un cran : la config vit a cote du mod, pas dans Scripts/.
            local modDir = string.match(dir, "^(.*)[/\\][Ss]cripts$")
            if modDir then return modDir end
        end
    end
    return nil
end

--- Strategie 2 : parcourir les dossiers du jeu et retrouver le mod par son nom.
-- Plus couteux et plus fragile que la strategie 1, mais independant de package.path.
local function fromGameDirectories(modName)
    if type(IterateGameDirectories) ~= "function" then return nil end

    local ok, root = pcall(IterateGameDirectories)
    if not ok or type(root) ~= "table" then return nil end

    local found = nil
    local MAX_DEPTH = 12 -- garde-fou : l'arbre est profond, on ne le parcourt pas sans borne

    local function walk(node, depth)
        if found or depth > MAX_DEPTH or type(node) ~= "table" then return end
        for key, child in pairs(node) do
            if found then return end
            -- Les cles techniques (__name, __absolute_path, __files) ne sont pas des dossiers.
            if type(key) == "string" and string.sub(key, 1, 2) ~= "__" then
                if key == modName and type(child) == "table" then
                    local path = rawget(child, "__absolute_path")
                    if type(path) == "string" then
                        found = path
                        return
                    end
                end
                if type(child) == "table" then
                    walk(child, depth + 1)
                end
            end
        end
    end

    pcall(walk, root, 0)
    return found
end

--- Resout le dossier du mod. Renvoie (chemin|nil, strategie).
function config.resolveModDir(modName)
    local dir = fromPackagePath()
    if dir then return dir, "package.path" end

    dir = fromGameDirectories(modName)
    if dir then return dir, "IterateGameDirectories" end

    -- Strategie 3 : chemin relatif au repertoire de travail. Fonctionne rarement (le cwd
    -- est celui du jeu, pas du mod) mais vaut mieux que pas de config du tout.
    return ".", "relatif (degrade)"
end

-- ---------------------------------------------------------------- fusion

--- Fusionne `override` dans une copie de `defaults`, recursivement.
-- Une valeur d'override n'est retenue que si son type correspond au defaut : une config
-- editee a la main et cassee (chaine la ou un nombre est attendu) ne doit pas propager
-- son type errone jusqu'au code appelant.
local function deepMerge(defaults, override, logger, path)
    local result = {}

    for k, defaultValue in pairs(defaults) do
        local overrideValue = override and override[k]
        local keyPath = path and (path .. "." .. k) or k

        if type(defaultValue) == "table" then
            if type(overrideValue) == "table" then
                result[k] = deepMerge(defaultValue, overrideValue, logger, keyPath)
            else
                if overrideValue ~= nil and logger then
                    logger.warn("config: '%s' devrait etre un objet, %s trouve -- defaut retenu",
                                keyPath, type(overrideValue))
                end
                result[k] = deepMerge(defaultValue, nil, logger, keyPath)
            end
        elseif overrideValue == nil then
            result[k] = defaultValue
        elseif type(overrideValue) ~= type(defaultValue) then
            if logger then
                logger.warn("config: '%s' devrait etre %s, %s trouve -- defaut retenu",
                            keyPath, type(defaultValue), type(overrideValue))
            end
            result[k] = defaultValue
        else
            result[k] = overrideValue
        end
    end

    -- Cles presentes dans le fichier mais absentes des defauts : conservees telles quelles.
    -- Elles appartiennent soit a une version plus recente, soit a l'utilisateur ; les
    -- supprimer silencieusement serait une perte de donnees.
    if override then
        for k, v in pairs(override) do
            if result[k] == nil then result[k] = v end
        end
    end

    return result
end

config.deepMerge = deepMerge

-- ---------------------------------------------------------------- IO

local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

--- Ecriture aussi atomique que possible.
-- On ecrit dans un temporaire, on bascule l'ancien fichier en .bak, puis on renomme.
-- os.rename ne remplace pas un fichier existant sous Windows, d'ou la bascule en deux
-- temps plutot qu'un simple rename.
local function writeFileAtomic(path, content)
    local tmp = path .. ".tmp"
    local bak = path .. ".bak"

    local f, err = io.open(tmp, "w")
    if not f then return false, tostring(err) end

    local ok, writeErr = pcall(function()
        f:write(content)
        f:close()
    end)
    if not ok then
        pcall(function() f:close() end)
        os.remove(tmp)
        return false, tostring(writeErr)
    end

    if readFile(path) then
        os.remove(bak)
        os.rename(path, bak)
    end

    local renamed, renameErr = os.rename(tmp, path)
    if not renamed then
        -- Dernier recours : on restaure la sauvegarde pour ne pas laisser l'utilisateur
        -- sans config du tout.
        os.rename(bak, path)
        os.remove(tmp)
        return false, tostring(renameErr)
    end

    return true
end

-- ---------------------------------------------------------------- API

--- Cree un gestionnaire de config pour un mod.
-- @param opts table { modName = "PalKitSpike", defaults = {...}, logger = <log.new()> }
-- @return table
function config.new(opts)
    opts = opts or {}
    local logger   = opts.logger
    local modName  = opts.modName or "PalKit"
    local defaults = opts.defaults or {}

    local self = {}
    self.values = deepMerge(defaults, nil, nil, nil)
    self.path = nil
    self.loaded = false

    --- Charge settings.json. Ne leve jamais : en cas d'echec, `values` reste sur les defauts.
    -- @return boolean  vrai si un fichier a effectivement ete lu
    function self.load()
        local dir, strategy = config.resolveModDir(modName)
        self.path = dir .. "/settings.json"

        if logger then
            logger.info("config: dossier resolu via %s -> %s", strategy, dir)
        end

        local content = readFile(self.path)
        if not content then
            self.values = deepMerge(defaults, nil, logger, nil)
            self.loaded = true

            -- Ecrire le fichier plutot que de se contenter des defauts en memoire : sans
            -- lui, il n'y a rien a editer et rien qui documente les reglages disponibles.
            -- L'utilisateur ne doit pas avoir a deviner la structure d'un fichier qui
            -- n'existe pas -- constate le 2026-08-15, Lucas cherchait un settings.json que
            -- le mod n'avait jamais cree.
            if self.save() then
                if logger then
                    logger.always("INFO", "config: settings.json cree avec les valeurs par "
                        .. "defaut -> %s", self.path)
                    logger.always("INFO", "config: l'editer puis presser INS pour recharger.")
                end
            elseif logger then
                logger.info("config: aucun settings.json et creation impossible, "
                    .. "defauts appliques en memoire (%s)", self.path)
            end
            return false
        end

        local parsed, err = json.decode(content)
        if not parsed then
            -- Config corrompue : on ne l'ecrase pas, on la laisse en place pour que Lucas
            -- puisse la nous renvoyer, et on tourne sur les defauts.
            if logger then
                logger.error("config: settings.json illisible (%s) -- defauts appliques, "
                             .. "fichier conserve pour analyse", tostring(err))
            end
            self.values = deepMerge(defaults, nil, logger, nil)
            self.loaded = true
            return false
        end

        self.values = deepMerge(defaults, parsed, logger, nil)
        self.loaded = true
        if logger then logger.info("config: chargee depuis %s", self.path) end
        return true
    end

    --- Ecrit la config courante.
    -- @return boolean
    function self.save()
        if not self.path then
            local dir = config.resolveModDir(modName)
            self.path = dir .. "/settings.json"
        end

        local ok, encoded = pcall(json.encode, self.values, true)
        if not ok then
            if logger then logger.error("config: encodage impossible : %s", tostring(encoded)) end
            return false
        end

        local written, err = writeFileAtomic(self.path, encoded)
        if not written then
            if logger then logger.error("config: ecriture impossible : %s", tostring(err)) end
            return false
        end

        if logger then logger.debug("config: enregistree dans %s", self.path) end
        return true
    end

    --- Lit une valeur par chemin pointe : self.get("minimap.size", 200)
    function self.get(keyPath, fallback)
        local node = self.values
        for segment in string.gmatch(tostring(keyPath), "[^%.]+") do
            if type(node) ~= "table" then return fallback end
            node = node[segment]
            if node == nil then return fallback end
        end
        return node
    end

    --- Ecrit une valeur par chemin pointe. N'enregistre pas : appeler save() ensuite.
    function self.set(keyPath, value)
        local segments = {}
        for segment in string.gmatch(tostring(keyPath), "[^%.]+") do
            segments[#segments + 1] = segment
        end
        if #segments == 0 then return false end

        local node = self.values
        for i = 1, #segments - 1 do
            local segment = segments[i]
            if type(node[segment]) ~= "table" then node[segment] = {} end
            node = node[segment]
        end
        node[segments[#segments]] = value
        return true
    end

    return self
end

return config
