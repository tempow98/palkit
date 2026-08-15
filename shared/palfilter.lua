--[[
    PalKit -- shared/palfilter.lua
    Moteur de requete sur une liste de Pals : filtrer, trier, detecter les doublons domines.

    ------------------------------------------------------------------------------------
    POURQUOI C'EST UN MODULE PUR
    ------------------------------------------------------------------------------------
    Rien ici ne touche au jeu. L'entree est une liste de tables telles que PalKitBox les
    produit (docs/testing.md decrit le format), la sortie est une autre liste. C'est
    volontaire, et c'est ce qui change tout pour ce projet : Lucas est le runtime, chaque
    aller-retour de test coute une session de jeu. Un moteur pur se valide **sur l'export
    reel** -- 743 Pals deja exportes -- sans lancer Palworld une seule fois.

    Corollaire : ce module servira tel quel a M3 (meme moteur sur le Paldeck).

    ------------------------------------------------------------------------------------
    CE QUE « DOMINE » VEUT DIRE, ET POURQUOI
    ------------------------------------------------------------------------------------
    Un Pal en domine un autre s'il est **au moins aussi bon partout, et meilleur quelque
    part** -- c'est-a-dire s'il n'y a aucune raison de garder l'autre. Trois choix de
    conception, discutables mais explicites :

      * **Meme espece obligatoire.** Comparer un Lamball a un Anubis n'a pas de sens.
      * **Meme genre par defaut.** Un male ne « domine » pas une femelle : en reproduction
        les deux servent, et conseiller de relacher la seule femelle d'une espece serait un
        mauvais conseil. `ignoreGender = true` pour l'ignorer quand on ne fait pas d'elevage.
      * **On compare l'inne, pas l'acquis.** IVs et passifs sont fixes a la naissance ; le
        niveau, la condensation et les ames se rattrapent avec du temps et des ressources.
        Un Pal niveau 1 aux IVs parfaits n'est pas domine par un niveau 50 mediocre.

    L'egalite parfaite est un cas a part : deux Pals identiques se domineraient mutuellement
    et on les relacherait tous les deux. Le premier rencontre est donc garde, le second est
    signale avec `equal = true` -- a l'appelant de decider.
]]

local palfilter = {}

-- ------------------------------------------------------------------ helpers

local IV_FIELDS = { "hp", "melee", "shot", "defense" }

--- Somme des IVs, 0 pour les champs absents. Sert de critere de tri courant.
function palfilter.ivTotal(pal)
    local total = 0
    local ivs = pal and pal.ivs
    if type(ivs) ~= "table" then return 0 end
    for _, field in ipairs(IV_FIELDS) do
        local value = ivs[field]
        if type(value) == "number" then total = total + value end
    end
    return total
end

--- Ensemble des passifs d'un Pal, pour des comparaisons en O(1).
local function passiveSet(pal)
    local set = {}
    if type(pal.passives) == "table" then
        for _, name in ipairs(pal.passives) do set[name] = true end
    end
    return set
end

--- Comparaison de chaines insensible a la casse et aux accents absents des noms internes.
local function contains(haystack, needle)
    if type(haystack) ~= "string" or type(needle) ~= "string" then return false end
    return string.find(string.lower(haystack), string.lower(needle), 1, true) ~= nil
end

-- ------------------------------------------------------------------ filtrage

--- Un Pal satisfait-il tous les criteres ?
--
-- Criteres reconnus (tous optionnels, combines en ET) :
--   species        sous-chaine du nom d'espece, insensible a la casse
--   speciesExact   nom exact
--   levelMin / levelMax
--   ivTotalMin     somme des 4 IVs
--   ivMin          table { hp =, melee =, shot =, defense = } -- seuil par statistique
--   gender         0 (aucun), 1 (male), 2 (femelle) -- EPalGenderType
--   rankMin        rang de condensation minimal
--   rare / awakening / locked   booleens exacts
--   passives       liste : le Pal doit les avoir TOUS
--   passivesAny    liste : le Pal doit en avoir AU MOINS UN
--   page           numero de page
-- @return boolean
function palfilter.match(pal, criteria)
    if type(pal) ~= "table" then return false end
    if type(criteria) ~= "table" then return true end

    if criteria.species and not contains(pal.species, criteria.species) then return false end
    if criteria.speciesExact and pal.species ~= criteria.speciesExact then return false end

    if criteria.levelMin and (pal.level or 0) < criteria.levelMin then return false end
    if criteria.levelMax and (pal.level or 0) > criteria.levelMax then return false end
    if criteria.rankMin  and (pal.rank  or 0) < criteria.rankMin  then return false end
    if criteria.page     and pal.page ~= criteria.page then return false end
    if criteria.gender   and pal.gender ~= criteria.gender then return false end

    -- Booleens : on compare a l'identique, `false` est un critere valable ("les non-rares").
    if criteria.rare      ~= nil and (pal.rare      == true) ~= criteria.rare      then return false end
    if criteria.awakening ~= nil and (pal.awakening == true) ~= criteria.awakening then return false end
    if criteria.locked    ~= nil and (pal.locked    == true) ~= criteria.locked    then return false end

    if criteria.ivTotalMin and palfilter.ivTotal(pal) < criteria.ivTotalMin then return false end

    if type(criteria.ivMin) == "table" then
        local ivs = pal.ivs or {}
        for _, field in ipairs(IV_FIELDS) do
            local threshold = criteria.ivMin[field]
            if threshold and (ivs[field] or 0) < threshold then return false end
        end
    end

    if type(criteria.passives) == "table" and #criteria.passives > 0 then
        local set = passiveSet(pal)
        for _, name in ipairs(criteria.passives) do
            if not set[name] then return false end
        end
    end

    if type(criteria.passivesAny) == "table" and #criteria.passivesAny > 0 then
        local set, found = passiveSet(pal), false
        for _, name in ipairs(criteria.passivesAny) do
            if set[name] then found = true break end
        end
        if not found then return false end
    end

    return true
end

--- Filtre une liste de Pals. L'ordre d'origine est conserve.
-- @return table
function palfilter.filter(pals, criteria)
    local out = {}
    for _, pal in ipairs(pals or {}) do
        if palfilter.match(pal, criteria) then out[#out + 1] = pal end
    end
    return out
end

-- ------------------------------------------------------------------ tri

--- Valeur triable d'un champ. `ivTotal` est calcule, le reste est lu tel quel.
local function sortValue(pal, field)
    if field == "ivTotal" then return palfilter.ivTotal(pal) end
    local value = pal[field]
    if value == nil and pal.ivs then value = pal.ivs[field] end
    if value == nil and pal.souls then value = pal.souls[field] end
    return value
end

--- Trie une COPIE de la liste, selon plusieurs cles successives.
-- @param spec table  ex. { { field = "ivTotal", desc = true }, { field = "level" } }
-- @return table  nouvelle liste
function palfilter.sort(pals, spec)
    local out = {}
    for i, pal in ipairs(pals or {}) do out[i] = pal end
    if type(spec) ~= "table" or #spec == 0 then return out end

    table.sort(out, function(a, b)
        for _, key in ipairs(spec) do
            local va, vb = sortValue(a, key.field), sortValue(b, key.field)

            -- Les valeurs absentes finissent toujours en dernier, quel que soit le sens :
            -- un Pal dont le niveau n'a pas ete lu ne doit pas prendre la tete d'un
            -- classement decroissant.
            if va == nil and vb == nil then
                -- egalite, on passe a la cle suivante
            elseif va == nil then return false
            elseif vb == nil then return true
            elseif type(va) ~= type(vb) then
                return tostring(va) < tostring(vb)
            elseif va ~= vb then
                if key.desc then return va > vb end
                return va < vb
            end
        end

        -- Départage stable : sans lui, table.sort peut permuter deux egaux d'un appel a
        -- l'autre et le rapport change sans que rien n'ait bouge.
        local pa = (a.page or 0) * 1000 + (a.slot or 0)
        local pb = (b.page or 0) * 1000 + (b.slot or 0)
        return pa < pb
    end)

    return out
end

--- Les `n` premiers, apres tri.
function palfilter.top(pals, spec, n)
    local sorted = palfilter.sort(pals, spec)
    if n == nil or #sorted <= n then return sorted end
    local out = {}
    for i = 1, n do out[i] = sorted[i] end
    return out
end

-- ------------------------------------------------------------------ dominance

--- `a` domine-t-il `b` ? Voir l'entete pour les regles.
-- @return boolean domine, boolean egaux
function palfilter.dominates(a, b, options)
    options = options or {}
    if a == b then return false, false end
    if a.species == nil or a.species ~= b.species then return false, false end
    if not options.ignoreGender and a.gender ~= b.gender then return false, false end

    local strictlyBetter = false

    -- IVs : jamais inferieur sur aucune statistique.
    local ia, ib = a.ivs or {}, b.ivs or {}
    for _, field in ipairs(IV_FIELDS) do
        local va, vb = ia[field] or 0, ib[field] or 0
        if va < vb then return false, false end
        if va > vb then strictlyBetter = true end
    end

    -- Passifs : ceux de `b` doivent tous se retrouver chez `a`.
    local setA, setB = passiveSet(a), passiveSet(b)
    local countA, countB = 0, 0
    for _ in pairs(setA) do countA = countA + 1 end
    for name in pairs(setB) do
        countB = countB + 1
        if not setA[name] then return false, false end
    end
    if countA > countB then strictlyBetter = true end

    return true, not strictlyBetter
end

--- Liste les Pals domines par un autre.
--
-- Complexite : les Pals sont d'abord groupes par espece (et par genre sauf option), donc
-- on ne compare que ce qui est comparable. Sur 743 Pals et 310 especes, les groupes sont
-- minuscules -- sans ce groupement, ce serait 743 x 743 comparaisons a chaque appel.
-- @return table  liste de { pal = <domine>, by = <dominant>, equal = boolean }
function palfilter.findDominated(pals, options)
    options = options or {}
    local groups = {}

    for _, pal in ipairs(pals or {}) do
        if pal.species ~= nil then
            local key = pal.species
            if not options.ignoreGender then key = key .. "/" .. tostring(pal.gender) end
            groups[key] = groups[key] or {}
            local group = groups[key]
            group[#group + 1] = pal
        end
    end

    local out = {}
    for _, group in pairs(groups) do
        for i = 1, #group do
            for j = 1, #group do
                if i ~= j then
                    local dominates, equal = palfilter.dominates(group[j], group[i], options)
                    -- En cas d'egalite parfaite, seul le second est signale : sinon les deux
                    -- se dominent et on relacherait la paire entiere.
                    if dominates and (not equal or j < i) then
                        out[#out + 1] = { pal = group[i], by = group[j], equal = equal }
                        break
                    end
                end
            end
        end
    end

    return out
end

return palfilter
