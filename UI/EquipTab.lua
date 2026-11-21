-- Onglet Équipement : meilleures améliorations par slot dans ton budget.
local _, ns = ...

local LOOKAHEAD_STEPS = { 0, 2, 5 }
local BUDGET_STEPS = { 0, 1, 5, 10, 25, 50, 100, 250 }   -- po, 0 = aucun
local lv, buttons = nil, {}

local function Cycle(steps, cur)
    for i, v in ipairs(steps) do
        if v == cur then return steps[i % #steps + 1] end
    end
    return steps[1]
end

local function Labels()
    local db = ns.db.equip
    buttons.ahead:SetText(("Niv. +%d"):format(db.lookahead or 0))
    buttons.budget:SetText((db.budget or 0) == 0 and "Budget : aucun" or ("Budget : %d po"):format(db.budget))
    buttons.mode:SetText(db.bestOnly and "Meilleur / slot" or "Options")
end

local function Number(n) return n >= 100 and ("%d"):format(n) or ("%.1f"):format(n) end

local COLUMNS = {
    { key = "name", title = "Objet", width = 230, ascending = true, text = function(d)
        local r, g, b = (C_Item.GetItemQualityColor or GetItemQualityColor)(d.quality)
        return d.name, r, g, b
    end },
    { key = "slot", title = "Slot", width = 90, ascending = true, text = function(d) return d.slot end },
    { key = "gain", title = "Gain", width = 60, justify = "RIGHT", text = function(d) return Number(d.gain) end },
    { key = "price", title = "Prix", width = 100, justify = "RIGHT", ascending = true, text = function(d) return ns.Money(d.price) end },
    { key = "ratio", title = "Gain/po", width = 70, justify = "RIGHT", text = function(d) return Number(d.ratio) end },
}

local function OnEnter(row, d)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(d.link)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("Gain %.1f pour %s"):format(d.gain, ns.Money(d.price)), 0.2, 1, 0.6)
    if d.stepGain then
        GameTooltip:AddLine(("+%.1f de gain pour %s de plus que l'option moins chère")
            :format(d.stepGain, ns.Money(d.stepPrice)), 1, 0.82, 0)
    end
    GameTooltip:AddLine("Clic : ouvrir la page d'achat", 0.7, 0.7, 0.7)
    GameTooltip:Show()
    if GameTooltip_ShowCompareItem then GameTooltip_ShowCompareItem(GameTooltip) end
end

local function OnClick(_, d)
    if AuctionHouseFrame and AuctionHouseFrame:IsShown() and AuctionHouseFrame.SelectBrowseResult then
        AuctionHouseFrame:SelectBrowseResult(d.browse)
    end
end

ns.UI.RegisterTab({
    name = "Équipement",
    build = function(toolbar, content)
        local db = ns.db.equip
        local B = ns.UI.Button
        buttons.ahead = B(toolbar, 70, "", function()
            db.lookahead = Cycle(LOOKAHEAD_STEPS, db.lookahead or 0) Labels()
        end, "Inclure les objets jusqu'à N niveaux au-dessus du tien (au prochain scan)")
        buttons.ahead:SetPoint("LEFT")
        buttons.budget = B(toolbar, 115, "", function()
            db.budget = Cycle(BUDGET_STEPS, db.budget or 0) Labels() ns.UI.RefreshAll()
        end, "Prix maximum par objet")
        buttons.budget:SetPoint("LEFT", buttons.ahead, "RIGHT", 4, 0)
        buttons.mode = B(toolbar, 115, "", function()
            db.bestOnly = not db.bestOnly Labels() ns.UI.RefreshAll()
        end, "Meilleur / slot : le plus gros gain dans ton budget pour chaque emplacement.\n"
            .. "Options : tous les choix utiles (on retire ceux qu'un objet moins cher bat).")
        buttons.mode:SetPoint("LEFT", buttons.budget, "RIGHT", 4, 0)
        Labels()
        lv = ns.ListView.Create(content, {
            columns = COLUMNS, icon = function(d) return d.icon end, onEnter = OnEnter, onClick = OnClick,
            sortKey = "gain", tiebreak = function(a, b) return a.ratio > b.ratio end,
        })
    end,
    refresh = function()
        local db = ns.db.equip
        lv:SetRows(ns.Ranking.Select(ns.Equip.Results(), (db.budget or 0) * 10000, db.bestOnly))
    end,
    status = function()
        local n = #ns.Equip.Results()
        return ("%s · %s"):format(ns.Weights.Current().label,
            n > 0 and (n .. " améliorations au dernier scan") or "lance un scan à l'HdV")
    end,
})
