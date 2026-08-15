--[[
    PalKit -- shared/json.lua
    Encodeur / decodeur JSON minimal.

    UE4SS ne fournit pas de bibliotheque JSON au Lua, et la config doit etre persistee en
    JSON (brief SS3.6). Ce fichier est une implementation PalKit, pas une bibliotheque tierce
    reprise : le perimetre est volontairement reduit a ce que settings.json exige --
    objets, tableaux, chaines, nombres, booleens, null. Pas de NaN, pas d'infini, pas de
    cle non-chaine.

    Ce choix evite d'embarquer -- et donc d'avoir a suivre et attribuer -- une dependance
    externe pour trois types de valeurs. Aucun code tiers n'est inclus dans PalKit.

    Compatibilite : Lua 5.1 comme 5.4 (UE4SS tourne en 5.4 ; le controle syntaxique local
    se fait en 5.1). Aucune syntaxe 5.4-only.
]]

local json = {}

-- ---------------------------------------------------------------- encodage

local ESCAPE_MAP = {
    ['"']    = '\\"',
    ['\\']   = '\\\\',
    ['\b']   = '\\b',
    ['\f']   = '\\f',
    ['\n']   = '\\n',
    ['\r']   = '\\r',
    ['\t']   = '\\t',
}

local function escapeChar(c)
    local mapped = ESCAPE_MAP[c]
    if mapped then return mapped end
    -- Caracteres de controle restants -> \u00XX
    return string.format('\\u%04x', string.byte(c))
end

local function encodeString(s)
    return '"' .. string.gsub(s, '[%z\1-\31\\"]', escapeChar) .. '"'
end

local function encodeNumber(n)
    if n ~= n then error("json: NaN non encodable") end
    if n == math.huge or n == -math.huge then error("json: infini non encodable") end
    -- %.14g conserve la precision utile sans traine de flottant ("0.30000000000000004").
    return string.format("%.14g", n)
end

--- Un tableau est une table dont les cles sont exactement 1..n.
-- Distinction indispensable : une table vide est ambigue en Lua, on la serialise en objet
-- (`{}`), ce qui est le bon defaut pour une config.
local function isArray(t)
    local count = 0
    for k in pairs(t) do
        if type(k) ~= "number" then return false, 0 end
        if k < 1 or k % 1 ~= 0 then return false, 0 end
        count = count + 1
    end
    for i = 1, count do
        if t[i] == nil then return false, 0 end
    end
    return count > 0, count
end

local encodeValue

local function encodeTable(t, indent, level, seen)
    if seen[t] then error("json: reference circulaire") end
    seen[t] = true

    local pretty = indent ~= nil
    local nl      = pretty and "\n" or ""
    local pad     = pretty and string.rep(indent, level + 1) or ""
    local padEnd  = pretty and string.rep(indent, level) or ""
    local sep     = pretty and ": " or ":"

    local parts = {}
    local array, count = isArray(t)

    if array then
        for i = 1, count do
            parts[#parts + 1] = pad .. encodeValue(t[i], indent, level + 1, seen)
        end
        seen[t] = nil
        if #parts == 0 then return "[]" end
        return "[" .. nl .. table.concat(parts, "," .. nl) .. nl .. padEnd .. "]"
    end

    -- Cles triees : un settings.json dont l'ordre change a chaque ecriture est illisible
    -- en diff, et Lucas va lire ce fichier.
    local keys = {}
    for k in pairs(t) do
        if type(k) ~= "string" then
            error("json: cle non-chaine (" .. type(k) .. ")")
        end
        keys[#keys + 1] = k
    end
    table.sort(keys)

    for _, k in ipairs(keys) do
        parts[#parts + 1] = pad .. encodeString(k) .. sep
                            .. encodeValue(t[k], indent, level + 1, seen)
    end

    seen[t] = nil
    if #parts == 0 then return "{}" end
    return "{" .. nl .. table.concat(parts, "," .. nl) .. nl .. padEnd .. "}"
end

encodeValue = function(v, indent, level, seen)
    local vt = type(v)
    if v == nil then return "null" end
    if vt == "boolean" then return tostring(v) end
    if vt == "number" then return encodeNumber(v) end
    if vt == "string" then return encodeString(v) end
    if vt == "table" then return encodeTable(v, indent, level, seen) end
    error("json: type non encodable (" .. vt .. ")")
end

--- Serialise une valeur Lua en JSON.
-- @param value any
-- @param pretty boolean  indente sur 2 espaces (defaut : true -- le fichier est lu a l'oeil)
-- @return string
function json.encode(value, pretty)
    if pretty == nil then pretty = true end
    return encodeValue(value, pretty and "  " or nil, 0, {})
end

-- ---------------------------------------------------------------- decodage

local Parser = {}
Parser.__index = Parser

local WHITESPACE = { [" "] = true, ["\t"] = true, ["\n"] = true, ["\r"] = true }

local function newParser(str)
    return setmetatable({ s = str, i = 1, n = #str }, Parser)
end

function Parser:fail(msg)
    error(string.format("json: %s (position %d)", msg, self.i), 0)
end

function Parser:skipWhitespace()
    while self.i <= self.n and WHITESPACE[string.sub(self.s, self.i, self.i)] do
        self.i = self.i + 1
    end
end

function Parser:peek()
    if self.i > self.n then return nil end
    return string.sub(self.s, self.i, self.i)
end

function Parser:expect(c)
    if self:peek() ~= c then
        self:fail("'" .. c .. "' attendu")
    end
    self.i = self.i + 1
end

--- Encode un point de code en UTF-8 (pour les sequences \uXXXX).
local function utf8Encode(cp)
    if cp < 0x80 then
        return string.char(cp)
    elseif cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40),
                           0x80 + (cp % 0x40))
    elseif cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000),
                           0x80 + (math.floor(cp / 0x40) % 0x40),
                           0x80 + (cp % 0x40))
    end
    return string.char(0xF0 + math.floor(cp / 0x40000),
                       0x80 + (math.floor(cp / 0x1000) % 0x40),
                       0x80 + (math.floor(cp / 0x40) % 0x40),
                       0x80 + (cp % 0x40))
end

local UNESCAPE_MAP = {
    ['"'] = '"', ['\\'] = '\\', ['/'] = '/',
    b = '\b', f = '\f', n = '\n', r = '\r', t = '\t',
}

function Parser:parseString()
    self:expect('"')
    local parts = {}

    while true do
        local c = self:peek()
        if c == nil then self:fail("chaine non terminee") end

        if c == '"' then
            self.i = self.i + 1
            return table.concat(parts)
        end

        if c == '\\' then
            self.i = self.i + 1
            local esc = self:peek()
            if esc == nil then self:fail("echappement non termine") end
            self.i = self.i + 1

            if esc == 'u' then
                local hex = string.sub(self.s, self.i, self.i + 3)
                if not string.match(hex, "^%x%x%x%x$") then
                    self:fail("sequence \\u invalide")
                end
                self.i = self.i + 4
                local cp = tonumber(hex, 16)

                -- Paire de substitution UTF-16 : \uD800-\uDBFF suivi de \uDC00-\uDFFF.
                if cp >= 0xD800 and cp <= 0xDBFF then
                    if string.sub(self.s, self.i, self.i + 1) == "\\u" then
                        local lowHex = string.sub(self.s, self.i + 2, self.i + 5)
                        local low = tonumber(lowHex, 16)
                        if low and low >= 0xDC00 and low <= 0xDFFF then
                            self.i = self.i + 6
                            cp = 0x10000 + (cp - 0xD800) * 0x400 + (low - 0xDC00)
                        end
                    end
                end
                parts[#parts + 1] = utf8Encode(cp)
            else
                local mapped = UNESCAPE_MAP[esc]
                if not mapped then self:fail("echappement inconnu \\" .. esc) end
                parts[#parts + 1] = mapped
            end
        else
            parts[#parts + 1] = c
            self.i = self.i + 1
        end
    end
end

function Parser:parseNumber()
    local start = self.i
    local pattern = "^-?%d+%.?%d*[eE]?[-+]?%d*"
    local matched = string.match(self.s, pattern, self.i)
    if not matched or matched == "" then self:fail("nombre invalide") end
    self.i = start + #matched
    local value = tonumber(matched)
    if value == nil then self:fail("nombre illisible : " .. matched) end
    return value
end

function Parser:parseLiteral()
    for literal, value in pairs({ ["true"] = true, ["false"] = false, ["null"] = json.null }) do
        if string.sub(self.s, self.i, self.i + #literal - 1) == literal then
            self.i = self.i + #literal
            return value
        end
    end
    self:fail("valeur inattendue")
end

function Parser:parseArray()
    self:expect('[')
    local result = {}
    self:skipWhitespace()

    if self:peek() == ']' then
        self.i = self.i + 1
        return result
    end

    while true do
        result[#result + 1] = self:parseValue()
        self:skipWhitespace()
        local c = self:peek()
        if c == ']' then
            self.i = self.i + 1
            return result
        end
        if c ~= ',' then self:fail("',' ou ']' attendu") end
        self.i = self.i + 1
        self:skipWhitespace()
    end
end

function Parser:parseObject()
    self:expect('{')
    local result = {}
    self:skipWhitespace()

    if self:peek() == '}' then
        self.i = self.i + 1
        return result
    end

    while true do
        self:skipWhitespace()
        if self:peek() ~= '"' then self:fail("cle attendue") end
        local key = self:parseString()

        self:skipWhitespace()
        self:expect(':')

        local value = self:parseValue()
        -- null en entree = cle absente : on ne stocke pas de sentinelle dans la config,
        -- le defaut du code doit reprendre la main.
        if value ~= json.null then
            result[key] = value
        end

        self:skipWhitespace()
        local c = self:peek()
        if c == '}' then
            self.i = self.i + 1
            return result
        end
        if c ~= ',' then self:fail("',' ou '}' attendu") end
        self.i = self.i + 1
    end
end

function Parser:parseValue()
    self:skipWhitespace()
    local c = self:peek()
    if c == nil then self:fail("fin de donnees inattendue") end

    if c == '{' then return self:parseObject() end
    if c == '[' then return self:parseArray() end
    if c == '"' then return self:parseString() end
    if c == '-' or string.match(c, "%d") then return self:parseNumber() end
    return self:parseLiteral()
end

-- Sentinelle distinguant "null explicite" de "absent". Table unique, comparable par identite.
json.null = setmetatable({}, { __tostring = function() return "null" end })

--- Parse une chaine JSON.
-- Ne leve pas : renvoie (nil, message) en cas d'echec, parce que tout appelant est
-- cense traiter une config corrompue sans tomber.
-- @return table|nil value, string|nil err
function json.decode(str)
    if type(str) ~= "string" then
        return nil, "json: chaine attendue, recu " .. type(str)
    end

    local parser = newParser(str)
    local ok, result = pcall(function()
        local value = parser:parseValue()
        parser:skipWhitespace()
        if parser.i <= parser.n then
            parser:fail("donnees residuelles apres la valeur")
        end
        return value
    end)

    if not ok then return nil, tostring(result) end
    return result, nil
end

return json
