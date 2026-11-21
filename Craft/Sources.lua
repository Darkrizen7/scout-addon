-- Où s'apprennent les recettes : maître (coût + niveau requis), patrons chez les marchands,
-- et prix marchands des composants. Tout est enregistré quand tu ouvres ces fenêtres.
local _, ns = ...
local Sources = {}
ns.Sources = Sources

local RECIPE_CLASS = Enum.ItemClass and Enum.ItemClass.Recipe or 9
local TRAINER_TYPES = { "available", "unavailable", "used" }

---------------------------------------------------------------------------
-- Maître
---------------------------------------------------------------------------
local function CaptureTrainer()
    local saved = {}
    for _, t in ipairs(TRAINER_TYPES) do
        saved[t] = GetTrainerServiceTypeFilter(t)
        SetTrainerServiceTypeFilter(t, true)
    end
    local n, recorded = GetNumTrainerServices(), 0
    for i = 1, n do
        local name = GetTrainerServiceInfo(i)
        local skillName, req = GetTrainerServiceSkillReq(i)
        local out = ns.Data.ItemID(GetTrainerServiceItemLink(i))
        local line = skillName and ns.Data.SkillLineByName(skillName)
        if line and out then
            ns.db.craft.trainer[line] = ns.db.craft.trainer[line] or {}
            ns.db.craft.trainer[line][out] = { cost = GetTrainerServiceCost(i), req = req, name = name }
            recorded = recorded + 1
        end
    end
    for _, t in ipairs(TRAINER_TYPES) do
        if saved[t] ~= nil then SetTrainerServiceTypeFilter(t, saved[t] and true or false) end
    end
    ns.Log(("Maître : %d recettes enregistrées"):format(recorded))
    if ns.UI then ns.UI.RefreshAll() end
end

---------------------------------------------------------------------------
-- Patrons
---------------------------------------------------------------------------
-- Enregistre un patron (si c'est bien un objet « recette ») : nom de la recette visée + niveau requis.
function Sources.RecordPattern(itemID, tooltipSetter, ...)
    Sources.Invalidate()
    local name, _, _, _, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(itemID)
    if not name then
        C_Item.RequestLoadItemDataByID(itemID)   -- sera enregistré au prochain passage
        return
    end
    if classID ~= RECIPE_CLASS then return end
    local p = ns.db.craft.patterns[itemID]
    if p and p.req then return end
    local req = ns.Data.TooltipSkillReq(tooltipSetter, ...)
    ns.db.craft.patterns[itemID] = { name = ns.Data.PatternTarget(name), req = req }
end

ns.On("TRAINER_SHOW", function() C_Timer.After(0.3, CaptureTrainer) end)

---------------------------------------------------------------------------
-- Comment apprendre une recette : { kind = "maître"|"marchand"|"HdV", cost, req } ou nil.
---------------------------------------------------------------------------
local patternIndex   -- [nom de recette] = { itemID, ... }, reconstruit à la demande

function Sources.Invalidate() patternIndex = nil end

local function PatternsFor(recipeName)
    if not patternIndex then
        patternIndex = {}
        for id, p in pairs(ns.db.craft.patterns) do
            if p.name then
                local key = p.name:lower()
                patternIndex[key] = patternIndex[key] or {}
                table.insert(patternIndex[key], id)
            end
        end
    end
    return patternIndex[recipeName:lower()] or {}
end

function Sources.Learn(line, recipe)
    local best
    local t = ns.db.craft.trainer[line] and ns.db.craft.trainer[line][recipe.out]
    if t then best = { kind = "maître", cost = t.cost or 0, req = t.req } end
    for _, id in ipairs(PatternsFor(recipe.name)) do
        local p = ns.db.craft.patterns[id]
        if not p.req and C_Item.GetItemInfo(id) then   -- niveau pas encore lu : on réessaie
            p.req = ns.Data.TooltipSkillReq("SetItemByID", id)
        end
        local vendor = ns.db.vendor[id]
        local ah = ns.Prices.AH(id)
        local cost, kind = vendor, "marchand"
        if ah and (not cost or ah < cost) then cost, kind = ah, "HdV" end
        if cost and (not best or cost < best.cost) then
            best = { kind = kind, cost = cost, req = p.req, pattern = id }
        end
    end
    return best
end

ns.Craft = ns.Craft or {}
ns.Craft.RecordPattern = Sources.RecordPattern
