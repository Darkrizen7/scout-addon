-- Ton propre butin : chaque corps fouillé ou dépecé est enregistré par type de monstre,
-- pour comparer l'estimation (base Classic / Forever Guide) à ce que donne vraiment Forever.
--   ScoutDB.farm.obs[npcID] = {
--     name, zone,                        dernier nom / zone connus du monstre
--     kills = corps fouillés, money = cuivre ramassé,
--     items = { [itemID] = { n = corps où l'objet est tombé, q = quantité totale } },
--     skins = corps dépecés (ou minés / herboristés), skin = { [itemID] = { n, q } },
--   }
--   ScoutDB.farm.seen = { set = { [GUID] = { l = {objets comptés à la fouille}, s = {… au dépeçage}, sk = dépecé } },
--                         order = { GUID… } }   bornée à MAX_GUIDS
-- Une fenêtre de butin rouverte sur le même corps ne recompte rien : seuls les objets pas encore vus comptent.
local _, ns = ...
local Observed = {}
ns.Observed = Observed

local MAX_GUIDS = 300
local MAX_NAMES = 200
local GATHER_WINDOW = 5   -- secondes entre la fin du sort de récolte et l'ouverture du butin

-- Sorts de récolte sur un corps (rangs Classic) : Dépeçage, Minage, Herboristerie.
local GATHER_SPELLS = { 8613, 8617, 8618, 10768, 2575, 2576, 3564, 10248, 2366, 2368, 3570, 11993 }
local gatherNames = { ["Dépeçage"] = true, ["Minage"] = true, ["Herboristerie"] = true,
    ["Skinning"] = true, ["Mining"] = true, ["Herb Gathering"] = true }
local gatherIDs = {}
for _, id in ipairs(GATHER_SPELLS) do gatherIDs[id] = true end

local moneyStart, lootGuids, gatherAt
local names, nameCount = {}, 0   -- GUID → nom, vus en cible ou au survol

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

ns.OnInit(function()
    for _, id in ipairs(GATHER_SPELLS) do
        local name = SpellName(id)
        if name then gatherNames[name] = true end
    end
end)

local NpcID = ns.NpcID

local function RememberName(unit)
    local guid = UnitGUID(unit)
    if not NpcID(guid) or names[guid] then return end
    local name = UnitName(unit)
    if not name or ns.IsSecret(name) then return end
    if nameCount >= MAX_NAMES then names, nameCount = {}, 0 end
    names[guid] = name
    nameCount = nameCount + 1
end

ns.On("PLAYER_TARGET_CHANGED", function() RememberName("target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() RememberName("mouseover") end)

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" then return end
    if gatherIDs[spellID] or gatherNames[SpellName(spellID) or ""] then gatherAt = GetTime() end
end)

-- Ancien format : items[id] = quantité ; champs ajoutés depuis.
local function Upgrade(e)
    e.skins, e.skin = e.skins or 0, e.skin or {}
    for _, list in ipairs({ e.items, e.skin }) do
        for id, v in pairs(list) do
            if type(v) == "number" then list[id] = { n = v, q = v } end
        end
    end
    return e
end

local function Entry(obs, npc)
    local e = obs[npc]
    if not e then
        e = { kills = 0, money = 0, items = {}, skins = 0, skin = {} }
        obs[npc] = e
    end
    return Upgrade(e)
end

-- État d'un corps : créé à sa première fenêtre de butin (le plus ancien est oublié au-delà de MAX_GUIDS).
local function Corpse(seen, guid)
    if seen.set == nil then seen.set, seen.order = {}, {} end
    local c = seen.set[guid]
    if type(c) == "table" then return c, false end
    local fresh = c == nil   -- `true` : ancien format, corps déjà compté sans le détail des objets
    c = { l = {}, s = {} }
    seen.set[guid] = c
    if fresh then
        table.insert(seen.order, guid)
        if #seen.order > MAX_GUIDS then seen.set[table.remove(seen.order, 1)] = nil end
    end
    return c, fresh
end

local function Copy(t)
    local r = {}
    for k, v in pairs(t) do r[k] = v end
    return r
end

local function Add(list, itemID, qty, counted)
    local v = list[itemID]
    if not v then
        v = { n = 0, q = 0 }
        list[itemID] = v
    end
    if not counted[itemID] then
        counted[itemID] = true
        v.n = v.n + 1
    end
    v.q = v.q + qty
end

ns.On("LOOT_OPENED", function()
    local obs, seen = ns.db.farm.obs, ns.db.farm.seen
    local gathering = gatherAt and GetTime() - gatherAt < GATHER_WINDOW
    gatherAt = nil
    moneyStart, lootGuids = GetMoney(), {}
    local zone = GetRealZoneText and GetRealZoneText()
    if ns.IsSecret(zone) then zone = nil end
    RememberName("target")
    RememberName("mouseover")
    -- Objets déjà vus à une ouverture précédente : pas recomptés (même s'ils réapparaissent sur un autre slot).
    local before = {}
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        if ns.IsSecret(link) then link = nil end
        local itemID = link and tonumber(link:match("item:(%d+)"))
        local sources = { GetLootSourceInfo(slot) }
        for i = 1, #sources, 2 do
            local guid, qty = sources[i], sources[i + 1] or 1
            local npc = NpcID(guid)
            if npc then
                local e = Entry(obs, npc)
                if names[guid] then e.name = names[guid] end
                if zone and zone ~= "" then e.zone = zone end
                local c, fresh = Corpse(seen, guid)
                if before[guid] == nil then before[guid] = { l = Copy(c.l), s = Copy(c.s) } end
                if gathering then
                    if not c.sk then
                        c.sk = true
                        e.skins = e.skins + 1
                    end
                    if itemID and not before[guid].s[itemID] then Add(e.skin, itemID, qty, c.s) end
                else
                    if fresh then e.kills = e.kills + 1 end
                    lootGuids[guid] = npc
                    if itemID and not before[guid].l[itemID] then Add(e.items, itemID, qty, c.l) end
                end
            end
        end
    end
end)

-- L'or ramassé est réparti entre les corps fouillés de la fenêtre de butin.
ns.On("LOOT_CLOSED", function()
    if not moneyStart then return end
    local gained = GetMoney() - moneyStart
    moneyStart = nil
    local n = 0
    for _ in pairs(lootGuids) do n = n + 1 end
    if gained <= 0 or n == 0 then return end
    for _, npc in pairs(lootGuids) do
        local e = Entry(ns.db.farm.obs, npc)
        e.money = e.money + gained / n
    end
end)

-- Valeur moyenne réellement observée par kill (dépeçage compris), aux prix actuels.
function Observed.PerKill(npc)
    local e = ns.db.farm.obs[npc]
    if not e or e.kills == 0 then return nil end
    Upgrade(e)
    local total = e.money
    for _, list in ipairs({ e.items, e.skin }) do
        for id, v in pairs(list) do total = total + v.q * (ns.Prices.ItemValue(id)) end
    end
    return total / e.kills, e.kills
end
