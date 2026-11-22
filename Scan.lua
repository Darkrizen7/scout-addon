-- Scan unique de l'HdV (lecture seule), partagé par les trois onglets :
--   1. browse complet → prix min + quantité par objet (et liste brute pour l'Équipement) ;
--   2. enregistrement des prix utiles + historique, patrons de métier ;
--   3. analyse Équipement (avec requêtes détaillées pour les objets à suffixe).
local _, ns = ...
local Scan = {}
ns.Scan = Scan

local RECIPE_CLASS = Enum.ItemClass and Enum.ItemClass.Recipe or 9
local HISTORY_DAYS = 21   -- durée de conservation des relevés (chaque scan est gardé)

local state = "idle"   -- idle | browsing | equip
local sending = false  -- vrai pendant notre propre SendBrowseQuery
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

-- Ancien format (une entrée par jour, sans heure) : on date l'entrée à midi ce jour-là.
local function EntryTime(e)
    if not e.t and e.d then
        local y, mo, d = e.d:match("(%d+)-(%d+)-(%d+)")
        e.t = time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 12 })
        e.d = nil
    end
    return e.t or 0
end

-- Ajoute un relevé et oublie ceux de plus de HISTORY_DAYS jours.
local function Record(m, id, entry)
    local h = m.hist[id] or {}
    m.hist[id] = h
    h[#h + 1] = entry
    local cutoff = entry.t - HISTORY_DAYS * 86400
    while h[1] and EntryTime(h[1]) < cutoff do table.remove(h, 1) end
    for _, e in ipairs(h) do EntryTime(e) end
end

-- Nom de chaque objet vu, pour l'export : même numéro d'objet que dans Auctionator et Forever Guide,
-- ce qui permet de nommer aussi leurs relevés. Les noms absents du cache client arrivent plus tard.
local pendingNames = {}

local function RememberName(id)
    local names = ns.db.market.names
    if names[id] then return end
    local name = C_Item.GetItemInfo(id)
    if name then
        names[id] = name
    else
        pendingNames[id] = true
        C_Item.RequestLoadItemDataByID(id)
    end
end

ns.On("GET_ITEM_INFO_RECEIVED", function(id, success)
    if not pendingNames[id] then return end
    pendingNames[id] = nil
    if success then ns.db.market.names[id] = C_Item.GetItemInfo(id) end
end)

-- Un scan qui voit beaucoup moins d'objets que le précédent a sans doute été coupé par une autre
-- recherche : on ne l'enregistre pas (sinon tous les objets suivis passeraient à « 0 en vente »).
local MIN_RATIO = 0.5

local function Store()
    local want, m, now = Wanted(), ns.db.market, time()
    if m.n and browseCount < m.n * MIN_RATIO then
        return false
    end
    local kept = 0
    wipe(m.prices)
    for id, e in pairs(seen) do
        local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(id)
        if classID == RECIPE_CLASS and ns.Craft then ns.Craft.RecordPattern(id, "SetItemByID", id) end
        RememberName(id)
        if want[id] or classID == RECIPE_CLASS then
            m.prices[id] = e
            Record(m, id, { t = now, p = e.p, q = e.q })
            kept = kept + 1
        end
    end
    for id in pairs(want) do   -- objets suivis absents de ce scan : 0 en vente
        if m.hist[id] and not seen[id] then Record(m, id, { t = now, q = 0 }) end
    end
    m.t, m.n = now, browseCount
    ns.Prices.SetSession(seen)
    ns.Log(("Prix enregistrés : %d objets suivis sur %d vus"):format(kept, browseCount))
    return true
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

local function Abort(reason)
    state = "idle"
    wipe(seen) wipe(browseList) browseCount = 0
    ns.Print("Scan annulé : " .. reason .. " Rien n'a été enregistré, relance le scan.")
    Finish("Scan annulé, rien d'enregistré.")
end

local function Continue()
    if C_AuctionHouse.HasFullBrowseResults() then
        if not Store() then
            return Abort(("seulement %d objets vus contre %d au scan précédent."):format(
                browseCount, ns.db.market.n))
        end
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
    sending = true
    C_AuctionHouse.SendBrowseQuery({ searchString = "", sorts = {}, filters = {}, itemClassFilters = {} })
    sending = false
end

-- Toute autre recherche pendant la lecture (barre de recherche, favoris, Forever Guide, Auctionator…)
-- remplace les résultats de l'HdV : le scan en cours n'est plus valable.
local function OtherQuery()
    if state == "browsing" and not sending then
        Abort("une autre recherche a été lancée à l'HdV pendant la lecture "
            .. "(barre de recherche, favoris, scan de Forever Guide ou d'Auctionator…).")
    end
end
hooksecurefunc(C_AuctionHouse, "SendBrowseQuery", OtherQuery)
if C_AuctionHouse.SearchForFavorites then hooksecurefunc(C_AuctionHouse, "SearchForFavorites", OtherQuery) end

ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
    if state ~= "browsing" then return end
    local results = C_AuctionHouse.GetBrowseResults()
    if #results < browseCount then   -- moins de lignes que d'objets déjà lus : autre recherche
        return Abort("les résultats de l'HdV ont été remplacés par une autre recherche.")
    end
    wipe(seen) wipe(browseList) browseCount = 0   -- UPDATED renvoie toute la liste
    Ingest(results)
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
