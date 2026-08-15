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

-- callWhy doit DIRE pourquoi il echoue. C'est ce qui manquait au premier essai en jeu du
-- 2026-08-15 : "GetPalStorage n'a rien renvoye" ne distinguait pas trois causes qui
-- appellent trois corrections differentes.
local said = {}
local function record(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    said[#said + 1] = ok and msg or fmt
end
local fakeLogger = {
    debug  = record,
    always = function(_, fmt, ...) record(fmt, ...) end,
}
local function lastSaid() return said[#said] or "" end

check("callWhy rend la valeur", query.callWhy(fakeLogger, fakeObj, "GetThing") == 42)
check("callWhy silencieux quand ca marche", #said == 0)

query.callWhy(fakeLogger, fakeObj, "PasLa")
check("callWhy signale un membre absent",
      lastSaid():find("absent", 1, true) ~= nil, lastSaid())

query.callWhy(fakeLogger, fakeObj, "Boom")
check("callWhy signale une levee", lastSaid():find("a leve", 1, true) ~= nil, lastSaid())

query.callWhy(fakeLogger, nil, "GetThing")
check("callWhy signale l'objet nil", lastSaid():find("nil", 1, true) ~= nil, lastSaid())

fakeObj.NotCallable = 42
query.callWhy(fakeLogger, fakeObj, "NotCallable")
check("callWhy signale un membre present mais non appelable",
      lastSaid():find("non appelable", 1, true) ~= nil, lastSaid())

-- LE test de non-regression du 2e run. UE4SS expose ses UFunction comme des **userdata
-- appelables**, pas comme des fonctions Lua : exiger type(fn) == "function" rejetait
-- silencieusement toutes les methodes du jeu. Impossible de fabriquer un userdata en Lua
-- pur, mais une table a metatable __call reproduit exactement le cas : appelable, et d'un
-- type autre que "function".
local callable = setmetatable({}, { __call = function(_, self, n) return (n or 0) + self.value end })
local fakeUE4SS = setmetatable({ value = 42 }, { __index = { GetThing = callable } })
check("callWhy appelle un membre appelable qui n'est pas une function",
      query.callWhy(fakeLogger, fakeUE4SS, "GetThing", 8) == 50,
      tostring(query.callWhy(fakeLogger, fakeUE4SS, "GetThing", 8)))

-- storageAnswers : ni un UObject valide, ni des dimensions ne suffisent -- il faut qu'un
-- SLOT sorte. Au 2e run, un storage annoncant 32 pages x 30 avait ete retenu alors que
-- GetSlot(0,0) ne rendait rien : l'export a sorti 0 Pal en se declarant satisfait.
local function fakeStorage(fields)
    fields.IsValid = function() return true end
    return fields
end
local function fakeSlot()
    return { IsValid = function() return true end }
end

check("storage complet (pages + slots) est retenu",
      query.storageAnswers(fakeLogger, fakeStorage({
          GetPageNum = function() return 32 end,
          GetSlot    = function(_, _, _) return fakeSlot() end,
      })))
check("storage avec la seule propriete PageNum mais des slots est retenu",
      query.storageAnswers(fakeLogger, fakeStorage({
          PageNum = 12,
          GetSlot = function(_, _, _) return fakeSlot() end,
      })))
check("storage aux dimensions lisibles mais aux slots muets est ECARTE",
      not query.storageAnswers(fakeLogger, fakeStorage({ PageNum = 32, SlotNumInPage = 30 })))
check("storage a zero page est ecarte",
      not query.storageAnswers(fakeLogger, fakeStorage({ PageNum = 0 })))
check("storage muet est ecarte",
      not query.storageAnswers(fakeLogger, fakeStorage({})))
check("storage nil est ecarte", not query.storageAnswers(fakeLogger, nil))

check("les voies d'acces Palbox sont exposees et nommees",
      type(query.palStorageRoutes) == "table" and #query.palStorageRoutes >= 4
      and type(query.palStorageRoutes[1].name) == "string"
      and type(query.palStorageRoutes[1].resolve) == "function")

-- ---------------------------------------------------------------- encodage de valeurs moteur
-- Le codec JSON refuse -- a raison -- tout ce qui n'est pas un scalaire. Au run 3, un seul
-- champ userdata a fait perdre un export de 723 Pals deja correctement lus. Ces tests
-- verifient la regle qui en decoule : ce que le moteur rend d'exotique se convertit, ou
-- se signale, mais ne coute jamais le fichier entier.
local function encodable(value)
    return pcall(json.encode, { v = value })
end

check("json refuse une valeur exotique", not encodable(coroutine.create(function() end)))

-- Une table vide est ambiguë en Lua : `json.array` lève l'ambiguïté, sinon un champ
-- « liste » change de type selon qu'il est vide ou non.
check("table vide -> objet par defaut", json.encode({ w = {} }, false) == '{"w":{}}',
      json.encode({ w = {} }, false))
check("table vide marquee -> liste", json.encode({ w = json.array({}) }, false) == '{"w":[]}',
      json.encode({ w = json.array({}) }, false))
check("json.array rend la table", (function() local t = {} return json.array(t) == t end)())
check("marquer ne casse pas une liste pleine",
      json.encode({ w = json.array({ 1, 2 }) }, false) == '{"w":[1,2]}')
check("json accepte les scalaires", encodable(42) and encodable("x") and encodable(true))

-- Les trois formes qu'UE4SS rend pour un champ non scalaire, telles que PalKitBox les
-- convertit : FName/FString (ToString), RemoteUnrealParam (get), enum (GetValue).
local asFName  = { ToString = function() return "BOSS_IceHorse_Dark" end }
local asParam  = { get      = function() return 65 end }
local asEnum   = { GetValue = function() return 2 end }
local opaque   = { Autre    = function() return {} end }

-- On teste le VRAI query.scalar, pas une copie de sa logique : c'est la raison pour
-- laquelle il vit dans shared/ et non dans le mod.
local scalarOf = query.scalar

check("scalar convertit un FName", scalarOf(asFName) == "BOSS_IceHorse_Dark")
check("scalar convertit un RemoteUnrealParam", scalarOf(asParam) == 65)
check("scalar convertit un enum", scalarOf(asEnum) == 2)
check("scalar laisse passer les scalaires", scalarOf(65) == 65 and scalarOf("x") == "x")
check("scalar abandonne l'irreductible plutot que de le deguiser", scalarOf(opaque) == nil)
check("scalar nomme la methode utilisee", select(2, scalarOf(asEnum)) == "GetValue")
check("un scalaire converti est encodable", encodable(scalarOf(asFName)))

-- toList : quatre API tentées, l'erreur de la première conservée.
local viaForEach = {
    ForEach = function(self, fn)
        for i, v in ipairs({ "Legend", "Swift" }) do fn(i, { get = function() return v end }) end
    end,
}
local list, via = query.toList(viaForEach)
check("toList lit un TArray via ForEach", list and #list == 2 and list[1] == "Legend", via)
check("toList nomme la voie utilisee", via == "ForEach", via)

local viaIndex = {
    GetArrayNum     = function() return 2 end,
    GetArrayElement = function(_, i) return "skill" .. i end,
}
local list2, via2 = query.toList(viaIndex)
check("toList retombe sur GetArrayElement quand ForEach leve",
      list2 and #list2 == 2 and list2[1] == "skill0", tostring(via2))

-- Un TArray dont l'UObject est mort : toutes les voies lèvent, y compris `#` (côté jeu
-- c'est un userdata sans __len). C'est le cas rencontré au run 4 sur les pages non
-- répliquées de la Palbox.
local mort = setmetatable({}, {
    __index = function() error("Tried calling a member function but the UObject instance is nullptr") end,
    __len   = function() error("UObject instance is nullptr") end,
})
local list3, _, detail = query.toList(mort)
check("toList rend nil et l'erreur exacte quand tout echoue",
      list3 == nil and detail and detail:find("nullptr", 1, true) ~= nil, tostring(detail))
check("toList sur nil est signale", select(3, query.toList(nil)) == "champ absent")

-- Une liste vide est légitime, mais elle ne doit pas l'emporter sur une voie qui rend des
-- données : sinon un Pal avec passifs sortirait sans passifs.
local videPuisPleine = {
    ForEach         = function() end, -- ne leve pas, ne remplit rien
    GetArrayNum     = function() return 1 end,
    GetArrayElement = function() return "Legend" end,
}
local list4, via4 = query.toList(videPuisPleine)
check("toList prefere une voie qui rend des donnees a une voie vide",
      list4 and #list4 == 1 and list4[1] == "Legend", tostring(via4))

local toujoursVide = { ForEach = function() end }
local list5, via5 = query.toList(toujoursVide)
check("toList accepte une liste vide a defaut de mieux, en le disant",
      list5 and #list5 == 0 and via5 and via5:find("vide", 1, true) ~= nil, tostring(via5))

-- keepObjects : une liste de slots n'est pas une liste de noms.
local slot = { IsValid = function() return true end }
local objets = query.toList({
    ForEach = function(_, fn) fn(1, { get = function() return slot end }) end,
}, true)
check("toList garde les UObject quand on le demande", objets and objets[1] == slot)

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
