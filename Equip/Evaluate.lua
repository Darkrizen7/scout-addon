-- Analyse Équipement d'un scan : gain vs équipé, filtre d'usage (infobulle), objets à suffixe.
local _, ns = ...
local Equip = {}
ns.Equip = Equip

local MAX_DETAILS = 40
local DETAIL_TIMEOUT = 3
local MAX_CACHE_RETRIES = 5
local PRICE_SORT = Enum.AuctionHouseSortOrder
    and { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } } or {}
local IGNORED_LOCS = {
    [""] = true, INVTYPE_BODY = true, INVTYPE_TABARD = true, INVTYPE_BAG = true,
    INVTYPE_AMMO = true, INVTYPE_QUIVER = true, INVTYPE_NON_EQUIP_IGNORE = true,
}

local running = false
local results = {}
local pending, details, inflight = {}, {}, {}
local currentDetail, detailTimer, onDone, ctx
local retries, skipped = 0, 0

function Equip.Results() return results end

local function Key(itemKey)
    return ("%d:%d:%d"):format(itemKey.itemID, itemKey.itemLevel or 0, itemKey.itemSuffix or 0)
end

local function Status(fmt, ...)
    if ns.UI then ns.UI.SetStatus(fmt:format(...)) end
end

local function Done()
    if not running then return end
    running = false
    if detailTimer then detailTimer:Cancel() detailTimer = nil end
    wipe(inflight)
    ns.Log(("Équipement : %d améliorations, %d objets non équipables écartés"):format(#results, skipped))
    if onDone then onDone(#results) end
end

function Equip.Stop() Done() end

local function AddResult(r, link, stats, price)
    local _, _, _, loc = C_Item.GetItemInfoInstant(r.itemKey.itemID)
    local gain, slotLabel = ns.Equipped.Gain(stats, loc, ctx.w)
    if not gain or gain <= 0.05 then return end
    local name, fullLink, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(link)
    if not name then name, fullLink, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(r.itemKey.itemID) end
    if not link:find("|H") and fullLink then link = fullLink end
    if not ns.Equipped.IsUsableByTooltip(link, (ns.db.equip.lookahead or 0) > 0) then
        skipped = skipped + 1
        return
    end
    local gold = math.max(price / 10000, 0.01)
    table.insert(results, {
        browse = r, link = link, name = name or "?", quality = quality or 1, icon = icon,
        itemLevel = r.itemKey.itemLevel, slot = slotLabel, gain = gain, price = price, ratio = gain / gold,
    })
end

-- Renvoie false si l'info client manque encore (à réessayer).
local function Evaluate(r)
    local id = r.itemKey.itemID
    local _, _, _, loc, _, classID, subClassID = C_Item.GetItemInfoInstant(id)
    if not loc or IGNORED_LOCS[loc] then return true end
    if not ns.Equipped.CanUse(classID, subClassID, ctx.level) then return true end
    local name, _, _, _, minLevel = C_Item.GetItemInfo(id)
    if not name then
        C_Item.RequestLoadItemDataByID(id)
        return false
    end
    if (minLevel or 0) > ctx.level then return true end
    local suffix = r.itemKey.itemSuffix or 0
    local link = suffix ~= 0 and ("item:%d:0:0:0:0:0:%d"):format(id, suffix) or ("item:" .. id)
    local stats = ns.Stats.FromLink(link)
    if not stats and suffix ~= 0 then
        if #details < MAX_DETAILS then table.insert(details, r) end
        return true
    end
    AddResult(r, link, stats or {}, r.minPrice)
    return true
end

---------------------------------------------------------------------------
-- Requêtes détaillées (objets à suffixe dont le client ne connaît pas les stats)
---------------------------------------------------------------------------
local NextDetail

local function SendDetail()
    local r = currentDetail
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then
        C_Timer.After(0.3, function()
            if running and currentDetail == r and not detailTimer then SendDetail() end
        end)
        return
    end
    inflight[Key(r.itemKey)] = r
    C_AuctionHouse.SendSearchQuery(r.itemKey, PRICE_SORT, false)
    detailTimer = C_Timer.NewTimer(DETAIL_TIMEOUT, function()
        if running and currentDetail == r then NextDetail() end
    end)
end

function NextDetail()
    if detailTimer then detailTimer:Cancel() detailTimer = nil end
    currentDetail = table.remove(details, 1)
    if not currentDetail then
        if next(inflight) then C_Timer.After(DETAIL_TIMEOUT, Done) return end
        return Done()
    end
    Status("Équipement : détail des objets à suffixe (%d restants)…", #details + 1)
    SendDetail()
end

ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
    if not running then return end
    local k = Key(itemKey)
    local r = inflight[k]
    if not r then return end
    inflight[k] = nil
    local info = C_AuctionHouse.GetNumItemSearchResults(itemKey) > 0
        and C_AuctionHouse.GetItemSearchResultInfo(itemKey, 1)
    if info and info.itemLink then
        AddResult(r, info.itemLink, ns.Stats.FromLink(info.itemLink) or {}, info.buyoutAmount or r.minPrice)
    end
    if currentDetail == r then NextDetail() end
end)

---------------------------------------------------------------------------
-- Entrée
---------------------------------------------------------------------------
local function EvaluatePending()
    local left = {}
    for _, r in ipairs(pending) do
        if not Evaluate(r) then left[#left + 1] = r end
    end
    pending = left
    if #pending > 0 and retries < MAX_CACHE_RETRIES then
        retries = retries + 1
        C_Timer.After(1, function() if running then EvaluatePending() end end)
        return
    end
    NextDetail()
end

function Equip.Evaluate(list, done)
    local cur = ns.Weights.Current()
    ctx = { w = cur.w, level = UnitLevel("player") + (ns.db.equip.lookahead or 0) }
    onDone, running, retries, skipped, currentDetail = done, true, 0, 0, nil
    wipe(results) wipe(details) wipe(inflight)
    pending = {}
    ns.Equipped.Refresh()
    for _, r in ipairs(list) do
        local _, _, _, loc = C_Item.GetItemInfoInstant(r.itemKey.itemID)
        if loc and not IGNORED_LOCS[loc] then pending[#pending + 1] = r end
    end
    Status("Équipement : analyse de %d annonces…", #pending)
    EvaluatePending()
end
