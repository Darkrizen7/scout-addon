-- Valeur attendue par kill d'un monstre : or + objets (dont butin partagé) + dépeçage.
local _, ns = ...
local Value = {}
ns.Value = Value

local refCache = {}

function Value.Reset()
    wipe(refCache)
    ns.Prices.ResetCache()
end

-- Somme des espérances × valeurs d'une liste plate {objet, espérance, ...}.
local function ListValue(list, detail)
    local total = 0
    for i = 1, #list, 2 do
        local id, expected = list[i], list[i + 1]
        local v, source = ns.Prices.ItemValue(id)
        local part = expected * v
        total = total + part
        if detail and part > 0 then
            detail[#detail + 1] = { id = id, expected = expected, value = v, part = part, source = source }
        end
    end
    return total
end

local function RefValue(rid)
    local v = refCache[rid]
    if not v then
        v = ListValue(ns.LootData.R[rid] or {})
        refCache[rid] = v
    end
    return v
end

-- Compétence de dépeçage requise selon le niveau du monstre (règles Classic).
function Value.SkinReq(level)
    if level <= 10 then return 1 end
    if level <= 20 then return (level - 10) * 10 end
    return level * 5
end

-- opts : { skinRank = compétence de dépeçage (nil = pas dépeceur), level = niveau du monstre, detail = bool }
function Value.Creature(id, opts)
    local c = ns.LootData.C[id]
    if not c then return nil end
    local detail = opts.detail and { items = {}, skin = {} } or nil
    local r = { gold = c[1] }
    r.items = ListValue(c[2], detail and detail.items)
    r.shared = 0
    local refs = c[3]
    for i = 1, #refs, 2 do r.shared = r.shared + refs[i + 1] * RefValue(refs[i]) end
    r.skin = 0
    local canSkin = c[4] ~= 0 and opts.skinRank and opts.level and opts.skinRank >= Value.SkinReq(opts.level)
    if canSkin then r.skin = ListValue(ns.LootData.S[c[4]] or {}, detail and detail.skin) end
    r.skinnable = c[4] ~= 0
    r.total = r.gold + r.items + r.shared + r.skin
    if detail then
        table.sort(detail.items, function(a, b) return a.part > b.part end)
        table.sort(detail.skin, function(a, b) return a.part > b.part end)
        r.detail = detail
    end
    return r
end

-- Compétence de dépeçage du personnage (nil s'il ne dépèce pas).
function Value.SkinningRank()
    if not (GetProfessions and GetProfessionInfo) then return nil end
    for _, idx in ipairs({ GetProfessions() }) do
        if type(idx) == "number" then
            local _, _, rank, _, _, _, skillLine = GetProfessionInfo(idx)
            if skillLine == 393 then return rank end
        end
    end
end
