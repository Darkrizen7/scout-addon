-- Capture des recettes depuis la fenêtre de métier (C_TradeSkillUI, toutes recettes, apprises ou non).
local _, ns = ...
local Recipes = {}
ns.Recipes = Recipes

local MAX_TRIVIAL = 300   -- au-delà : recettes d'autres versions du jeu, absentes de Forever

local function OwnWindow()
    local T = C_TradeSkillUI
    if T.IsTradeSkillLinked and T.IsTradeSkillLinked() then return false end
    if T.IsTradeSkillGuild and T.IsTradeSkillGuild() then return false end
    if T.IsNPCCrafting and T.IsNPCCrafting() then return false end
    return true
end

local function Reagents(schematic)
    local list = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        local reagent = slot.reagents and slot.reagents[1]
        if slot.required ~= false and reagent and reagent.itemID then
            list[#list + 1] = { id = reagent.itemID, n = slot.quantityRequired or 1 }
        end
    end
    return list
end

function Recipes.Capture()
    local T = C_TradeSkillUI
    if not (T and T.GetAllRecipeIDs and T.GetBaseProfessionInfo) or not OwnWindow() then return end
    local prof = T.GetBaseProfessionInfo()
    local line = prof and prof.professionID
    if not line or line == 0 then return end
    ns.char.skills[line] = { name = prof.professionName, rank = prof.skillLevel, max = prof.maxSkillLevel }

    local store = ns.db.craft.recipes[line] or {}
    ns.db.craft.recipes[line] = store
    local known, diff = {}, {}
    local count, learned = 0, 0
    for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
        local info = T.GetRecipeInfo(id)
        if info and (info.maxTrivialLevel or 0) <= MAX_TRIVIAL and not info.isDummyRecipe then
            if not store[id] then
                local s = T.GetRecipeSchematic(id, false)
                if s and s.outputItemID then
                    store[id] = {
                        name = info.name, out = s.outputItemID, qty = s.quantityMin or 1,
                        reagents = Reagents(s), trivial = info.maxTrivialLevel,
                    }
                end
            end
            if store[id] then
                count = count + 1
                if info.learned then known[id] = true learned = learned + 1 end
                diff[id] = info.relativeDifficulty
            end
        end
    end
    -- Remplace la liste des recettes connues de ce métier pour ce personnage.
    for id in pairs(store) do ns.char.known[id] = known[id] end
    -- Couleur donnée par le jeu (chance de gagner un point), valable tant que le niveau ne bouge pas.
    ns.char.diff = ns.char.diff or {}
    ns.char.diff[line] = { rank = prof.skillLevel, ids = diff }
    ns.Log(("Recettes %s : %d (dont %d apprises), compétence %d/%d"):format(
        prof.professionName, count, learned, prof.skillLevel or 0, prof.maxSkillLevel or 0))
    if ns.UI then ns.UI.RefreshAll() end
end

local pending = false
local function Schedule()
    if pending then return end
    pending = true
    C_Timer.After(0.5, function() pending = false Recipes.Capture() end)
end

ns.On("TRADE_SKILL_SHOW", Schedule)
ns.On("TRADE_SKILL_LIST_UPDATE", Schedule)
