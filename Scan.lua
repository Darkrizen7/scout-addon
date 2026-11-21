-- Scan unique de l'HdV (lecture seule), partagé par les trois onglets :
--   1. browse complet → prix min + quantité par objet (et liste brute pour l'Équipement) ;
--   2. enregistrement des prix utiles + historique, patrons de métier ;
--   3. analyse Équipement (avec requêtes détaillées pour les objets à suffixe).
local _, ns = ...
local Scan = {}
ns.Scan = Scan

local RECIPE_CLASS = Enum.ItemClass and Enum.ItemClass.Recipe or 9
local HISTORY_DAYS = 21

local state = "idle"   -- idle | browsing | equip
local awaitingMore = false
local seen, browseList, browseCount = {}, {}, 0

function Scan.IsRunning() return state ~= "idle" end

local function Status(text)
    if ns.UI then ns.UI.SetStatus(text) end
    ns.Log("[scan] " .. text)
end

---------------------------------------------------------------------------
-- Enregistrement
---------------------------------------------------------------------------
-- Objets dont on garde le prix d'un jour à l'autre : recettes (produits, composants), butin.
local function Wanted()
    local want = {}
    for _, recipes in pairs(ns.db.craft.recipes) do
        for _, r in pairs(recipes) do
            want[r.out] = true
            for _, reagent in ipairs(r.reagents) do want[reagent.id] = true end
        end
    end
    if ns.LootData then
        for id in pairs(ns.LootData.V) do want[id] = true end
    end
    return want
end

local function Store()
    local want, m, day = Wanted(), ns.db.market, date("%Y-%m-%d")
    local kept = 0
    wipe(m.prices)
    for id, e in pairs(seen) do
        local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(id)
        if classID == RECIPE_CLASS and ns.Craft then ns.Craft.RecordPattern(id, "SetItemByID", id) end
        if want[id] or classID == RECIPE_CLASS then
            m.prices[id] = e
            local h = m.hist[id] or {}
            m.hist[id] = h
            if h[#h] and h[#h].d == day then table.remove(h) end
            h[#h + 1] = { d = day, p = e.p, q = e.q }
            while #h > HISTORY_DAYS do table.remove(h, 1) end
            kept = kept + 1
        end
    end
    for id in pairs(want) do   -- objets suivis absents aujourd'hui : 0 en vente
        local h = m.hist[id]
        if h and not seen[id] and not (h[#h] and h[#h].d == day) then h[#h + 1] = { d = day, q = 0 } end
    end
    m.t = time()
    ns.Prices.SetSession(seen)
    ns.Log(("Prix enregistrés : %d objets suivis sur %d vus"):format(kept, browseCount))
end

local function Finish(message)
    state = "idle"
    Status(message)
    if ns.UI then ns.UI.RefreshAll() end
end

---------------------------------------------------------------------------
-- Browse
---------------------------------------------------------------------------
local function Ingest(list)
    awaitingMore = false
    for _, r in ipairs(list or {}) do
        local id, q, p = r.itemKey.itemID, r.totalQuantity or 0, r.minPrice
        if p and q > 0 then
            browseList[#browseList + 1] = r
            local e = seen[id]
            if not e then
                seen[id] = { p = p, q = q }
                browseCount = browseCount + 1
            else
                e.p, e.q = math.min(e.p, p), e.q + q
            end
        end
    end
    Status(("Lecture de l'HdV… %d objets différents"):format(browseCount))
end

local function Continue()
    if C_AuctionHouse.HasFullBrowseResults() then
        Store()
        state = "equip"
        ns.Equip.Evaluate(browseList, function(count)
            Finish(("Scan terminé : %d objets à l'HdV, %d améliorations d'équipement."):format(browseCount, count))
        end)
        return
    end
    if not awaitingMore and C_AuctionHouse.IsThrottledMessageSystemReady() then
        awaitingMore = true
        C_AuctionHouse.RequestMoreBrowseResults()
    end
end

function Scan.Start()
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        return ns.Print("Ouvre l'hôtel des ventes pour scanner.")
    end
    if state ~= "idle" then
        if state == "equip" then ns.Equip.Stop() end
        return ns.Print("Scan déjà en cours (re-clic pendant l'analyse d'équipement : arrêt).")
    end
    wipe(seen) wipe(browseList)
    browseCount, awaitingMore, state = 0, false, "browsing"
    Status("Lecture de l'HdV…")
    C_AuctionHouse.SendBrowseQuery({ searchString = "", sorts = {}, filters = {}, itemClassFilters = {} })
end

ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
    if state ~= "browsing" then return end
    wipe(seen) wipe(browseList) browseCount = 0   -- UPDATED renvoie toute la liste
    Ingest(C_AuctionHouse.GetBrowseResults())
    Continue()
end)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function(added)
    if state ~= "browsing" then return end
    Ingest(added)
    Continue()
end)
ns.On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
    if state == "browsing" then Continue() end
end)
ns.On("AUCTION_HOUSE_CLOSED", function()
    if state == "idle" then return end
    if state == "equip" then ns.Equip.Stop() end
    state = "idle"
    ns.Print("Scan interrompu (HdV fermé).")
end)

ns.commands.scan = Scan.Start
