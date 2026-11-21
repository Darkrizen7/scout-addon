-- Sélection des objets à afficher : budget, options utiles par slot, meilleur par slot.
local _, ns = ...
local Ranking = {}
ns.Ranking = Ranking

-- Options utiles d'un slot (frontière de Pareto) : triées par prix croissant, on ne garde
-- un objet que s'il fait mieux que toutes les options moins chères. Chaque option garde
-- l'écart avec la précédente (stepGain, stepPrice) pour l'infobulle.
local function Frontier(items)
    table.sort(items, function(a, b)
        if a.price == b.price then return a.gain > b.gain end
        return a.price < b.price
    end)
    local out, prev = {}, nil
    for _, item in ipairs(items) do
        if not prev or item.gain > prev.gain then
            item.stepGain = prev and item.gain - prev.gain or nil
            item.stepPrice = prev and item.price - prev.price or nil
            out[#out + 1] = item
            prev = item
        end
    end
    return out
end

-- budget : prix max en cuivre (0 = aucun) ; bestOnly : une ligne par slot.
function Ranking.Select(list, budget, bestOnly)
    local bySlot = {}
    for _, item in ipairs(list) do
        if budget == 0 or item.price <= budget then
            bySlot[item.slot] = bySlot[item.slot] or {}
            table.insert(bySlot[item.slot], item)
        end
    end
    local out = {}
    for _, items in pairs(bySlot) do
        local frontier = Frontier(items)
        if bestOnly then
            out[#out + 1] = frontier[#frontier]
        else
            for _, item in ipairs(frontier) do out[#out + 1] = item end
        end
    end
    return out
end
