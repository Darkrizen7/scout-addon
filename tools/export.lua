-- Exporte l'historique HdV de ScoutDB en CSV (une ligne par objet et par scan).
-- Usage : lua tools/export.lua <SavedVariables/Scout.lua> [sortie.csv]   (défaut : stdout)
--         lua tools/export.lua <SavedVariables/Scout.lua> --names [sortie.csv]
--
-- Avec --names : tous les noms connus (objets vus aux scans), colonnes item_id,name.
-- Les numéros d'objet sont ceux du jeu, les mêmes que dans Auctionator et Forever Guide.
--
-- Colonnes : item_id,name,timestamp,datetime,price,quantity
--   timestamp : heure du scan, secondes Unix (UTC)
--   datetime  : la même en heure locale, AAAA-MM-JJ HH:MM:SS
--   price    : prix unitaire minimum en cuivre (vide si l'objet n'était pas en vente à ce scan)
--   quantity : nombre d'exemplaires en vente (0 = absent de l'HdV)
local src = assert(arg[1], "usage : lua tools/export.lua <SavedVariables/Scout.lua> [--names] [sortie.csv]")
local namesOnly = arg[2] == "--names"
local dest = namesOnly and arg[3] or (not namesOnly and arg[2]) or nil

local env = {}
assert(loadfile(src, "t", env))()
local market = assert(env.ScoutDB and env.ScoutDB.market, "pas de ScoutDB.market dans " .. src)
local hist, names = market.hist or {}, market.names or {}

local function field(v)
    if v == nil then return "" end
    v = tostring(v)
    if v:find('[,"\n]') then v = '"' .. v:gsub('"', '""') .. '"' end
    return v
end

local ids = {}
for id in pairs(namesOnly and names or hist) do ids[#ids + 1] = id end
table.sort(ids)

local out = dest and assert(io.open(dest, "w")) or io.stdout
if namesOnly then
    out:write("item_id,name\n")
    for _, id in ipairs(ids) do out:write(id, ",", field(names[id]), "\n") end
    if out ~= io.stdout then out:close() end
    io.stderr:write(("%d noms\n"):format(#ids))
    return
end
out:write("item_id,name,timestamp,datetime,price,quantity\n")
local rows = 0
for _, id in ipairs(ids) do
    for _, e in ipairs(hist[id]) do
        local t = e.t
        if not t and e.d then   -- ancien format, un relevé par jour : midi
            local y, mo, d = e.d:match("(%d+)-(%d+)-(%d+)")
            t = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 12 })
        end
        out:write(table.concat({ id, field(names[id]), t, os.date("%Y-%m-%d %H:%M:%S", t), field(e.p), e.q or 0 }, ","), "\n")
        rows = rows + 1
    end
end
if out ~= io.stdout then out:close() end
io.stderr:write(("%d lignes, %d objets\n"):format(rows, #ids))
