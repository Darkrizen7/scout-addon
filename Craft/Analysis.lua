-- Calcul par recette : coût des composants, prix de vente, bénéfice, coût d'apprentissage,
-- nombre de crafts pour rembourser, offre à l'HdV et tendance.
local _, ns = ...
local Analysis = {}
ns.Analysis = Analysis

Analysis.MODES = {
    { key = "learnable", label = "À apprendre" },
    { key = "soon", label = "Bientôt (+25)" },
    { key = "known", label = "Connues" },
    { key = "all", label = "Toutes" },
}
local SOON = 25

local function ReagentCost(r)
    local total, missing = 0, {}
    for _, reagent in ipairs(r.reagents) do
        local unit = ns.Prices.Buy(reagent.id)
        if unit then total = total + unit * reagent.n else missing[#missing + 1] = reagent.id end
    end
    return total, missing
end

-- Tendance de l'offre : quantité aujourd'hui vs moyenne des jours précédents.
local function Trend(id)
    local h = ns.Prices.History(id)
    if #h < 2 then return nil end
    local sum = 0
    for i = 1, #h - 1 do sum = sum + (h[i].q or 0) end
    return (h[#h].q or 0) - sum / (#h - 1), #h
end

function Analysis.Row(line, id, r)
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
    return row
end

local function Keep(row, mode, rank)
    if mode == "known" then return row.known end
    if mode == "all" then return true end
    -- Niveau requis inconnu : on ne peut pas savoir si c'est apprenable, donc seulement dans « Toutes ».
    if row.known or not row.learn or not row.req then return false end
    if mode == "learnable" then return row.req <= rank end
    return row.req <= rank + SOON
end

function Analysis.Rows(line, mode)
    local skill = ns.char.skills[line]
    local rank = skill and skill.rank or 0
    local rows = {}
    for id, r in pairs(ns.db.craft.recipes[line] or {}) do
        local row = Analysis.Row(line, id, r)
        if Keep(row, mode, rank) then rows[#rows + 1] = row end
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
