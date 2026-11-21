-- Ton propre butin : chaque corps fouillé ou dépecé est enregistré par type de monstre,
-- pour comparer l'estimation (base Classic) à ce que donne vraiment Forever.
--   ScoutDB.farm.obs[npcID] = { kills = n, money = cuivre, items = { [itemID] = quantité } }
local _, ns = ...
local Observed = {}
ns.Observed = Observed

local MAX_GUIDS = 300
local moneyStart, lootGuids

local function NpcID(guid)
    local kind, _, _, _, _, id = strsplit("-", guid or "")
    if kind == "Creature" then return tonumber(id) end
end

local function Store()
    return ns.db.farm.obs, ns.db.farm.seen   -- seen : GUIDs déjà comptés (fouille puis dépeçage = 1 kill)
end

local function Entry(obs, npc)
    local e = obs[npc]
    if not e then
        e = { kills = 0, money = 0, items = {} }
        obs[npc] = e
    end
    return e
end

local function CountKill(seen, obs, guid, npc)
    if seen.set == nil then seen.set, seen.order = {}, {} end
    if seen.set[guid] then return end
    seen.set[guid] = true
    table.insert(seen.order, guid)
    if #seen.order > MAX_GUIDS then seen.set[table.remove(seen.order, 1)] = nil end
    Entry(obs, npc).kills = Entry(obs, npc).kills + 1
end

ns.On("LOOT_OPENED", function()
    local obs, seen = Store()
    moneyStart, lootGuids = GetMoney(), {}
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        local itemID = link and tonumber(link:match("item:(%d+)"))
        local sources = { GetLootSourceInfo(slot) }
        for i = 1, #sources, 2 do
            local guid, qty = sources[i], sources[i + 1] or 1
            local npc = NpcID(guid)
            if npc then
                lootGuids[guid] = npc
                CountKill(seen, obs, guid, npc)
                if itemID then
                    local items = Entry(obs, npc).items
                    items[itemID] = (items[itemID] or 0) + qty
                end
            end
        end
    end
end)

-- L'or ramassé est réparti entre les corps de la fenêtre de butin.
ns.On("LOOT_CLOSED", function()
    if not moneyStart then return end
    local gained = GetMoney() - moneyStart
    moneyStart = nil
    local n = 0
    for _ in pairs(lootGuids) do n = n + 1 end
    if gained <= 0 or n == 0 then return end
    local obs = Store()
    for _, npc in pairs(lootGuids) do
        local e = Entry(obs, npc)
        e.money = e.money + gained / n
    end
end)

-- Valeur moyenne réellement observée par kill, aux prix actuels.
function Observed.PerKill(npc)
    local e = ns.db.farm.obs[npc]
    if not e or e.kills == 0 then return nil end
    local total = e.money
    for id, qty in pairs(e.items) do total = total + qty * (ns.Prices.ItemValue(id)) end
    return total / e.kills, e.kills
end
