-- Onglet Farm : monstres de ton niveau classés par valeur moyenne par kill.
local _, ns = ...

local lv, buttons = nil, {}
local opts = { range = 1, elites = false }
local lastCount, lastSkin = 0, nil

local function ItemName(id)
    local name = C_Item.GetItemInfo(id)
    if not name then C_Item.RequestLoadItemDataByID(id) end
    return name or ("objet " .. id)
end

local COLUMNS = {
    { key = "name", title = "Monstre", width = 150, ascending = true, text = function(d)
        if d.elite then return d.name, 1, 0.5, 0.2 end
        return d.name
    end },
    { key = "avgLevel", title = "Niv.", width = 40, justify = "RIGHT", ascending = true, text = function(d) return d.level end },
    { key = "zone", title = "Zone", width = 120, ascending = true, text = function(d) return d.zone end },
    { key = "gold", title = "Or", width = 55, justify = "RIGHT", text = function(d) return ns.Money(d.gold) end },
    { key = "items", title = "Objets", width = 60, justify = "RIGHT", text = function(d) return ns.Money(d.items) end },
    { key = "skin", title = "Dépeçage", width = 60, justify = "RIGHT", text = function(d)
        return d.skinnable and ns.Money(d.skin) or ""
    end },
    { key = "total", title = "Total/kill", width = 70, justify = "RIGHT", text = function(d) return ns.Money(d.total), 1, 0.82, 0 end },
    { key = "spawns", title = "Appar.", width = 42, justify = "RIGHT", text = function(d) return tostring(d.spawns) end },
    { key = "observed", title = "Réel/kill", width = 70, justify = "RIGHT", text = function(d)
        if d.kills == 0 then return "" end
        return ns.Money(d.observed) .. " (" .. d.kills .. ")", 0.4, 1, 0.4
    end },
}

local function OnEnter(row, d)
    local GT = GameTooltip
    GT:SetOwner(row, "ANCHOR_RIGHT")
    GT:SetText(d.name .. (d.elite and " (élite)" or ""))
    GT:AddLine(("Niveau %s · %s · %d apparitions"):format(d.level, d.zone, d.spawns), 0.8, 0.8, 0.8)
    local v = ns.List.Detail(d)
    GT:AddDoubleLine("Or", ns.Money(v.gold), 1, 1, 1, 1, 1, 1)
    for i = 1, math.min(6, #v.detail.items) do
        local it = v.detail.items[i]
        GT:AddDoubleLine(("%s  %.1f %% × %s (%s)"):format(ItemName(it.id), it.expected * 100, ns.Money(it.value), it.source),
            ns.Money(it.part), 0.9, 0.9, 0.9, 1, 1, 1)
    end
    if v.shared > 0.5 then
        GT:AddDoubleLine("Butin aléatoire partagé (objets verts…)", ns.Money(v.shared), 0.6, 0.8, 1, 1, 1, 1)
    end
    if d.skinnable then
        if v.skin > 0 then
            for i = 1, math.min(3, #v.detail.skin) do
                local it = v.detail.skin[i]
                GT:AddDoubleLine(("Dépeçage : %s ×%.2f"):format(ItemName(it.id), it.expected), ns.Money(it.part), 0.8, 0.6, 0.3, 1, 1, 1)
            end
        else
            GT:AddLine(("Dépeçable à partir de %d en Dépeçage"):format(ns.Value.SkinReq(d.avgLevel)), 0.8, 0.6, 0.3)
        end
    end
    GT:AddDoubleLine("Estimation par kill", ns.Money(v.total), 1, 0.82, 0, 1, 0.82, 0)
    if d.kills > 0 then
        GT:AddDoubleLine(("Ton butin réel (%d kills)"):format(d.kills), ns.Money(d.observed), 0.4, 1, 0.4, 0.4, 1, 0.4)
    else
        GT:AddLine("Pas encore de butin enregistré sur ce monstre.", 0.6, 0.6, 0.6)
    end
    GT:AddLine("Estimation : taux de Classic (cmangos) ; Forever peut différer.", 0.5, 0.5, 0.5)
    GT:Show()
end

ns.UI.RegisterTab({
    name = "Farm",
    build = function(toolbar, content)
        local B = ns.UI.Button
        buttons.range = B(toolbar, 110, "", function()
            opts.range = opts.range % #ns.List.RANGES + 1
            ns.UI.RefreshAll()
        end, "Écart de niveau des monstres autour du tien")
        buttons.range:SetPoint("LEFT")
        buttons.elites = B(toolbar, 100, "", function()
            opts.elites = not opts.elites
            ns.UI.RefreshAll()
        end, "Inclure les élites (donjons, groupes)")
        buttons.elites:SetPoint("LEFT", buttons.range, "RIGHT", 4, 0)
        lv = ns.ListView.Create(content, {
            columns = COLUMNS, onEnter = OnEnter, sortKey = "total",
            tiebreak = function(a, b) return a.name < b.name end,
        })
    end,
    refresh = function()
        buttons.range:SetText(ns.List.RANGES[opts.range].label)
        buttons.elites:SetText(opts.elites and "Élites : oui" or "Élites : non")
        if not NpcDB then lastCount = 0 lv:SetRows({}) return end
        local rows, skinRank = ns.List.Build(opts)
        lastCount, lastSkin = #rows, skinRank
        lv:SetRows(rows)
    end,
    status = function()
        if not NpcDB then return "L'onglet Farm a besoin de QuestieDB (installé avec Questie)." end
        local t = ns.db.market.t
        return ("%d monstres · niveau %d · dépeçage %s · prix : %s"):format(lastCount, UnitLevel("player"),
            lastSkin and tostring(lastSkin) or "non",
            t and ("scan du " .. date("%d/%m %H:%M", t)) or (ns.Prices.HasAuctionator() and "Auctionator" or "marchand seulement"))
    end,
})
