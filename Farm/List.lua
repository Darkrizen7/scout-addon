-- Liste des monstres à farmer pour le personnage : niveau, zone, hostilité (QuestieDB) + valeur par kill.
local _, ns = ...
local List = {}
ns.List = List

List.RANGES = {   -- écart de niveau autour du tien : { en dessous, au-dessus }
    { lo = 3, hi = 2, label = "Niv. -3/+2" },
    { lo = 6, hi = 2, label = "Niv. -6/+2" },
    { lo = 10, hi = 2, label = "Niv. -10/+2" },
}

local zoneNames = {}
local function ZoneName(areaID)
    local name = zoneNames[areaID]
    if name == nil then
        name = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaID) or false
        zoneNames[areaID] = name
    end
    return name or ("zone " .. areaID)
end

-- Zone principale (celle qui a le plus d'apparitions) et nombre total d'apparitions.
local function MainZone(spawns)
    local best, bestCount, total = nil, 0, 0
    for zone, points in pairs(spawns or {}) do
        local n = #points
        total = total + n
        if n > bestCount then best, bestCount = zone, n end
    end
    return best, total
end

local function FriendlyToMe(friendly)
    if not friendly then return false end
    local mine = UnitFactionGroup("player") == "Horde" and "H" or "A"
    return friendly:find(mine, 1, true) ~= nil
end

-- opts : { range = index de RANGES, elites = bool }
function List.Build(opts)
    ns.Value.Reset()
    local level = UnitLevel("player")
    local range = List.RANGES[opts.range] or List.RANGES[1]
    local skinRank = ns.Value.SkinningRank()
    local rows = {}
    for id in pairs(ns.LootData.C) do
        local minL, maxL = NpcDB.Get(id, "minLevel"), NpcDB.Get(id, "maxLevel")
        if minL and maxL and maxL >= level - range.lo and minL <= level + range.hi then
            local rank = NpcDB.Get(id, "rank") or 0
            if (opts.elites or rank == 0) and not FriendlyToMe(NpcDB.Get(id, "friendlyToFaction")) then
                local zone, spawnCount = MainZone(NpcDB.Get(id, "spawns"))
                if zone and spawnCount > 0 then
                    local avgLevel = math.floor((minL + maxL) / 2)
                    local v = ns.Value.Creature(id, { skinRank = skinRank, level = avgLevel })
                    local observed, kills = ns.Observed.PerKill(id)
                    rows[#rows + 1] = {
                        id = id, name = NpcDB.Get(id, "name") or ("PNJ " .. id),
                        level = minL == maxL and tostring(minL) or (minL .. "-" .. maxL), avgLevel = avgLevel,
                        zone = ZoneName(zone), spawns = spawnCount, elite = rank > 0,
                        gold = v.gold, items = v.items + v.shared, skin = v.skin, skinnable = v.skinnable,
                        total = v.total, observed = observed, kills = kills or 0,
                    }
                end
            end
        end
    end
    return rows, skinRank
end

function List.Detail(row)
    return ns.Value.Creature(row.id, { skinRank = ns.Value.SkinningRank(), level = row.avgLevel, detail = true })
end
