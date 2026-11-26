-- Onglet Métiers : quelles recettes apprendre pour fabriquer et revendre.
local _, ns = ...

local SOURCE_TAG = { ["maître"] = "M", marchand = "V", HdV = "H" }
local lv, buttons = nil, {}
local profIndex = 1
local lastCount = 0

local function Profession()
    local list = ns.Analysis.Professions()
    if #list == 0 then return nil end
    if profIndex > #list then profIndex = 1 end
    return list[profIndex]
end

local function ItemName(id)
    local name = C_Item.GetItemInfo(id)
    if not name then C_Item.RequestLoadItemDataByID(id) end
    return name
end

local function ProfitColor(v)
    if not v then return 0.6, 0.6, 0.6 end
    if v > 0 then return 0.3, 1, 0.3 end
    return 1, 0.35, 0.35
end

local COLUMNS = {
    -- Couleur du jeu : chance de gagner un point (orange / jaune / vert / gris, rouge = niveau trop bas).
    { key = "name", title = "Objet fabriqué", width = 185, ascending = true, text = function(d)
        local c = d.color and ns.Analysis.COLORS[d.color]
        if c then return d.name, c[1], c[2], c[3] end
        return d.name, 1, 1, 1
    end },
    { key = "req", title = "Niv.", width = 32, justify = "RIGHT", ascending = true, text = function(d) return d.req and tostring(d.req) end },
    { key = "learnCost", title = "Apprendre", width = 95, justify = "RIGHT", ascending = true, text = function(d)
        if d.known then return "connue", 0.4, 1, 0.4 end
        if d.learn then return ns.Money(d.learn.cost) .. " " .. (SOURCE_TAG[d.learn.kind] or "") end
        return "?", 0.6, 0.6, 0.6
    end },
    { key = "cost", title = "Coût", width = 75, justify = "RIGHT", ascending = true, text = function(d)
        return d.complete and ns.Money(d.cost) or "?"
    end },
    { key = "sell", title = "Vente", width = 75, justify = "RIGHT", text = function(d) return ns.Money(d.sell) end },
    { key = "profit", title = "Bénéfice", width = 78, justify = "RIGHT", text = function(d)
        if not d.profit then return "—", 0.6, 0.6, 0.6 end
        return (d.profit >= 0 and "+" or "-") .. ns.Money(d.profit), ProfitColor(d.profit)
    end },
    { key = "repay", title = "Remb.", width = 42, justify = "RIGHT", ascending = true, text = function(d) return d.repay and tostring(d.repay) end },
    { key = "supply", title = "En vente", width = 55, justify = "RIGHT", ascending = true, text = function(d) return tostring(d.supply) end },
}

local SKILL_TEXT = { red = "Niveau de métier insuffisant", orange = "Orange : gagne toujours un point",
    yellow = "Jaune : gagne souvent un point", green = "Vert : gagne parfois un point",
    grey = "Gris : ne fait plus monter le métier" }

local function OnEnter(row, d)
    local GT = GameTooltip
    GT:SetOwner(row, "ANCHOR_RIGHT")
    GT:SetItemByID(d.recipe.out)
    GT:AddLine(" ")
    local c = d.color and ns.Analysis.COLORS[d.color]
    if c then GT:AddLine(SKILL_TEXT[d.color], c[1], c[2], c[3]) end
    if d.known then
        GT:AddLine("Recette connue", 0.4, 1, 0.4)
    elseif d.learn then
        GT:AddLine(("Apprendre : %s (%s)%s"):format(ns.Money(d.learn.cost), d.learn.kind,
            d.req and (" · niveau " .. d.req) or ""), 1, 0.82, 0)
    else
        GT:AddLine("Source inconnue : pas encore vue chez un maître, un marchand ou à l'HdV", 0.6, 0.6, 0.6)
    end
    GT:AddLine("Composants :", 1, 1, 1)
    for _, reagent in ipairs(d.recipe.reagents) do
        local unit = ns.Prices.Buy(reagent.id)
        GT:AddDoubleLine(("  %s ×%d"):format(ItemName(reagent.id) or ("objet " .. reagent.id), reagent.n),
            unit and ns.Money(unit * reagent.n) or "prix inconnu", 0.9, 0.9, 0.9, 1, 1, 1)
    end
    if d.sell then
        GT:AddDoubleLine(("Vente (×%d, après 5 %% de l'HdV)"):format(d.recipe.qty), ns.Money(d.sell), 1, 1, 1, 1, 1, 1)
    else
        GT:AddLine("Pas en vente à l'HdV au dernier scan", 0.6, 0.6, 0.6)
    end
    local h = ns.Prices.History(d.recipe.out)
    if #h > 0 then
        local parts = {}
        for i = math.max(1, #h - 6), #h do parts[#parts + 1] = tostring(h[i].q or 0) end
        GT:AddLine("En vente, derniers scans : " .. table.concat(parts, " → "), 0.7, 0.85, 1)
    end
    if d.repay then GT:AddLine(("Remboursé après %d craft(s)"):format(d.repay), 0.4, 1, 0.4) end
    GT:AddLine("Clic : chercher l'objet à l'HdV", 0.7, 0.7, 0.7)
    GT:AddLine("Maj-clic : courbe de prix (30 j)", 0.7, 0.7, 0.7)
    GT:Show()
end

local function OnClick(_, d)
    if IsShiftKeyDown() then
        ns.PriceChart.Show(d.recipe.out, d.name)
        return
    end
    local bar = AuctionHouseFrame and AuctionHouseFrame:IsShown() and AuctionHouseFrame.SearchBar
    if bar then
        bar:SetSearchText(d.name)
        bar:StartSearch()
    end
end

ns.UI.RegisterTab({
    name = "Métiers",
    help = "Coche ce que tu veux voir : les couleurs disent si la recette fait encore monter ton métier.",
    build = function(toolbar, content)
        local B = ns.UI.Button
        buttons.prof = B(toolbar, 140, "", function() profIndex = profIndex + 1 ns.UI.RefreshAll() end,
            "Changer de métier (ouvre la fenêtre d'un métier une fois pour qu'il apparaisse)")
        buttons.prof:SetPoint("LEFT")
        local anchor = buttons.prof
        for _, f in ipairs(ns.Analysis.FILTERS) do
            local cb = CreateFrame("CheckButton", nil, toolbar, "UICheckButtonTemplate")
            cb:SetSize(24, 24)
            cb:SetPoint("LEFT", anchor, "RIGHT", anchor == buttons.prof and 6 or 2, 0)
            local label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("LEFT", cb, "RIGHT", 0, 1)
            label:SetText(f.label)
            cb:SetHitRectInsets(0, -label:GetStringWidth(), 0, 0)
            cb:SetScript("OnClick", function(self)
                ns.db.ui.craftShow[f.key] = self:GetChecked() and true or false
                ns.UI.RefreshAll()
            end)
            cb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:SetText(f.label, 1, 1, 1)
                GameTooltip:AddLine(f.tip, nil, nil, nil, true)
                GameTooltip:Show()
            end)
            cb:SetScript("OnLeave", GameTooltip_Hide)
            buttons[f.key] = cb
            anchor = label
        end
        lv = ns.ListView.Create(content, {
            columns = COLUMNS, icon = function(d) return C_Item.GetItemIconByID(d.recipe.out) end,
            onEnter = OnEnter, onClick = OnClick, sortKey = "profit",
            tiebreak = function(a, b) return a.name < b.name end,
        })
    end,
    refresh = function()
        local prof = Profession()
        local show = ns.db.ui.craftShow
        for _, f in ipairs(ns.Analysis.FILTERS) do buttons[f.key]:SetChecked(show[f.key] == true) end
        buttons.prof:SetText(prof and prof.name or "Aucun métier")
        local rows = prof and ns.Analysis.Rows(prof.line, show) or {}
        for _, row in ipairs(rows) do
            row.name = ItemName(row.recipe.out) or row.recipe.name
            row.learnCost = row.learn and row.learn.cost or (row.known and 0 or nil)
        end
        lastCount = #rows
        lv:SetRows(rows)
    end,
    status = function()
        local prof = Profession()
        if not prof then return "Ouvre la fenêtre d'un de tes métiers pour charger ses recettes." end
        local skill = ns.char.skills[prof.line]
        local t = ns.db.market.t
        return ("%s %s · %d recettes · prix : %s"):format(prof.name,
            skill and (skill.rank .. "/" .. skill.max) or "", lastCount, t and date("%d/%m %H:%M", t) or "aucun scan")
    end,
})
