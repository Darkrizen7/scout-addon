-- Onglet Objets : recherche d'un objet vu à l'HdV et courbe de son prix sur 30 jours.
-- Un clic sur un résultat de l'HdV le sélectionne ici (sans changer d'onglet).
local _, ns = ...

local TAB = "Objets"
local lv, chart, box
local query = ""                 -- texte de recherche (variable de module, pas sauvegardé)
local selected, selectedName     -- objet sélectionné
local shown, total = 0, 0
local foldCache = {}             -- id -> nom replié

-- Minuscules sans accents (UTF-8 : lower() ne touche pas aux majuscules accentuées).
local ACCENTS = {
    ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
    ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["À"] = "a", ["Â"] = "a", ["Ä"] = "a",
    ["î"] = "i", ["ï"] = "i", ["Î"] = "i", ["Ï"] = "i",
    ["ô"] = "o", ["ö"] = "o", ["Ô"] = "o", ["Ö"] = "o",
    ["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["Ù"] = "u", ["Û"] = "u", ["Ü"] = "u",
    ["ç"] = "c", ["Ç"] = "c", ["œ"] = "oe", ["Œ"] = "oe", ["æ"] = "ae", ["Æ"] = "ae",
}

local function Fold(s)
    return (s:lower():gsub("[\195\197][\128-\191]", ACCENTS))
end
ns.Fold = Fold

local function FoldedName(id, name)
    local f = foldCache[id]
    if not f or f.name ~= name then
        f = { name = name, fold = Fold(name) }
        foldCache[id] = f
    end
    return f.fold
end

local function Matches(id, name, q)
    return q == "" or FoldedName(id, name):find(q, 1, true) ~= nil
end

-- Dernier prix connu : HdV, sinon dernier jour de l'historique. Mis en cache jusqu'au prochain scan
-- (sinon chaque frappe relirait l'historique de milliers d'objets).
local priceCache, priceStamp = {}, nil

local function ComputeLastPrice(id)
    local p = ns.Prices.AH(id)
    if p and p > 0 then return p end
    local days = ns.Prices.Daily(id)
    if not days then return false end
    local last
    for d in pairs(days) do
        if not last or d > last then last = d end
    end
    if last then return days[last] end
    return false
end

local function LastPrice(id)
    local m = ns.db.market
    local stamp = (m.t or 0) + (m.tq or 0)
    if stamp ~= priceStamp then wipe(priceCache) priceStamp = stamp end
    local p = priceCache[id]
    if p == nil then
        p = ComputeLastPrice(id)
        priceCache[id] = p
    end
    return p or nil
end

local COLUMNS = {
    { key = "fold", title = "Objet", width = 200, ascending = true, text = function(d)
        local label = d.id == selected and ("> " .. d.name) or d.name
        local _, _, quality = C_Item.GetItemInfo(d.id)
        if quality then
            local r, g, b = (C_Item.GetItemQualityColor or GetItemQualityColor)(quality)
            return label, r, g, b
        end
        return label
    end },
    { key = "price", title = "Prix", width = 90, justify = "RIGHT", text = function(d)
        return d.price and ns.Money(d.price) or ""
    end },
}

local function OnEnter(row, d)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(d.id) else GameTooltip:SetHyperlink("item:" .. d.id) end
    GameTooltip:Show()
end

local function Refresh()
    if not lv then return end
    local q = Fold(query)
    local rows = {}
    total = 0
    for id, name in pairs(ns.db.market.names) do
        total = total + 1
        if Matches(id, name, q) then rows[#rows + 1] = { id = id, name = name, fold = FoldedName(id, name), price = LastPrice(id) } end
    end
    shown = #rows
    lv:SetRows(rows)
    chart:Draw(selected, selectedName)
end

local function Choose(id, name)
    selected, selectedName = id, name
    ns.UI.RefreshAll()
end

-- Appelé depuis l'HdV : sélectionne l'objet, et le rend visible dans la liste.
local function SelectFromAuction(id, hint)
    local name = ns.db.market.names[id] or hint or C_Item.GetItemInfo(id) or ("Objet " .. id)
    selected, selectedName = id, name
    if not Matches(id, name, Fold(query)) then
        query = name
        if box then box:SetText(name) end
    end
    if ns.UI.IsCurrent(TAB) then ns.UI.RefreshAll() end
end

local hooked = false
ns.On("AUCTION_HOUSE_SHOW", function()
    if hooked or not (AuctionHouseFrame and AuctionHouseFrame.SelectBrowseResult) then return end
    hooked = true
    hooksecurefunc(AuctionHouseFrame, "SelectBrowseResult", function(_, r)
        local key = r and r.itemKey
        if key and key.itemID then SelectFromAuction(key.itemID) end
    end)
end)

ns.UI.RegisterTab({
    name = TAB,
    help = "Cherche un objet ou clique-le dans l'HdV pour voir son prix sur 30 jours.",
    build = function(toolbar, content)
        box = CreateFrame("EditBox", nil, toolbar, "SearchBoxTemplate")
        box:SetSize(200, 20)
        box:SetPoint("LEFT", 6, 0)
        box:SetAutoFocus(false)
        box:SetText(query)
        box:HookScript("OnTextChanged", function(self)
            query = self:GetText() or ""
            if ns.UI.IsCurrent(TAB) then ns.UI.RefreshAll() end
        end)

        local left = CreateFrame("Frame", nil, content)
        left:SetPoint("TOPLEFT", 0, 0)
        left:SetSize(340, 408)
        lv = ns.ListView.Create(left, {
            columns = COLUMNS, icon = function(d) return C_Item.GetItemIconByID(d.id) end,
            onEnter = OnEnter, onClick = function(_, d) Choose(d.id, d.name) end,
            sortKey = "fold", sortDesc = false,
        })
        local frame
        chart, frame = ns.PriceChart.Embed(content)
        frame:SetPoint("TOPLEFT", 350, 0)
    end,
    refresh = Refresh,
    status = function()
        if shown == total then return ("%d objets"):format(total) end
        return ("%d / %d objets"):format(shown, total)
    end,
})
