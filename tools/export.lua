-- Exporte l'historique HdV de ScoutDB en CSV (une ligne par objet et par scan).
-- Usage : lua tools/export.lua <SavedVariables/Scout.lua> [sortie.csv]   (défaut : stdout)
--         lua tools/export.lua <SavedVariables/Scout.lua> --names [sortie.csv]
--         lua tools/export.lua <SavedVariables/Scout.lua> --loot [sortie.csv]
--
-- Avec --names : tous les noms connus (objets vus aux scans),
--   colonnes item_id,name,class_id,subclass_id,class,subclass (catégorie et libellés du client).
-- Avec --loot : le butin enregistré en jeu (ScoutDB.farm.obs),
--   colonnes npc_id,name,zone,kills,skins,kind,item_id,drops,quantity
--   kind : loot (fouille, sur `kills` corps) ou skin (dépeçage / minage / herboristerie, sur `skins` corps) ;
--   drops : corps où l'objet est tombé ; quantity : exemplaires au total ;
--   une ligne sans kind ni item_id pour un monstre sans objet (garde ses kills).
-- Les numéros d'objet sont ceux du jeu, les mêmes que dans Auctionator et Forever Guide.
--
-- Colonnes : item_id,name,timestamp,datetime,price,quantity,realm,faction
--   timestamp : heure du scan, secondes Unix (UTC)
--   datetime  : la même en heure locale, AAAA-MM-JJ HH:MM:SS
--   price    : prix unitaire minimum en cuivre (vide si l'objet n'était pas en vente à ce scan)
--   quantity : nombre d'exemplaires en vente (0 = absent de l'HdV)
--   realm, faction : HdV scanné (market.houses[e.a]) ; faction = Alliance | Horde | Neutral ;
--     vides pour les anciens relevés sans `a`
local src = assert(arg[1], "usage : lua tools/export.lua <SavedVariables/Scout.lua> [--names | --loot] [sortie.csv]")
local mode = (arg[2] == "--names" or arg[2] == "--loot") and arg[2] or nil
local namesOnly = mode == "--names"
local dest
if mode then dest = arg[3] else dest = arg[2] end

local env = {}
assert(loadfile(src, "t", env))()

local function field(v)
    if v == nil then return "" end
    v = tostring(v)
    if v:find('[,"\n]') then v = '"' .. v:gsub('"', '""') .. '"' end
    return v
end

if mode == "--loot" then
    local obs = env.ScoutDB and env.ScoutDB.farm and env.ScoutDB.farm.obs or {}
    local out = dest and assert(io.open(dest, "w")) or io.stdout
    out:write("npc_id,name,zone,kills,skins,kind,item_id,drops,quantity\n")
    local npcs, rows = {}, 0
    for npc in pairs(obs) do npcs[#npcs + 1] = npc end
    table.sort(npcs)
    for _, npc in ipairs(npcs) do
        local e = obs[npc]
        local head = table.concat({ npc, field(e.name), field(e.zone), e.kills or 0, e.skins or 0 }, ",")
        local any = false
        for _, part in ipairs({ { "loot", e.items }, { "skin", e.skin } }) do
            local ids = {}
            for id in pairs(part[2] or {}) do ids[#ids + 1] = id end
            table.sort(ids)
            for _, id in ipairs(ids) do
                local v = part[2][id]
                if type(v) == "number" then v = { n = v, q = v } end   -- ancien format : quantité seule
                out:write(table.concat({ head, part[1], id, v.n, v.q }, ","), "\n")
                rows, any = rows + 1, true
            end
        end
        if not any then
            out:write(head, ",,,,\n")
            rows = rows + 1
        end
    end
    if out ~= io.stdout then out:close() end
    io.stderr:write(("%d lignes, %d monstres\n"):format(rows, #npcs))
    return
end

local market = assert(env.ScoutDB and env.ScoutDB.market, "pas de ScoutDB.market dans " .. src)
local hist, names, houses = market.hist or {}, market.names or {}, market.houses or {}
local classes, classNames, subclassNames = market.class or {}, market.classNames or {}, market.subclassNames or {}

local ids = {}
for id in pairs(namesOnly and names or hist) do ids[#ids + 1] = id end
table.sort(ids)

local out = dest and assert(io.open(dest, "w")) or io.stdout
if namesOnly then
    out:write("item_id,name,class_id,subclass_id,class,subclass\n")
    for _, id in ipairs(ids) do
        local key = classes[id]
        local classID, subClassID = key and key // 100, key and key % 100
        out:write(table.concat({ id, field(names[id]), field(classID), field(subClassID),
            field(classNames[classID or -1]), field(subclassNames[key or -1]) }, ","), "\n")
    end
    if out ~= io.stdout then out:close() end
    io.stderr:write(("%d noms\n"):format(#ids))
    return
end
out:write("item_id,name,timestamp,datetime,price,quantity,realm,faction\n")
local rows = 0
for _, id in ipairs(ids) do
    for _, e in ipairs(hist[id]) do
        local t = e.t
        if not t and e.d then   -- ancien format, un relevé par jour : midi
            local y, mo, d = e.d:match("(%d+)-(%d+)-(%d+)")
            t = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 12 })
        end
        local house = e.a and houses[e.a] or {}
        out:write(table.concat({ id, field(names[id]), t, os.date("%Y-%m-%d %H:%M:%S", t), field(e.p), e.q or 0,
            field(house.realm), field(house.faction) }, ","), "\n")
        rows = rows + 1
    end
end
if out ~= io.stdout then out:close() end
io.stderr:write(("%d lignes, %d objets\n"):format(rows, #ids))
