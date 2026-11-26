-- Calcul par recette : coût des composants, prix de vente, bénéfice, coût d'apprentissage,
-- nombre de crafts pour rembourser, offre à l'HdV et tendance.
local _, ns = ...
local Analysis = {}
ns.Analysis = Analysis

-- Cases à cocher de l'onglet (combinables), choix gardé dans ns.db.ui.craftShow.
Analysis.FILTERS = {
    { key = "known", label = "Apprises", tip = "Tes recettes." },
    { key = "learn", label = "À apprendre",
      tip = "Pas apprises, de ton niveau, disponibles chez un maître, un marchand ou à l'HdV." },
    { key = "high", label = "Trop haut", tip = "Pas encore accessibles : jusqu'à +25 points au-dessus de ton niveau." },
}
local SOON = 25

-- Chance de gagner un point, comme dans le jeu (Enum.TradeskillRelativeDifficulty) ; « red » = niveau insuffisant.
local DIFF = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "grey" }
Analysis.COLORS = {
    red = { 1, 0.1, 0.1 }, orange = { 1, 0.5, 0.25 }, yellow = { 1, 1, 0 },
    green = { 0.25, 0.75, 0.25 }, grey = { 0.5, 0.5, 0.5 },
}

-- Couleur de la recette : celle du jeu si la fenêtre du métier a été ouverte à ce niveau, sinon estimée
-- (Classic : jaune à mi-chemin entre le niveau requis et le gris, vert à mi-chemin entre jaune et gris).
local function SkillColor(line, id, r, req, rank)
    if req and rank < req then return "red" end
    local d = ns.char.diff and ns.char.diff[line]
    if d and d.rank == rank and DIFF[d.ids[id]] then return DIFF[d.ids[id]] end
    local grey = r.trivial
    if not grey or grey <= 0 then return nil end
    if rank >= grey then return "grey" end
    if not req then return nil end
    local yellow = (req + grey) / 2
    if rank < yellow then return "orange" end
    if rank < (yellow + grey) / 2 then return "yellow" end
    return "green"
end

local function ReagentCost(r)
    local total, missing = 0, {}
    for _, reagent in ipairs(r.reagents) do
        local unit = ns.Prices.Buy(reagent.id)
        if unit then total = total + unit * reagent.n else missing[#missing + 1] = reagent.id end
    end
    return total, missing
end

-- Tendance de l'offre : quantité au dernier scan vs moyenne des scans précédents.
local function Trend(id)
    local h = ns.Prices.History(id)
    if #h < 2 then return nil end
    local sum = 0
    for i = 1, #h - 1 do sum = sum + (h[i].q or 0) end
    return (h[#h].q or 0) - sum / (#h - 1), #h
end

function Analysis.Row(line, id, r, rank)
    local known = ns.char.known[id] == true
    local learn = not known and ns.Sources.Learn(line, r) or nil
    local cost, missing = ReagentCost(r)
    local unitSell = ns.Prices.Sell(r.out)
    local row = {
        id = id, recipe = r, known = known, learn = learn, req = learn and learn.req,
        cost = cost, missing = missing, complete = #missing == 0,
        sell = unitSell and unitSell * r.qty, supply = ns.Prices.Quantity(r.out) or 0,
    }
    if row.sell and row.complete then row.profit = row.sell - cost end
    if learn and row.profit and row.profit > 0 then
        row.repay = math.ceil((learn.cost or 0) / row.profit)
    end
    row.trend, row.days = Trend(r.out)
    row.color = SkillColor(line, id, r, row.req, rank or 0)
    return row
end

-- Niveau requis inconnu : on ne peut pas savoir si c'est apprenable, la recette n'est dans aucune case.
local function Keep(row, show, rank)
    if row.known then return show.known end
    if not row.learn or not row.req then return false end
    if row.req <= rank then return show.learn end
    return show.high and row.req <= rank + SOON
end

function Analysis.Rows(line, show)
    local skill = ns.char.skills[line]
    local rank = skill and skill.rank or 0
    local rows = {}
    for id, r in pairs(ns.db.craft.recipes[line] or {}) do
        local row = Analysis.Row(line, id, r, rank)
        if Keep(row, show, rank) then rows[#rows + 1] = row end
    end
    return rows
end

-- Métiers dont on connaît les recettes, avec leur nom.
function Analysis.Professions()
    local list = {}
    for line in pairs(ns.db.craft.recipes) do
        local s = ns.char.skills[line]
        list[#list + 1] = { line = line, name = s and s.name or tostring(line) }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end
