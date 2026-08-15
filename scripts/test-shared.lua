-- Tests de la lib commune PalKit, executables hors jeu (Lua 5.1 local).
package.path = "shared/?.lua;" .. package.path

local json   = require("json")
local config = require("config")

local pass, fail = 0, 0
local function check(name, cond, detail)
    if cond then
        pass = pass + 1
    else
        fail = fail + 1
        print(("FAIL  %s  %s"):format(name, tostring(detail or "")))
    end
end

-- ---------------------------------------------------------------- json aller-retour
local function roundtrip(name, value)
    local encoded = json.encode(value)
    local decoded, err = json.decode(encoded)
    check(name .. " (decode)", decoded ~= nil, err)
    return decoded, encoded
end

local d = roundtrip("scalaires", { a = 1, b = "x", c = true, d = false })
check("nombre", d and d.a == 1)
check("chaine", d and d.b == "x")
check("bool vrai", d and d.c == true)
check("bool faux", d and d.d == false)

local nested = { minimap = { size = 200, shape = "circle", markers = { pals = true } } }
d = roundtrip("imbrique", nested)
check("profondeur 3", d and d.minimap.markers.pals == true)
check("nombre imbrique", d and d.minimap.size == 200)

d = roundtrip("tableau", { list = { 1, 2, 3 }, empty = {} })
check("tableau taille", d and #d.list == 3)
check("tableau ordre", d and d.list[1] == 1 and d.list[3] == 3)
check("table vide -> objet", d and type(d.empty) == "table")

-- echappements
local tricky = { s = 'guillemet " antislash \\ tab \t nl \n' }
d = roundtrip("echappements", tricky)
check("echappements exacts", d and d.s == tricky.s, d and d.s)

-- unicode
local u, uerr = json.decode('{"s":"caf\\u00e9"}')
check("unicode \\u", u and u.s == "caf\195\169", u and u.s or uerr)

local emoji = json.decode('{"s":"\\ud83d\\ude00"}')
check("paire de substitution", emoji and #emoji.s == 4, emoji and #emoji.s)

-- precision numerique
d = json.decode(json.encode({ n = 0.1 + 0.2 }))
check("pas de traine flottante", tostring(d.n):sub(1, 3) == "0.3", d.n)

-- negatifs / exposants
d = json.decode('{"a":-42,"b":1.5e3,"c":-0.25}')
check("negatif", d and d.a == -42)
check("exposant", d and d.b == 1500)
check("decimal negatif", d and d.c == -0.25)

-- null = cle absente
d = json.decode('{"a":1,"b":null}')
check("null ignore", d and d.a == 1 and d.b == nil)

-- cles triees (diff lisible)
local sorted = json.encode({ zebra = 1, alpha = 2 }, false)
check("cles triees", sorted:find("alpha") < sorted:find("zebra"), sorted)

-- erreurs : ne doivent pas lever, mais renvoyer nil + message
local bad, badErr = json.decode("{oops}")
check("json invalide -> nil", bad == nil and type(badErr) == "string", badErr)
check("json vide -> nil", (json.decode("")) == nil)
check("non-chaine -> nil", (json.decode(nil)) == nil)
check("residu rejete", (json.decode('{"a":1} zzz')) == nil)

-- circulaire
local circ = {}; circ.self = circ
check("circulaire attrapee", not pcall(json.encode, circ))

-- ---------------------------------------------------------------- deepMerge
local defaults = {
    enabled = true,
    minimap = { size = 200, shape = "circle", opacity = 0.8 },
}

local merged = config.deepMerge(defaults, { minimap = { size = 350 } }, nil, nil)
check("override applique", merged.minimap.size == 350)
check("frere preserve", merged.minimap.shape == "circle")
check("defaut racine preserve", merged.enabled == true)

-- mauvais type -> defaut retenu
merged = config.deepMerge(defaults, { minimap = { size = "grand" } }, nil, nil)
check("mauvais type rejete", merged.minimap.size == 200, merged.minimap.size)

-- cle inconnue conservee
merged = config.deepMerge(defaults, { futureKey = 7 }, nil, nil)
check("cle inconnue conservee", merged.futureKey == 7)

-- override non-table sur un objet
merged = config.deepMerge(defaults, { minimap = 5 }, nil, nil)
check("objet ecrase par scalaire -> defaut", merged.minimap.size == 200)

-- l'original n'est pas mute
config.deepMerge(defaults, { minimap = { size = 999 } }, nil, nil)
check("defauts non mutes", defaults.minimap.size == 200, defaults.minimap.size)

-- ---------------------------------------------------------------- query
-- query.lua parle au moteur, mais ses gardes sont testables hors jeu : c'est justement
-- leur role d'absorber des objets qui n'ont pas la forme attendue.
local query = require("query")

-- Faux UObject : une table dont les methodes prennent self, comme cote UE4SS.
local fakeObj = {
    value = 42,
    GetThing = function(self) return self.value end,
    Add      = function(self, a, b) return a + b end,
    Boom     = function(self) error("la reflexion moteur a leve") end,
}

check("call methode simple", query.call(fakeObj, "GetThing") == 42)
check("call avec arguments", query.call(fakeObj, "Add", 2, 3) == 5)
check("call methode absente -> nil", query.call(fakeObj, "PasLa") == nil)
check("call methode qui leve -> nil", query.call(fakeObj, "Boom") == nil)
check("call sur nil -> nil", query.call(nil, "GetThing") == nil)

check("get propriete", query.get(fakeObj, "value") == 42)
check("get propriete absente -> nil", query.get(fakeObj, "absente") == nil)
check("get sur nil -> nil", query.get(nil, "value") == nil)

check("str chaine", query.str("deja une chaine") == "deja une chaine")
check("str via ToString", query.str({ ToString = function() return "FName" end }) == "FName")
check("str sur nil", query.str(nil) == nil)

check("nameOf sur nil", query.nameOf(nil) == "<nil>")
check("nameOf sur objet muet", query.nameOf({}) == "<sans nom>")

-- Un cache vide ne doit jamais rendre un objet mort : reset est idempotent.
check("reset ne leve pas", pcall(query.reset))
check("reset idempotent", pcall(query.reset))

-- ---------------------------------------------------------------- palio
local palio = require("palio")

-- On force le dossier de sortie : sans le jeu, resolveModDir retomberait sur "." et
-- ecrirait dans le depot.
local tmpDir = os.getenv("TMPDIR") or "/tmp"
local realResolve = config.resolveModDir
config.resolveModDir = function() return tmpDir, "test" end

local writer = palio.new({ modName = "PalKitTest", prefix = "test" })
check("modDir force", writer.modDir == tmpDir, writer.modDir)

local payload = {
    meta = { palCount = 2 },
    pals = { { species = "Lamball", level = 3 }, { species = "Cattiva", level = 5 } },
    warnings = {},
}
local path, err = writer.writeJson("export", payload)
check("writeJson renvoie un chemin", type(path) == "string", err)
check("nom horodate", path and path:find("test%-export%-%d+%-%d+%.json") ~= nil, path)

if path then
    local f = io.open(path, "r")
    check("fichier cree", f ~= nil)
    if f then
        local content = f:read("*a")
        f:close()
        local back = json.decode(content)
        check("relecture JSON", back ~= nil)
        check("contenu preserve", back and back.pals[2].species == "Cattiva")
        check("meta preserve", back and back.meta.palCount == 2)
        os.remove(path)
    end
end

-- Une valeur non serialisable ne doit pas lever : elle est signalee, pas propagee.
local cyclic = {}; cyclic.self = cyclic
local badPath, badErr = writer.writeJson("cycle", cyclic)
check("cycle -> pas de fichier", badPath == nil and type(badErr) == "string", badErr)

config.resolveModDir = realResolve

print(("\n%d OK, %d KO"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
