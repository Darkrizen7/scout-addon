-- Équipement porté, droit de port (règles Classic) et calcul du gain d'un objet.
local _, ns = ...
local Equipped = {}
ns.Equipped = Equipped

local ARMOR_CLASS, WEAPON_CLASS = 4, 2

-- Sous-classes d'armes utilisables par classe.
local WEAPONS = {
    WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }, PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
    HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }, ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
    PRIEST = { 4, 10, 15, 19 }, SHAMAN = { 0, 1, 4, 5, 10, 13, 15 }, MAGE = { 7, 10, 15, 19 },
    WARLOCK = { 7, 10, 15, 19 }, DRUID = { 4, 5, 10, 13, 15 },
}
-- Sous-classe d'armure → niveau à partir duquel la classe peut la porter.
-- 0 divers, 1 tissu, 2 cuir, 3 maille, 4 plaques, 6 bouclier, 7 libram, 8 idole, 9 totem.
local ARMOR = {
    WARRIOR = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
    PALADIN = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1, [7] = 1 },
    HUNTER = { [1] = 1, [2] = 1, [3] = 40 }, ROGUE = { [1] = 1, [2] = 1 }, PRIEST = { [1] = 1 },
    SHAMAN = { [1] = 1, [2] = 1, [3] = 40, [6] = 1, [9] = 1 }, MAGE = { [1] = 1 }, WARLOCK = { [1] = 1 },
    DRUID = { [1] = 1, [2] = 1, [8] = 1 },
}
local DUAL_WIELD = { WARRIOR = 20, ROGUE = 10, HUNTER = 20 }

-- Emplacement d'équipement → slot d'inventaire (et partie pour le DPS d'arme).
local SIMPLE = {
    INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_CHEST = 5, INVTYPE_ROBE = 5,
    INVTYPE_WAIST = 6, INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10,
    INVTYPE_CLOAK = 15,
}
local SLOT_NAMES = {
    [1] = "Tête", [2] = "Cou", [3] = "Épaules", [5] = "Torse", [6] = "Taille", [7] = "Jambes",
    [8] = "Pieds", [9] = "Poignets", [10] = "Mains", [11] = "Doigt", [12] = "Doigt", [13] = "Bijou",
    [14] = "Bijou", [15] = "Dos", [16] = "Main droite", [17] = "Main gauche", [18] = "Distance",
}
Equipped.SLOT_NAMES = SLOT_NAMES

local function PlayerClass()
    local _, class = UnitClass("player")
    return class
end

local function Contains(list, value)
    for _, v in ipairs(list or {}) do if v == value then return true end end
    return false
end

-- level : niveau auquel on veut porter l'objet (niveau actuel + anticipation).
function Equipped.CanUse(classID, subClassID, level)
    local class = PlayerClass()
    if classID == WEAPON_CLASS then return Contains(WEAPONS[class], subClassID) end
    if classID ~= ARMOR_CLASS then return false end
    if subClassID == 0 then return true end
    local from = ARMOR[class] and ARMOR[class][subClassID]
    return from ~= nil and level >= from
end

-- Vérification finale via l'infobulle du jeu : une ligne en rouge = objet non équipable
-- (compétence d'arme pas apprise, armure, classe…). Les lignes de niveau requis sont ignorées
-- si ignoreLevel est vrai (option « Niv. +N »).
local scanTip
local LEVEL_PATTERN = ITEM_MIN_LEVEL and "^" .. ITEM_MIN_LEVEL:gsub("%%d", "%%d+") .. "$"

local function IsRed(fs)
    if not (fs and fs:IsShown() and fs:GetText()) then return false end
    local r, g, b = fs:GetTextColor()
    return r > 0.9 and g < 0.2 and b < 0.2
end

function Equipped.IsUsableByTooltip(link, ignoreLevel)
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "ScoutEquipScanTip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetHyperlink(link)
    for i = 1, scanTip:NumLines() do
        local left = _G["ScoutEquipScanTipTextLeft" .. i]
        local right = _G["ScoutEquipScanTipTextRight" .. i]
        if IsRed(right) then return false end
        if IsRed(left) then
            local isLevel = LEVEL_PATTERN and left:GetText():match(LEVEL_PATTERN)
            if not (isLevel and ignoreLevel) then return false end
        end
    end
    return true
end

local function CanDualWield()
    local from = DUAL_WIELD[PlayerClass()]
    return from ~= nil and UnitLevel("player") >= from
end

---------------------------------------------------------------------------
-- Instantané de l'équipement porté (recalculé à chaque scan)
---------------------------------------------------------------------------
local worn = {}   -- [slot] = { stats, twoHand }

function Equipped.Refresh()
    wipe(worn)
    for slot in pairs(SLOT_NAMES) do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local _, _, _, loc = C_Item.GetItemInfoInstant(link)
            worn[slot] = { stats = ns.Stats.FromLink(link) or {}, twoHand = loc == "INVTYPE_2HWEAPON", link = link }
        end
    end
end

local function WornScore(slot, w, part)
    local item = worn[slot]
    return item and ns.Stats.Score(item.stats, w, part) or 0
end

-- Gain de l'objet vs l'équipement porté. Renvoie gain, slotLabel (ou nil si non comparable).
function Equipped.Gain(stats, loc, w)
    local slot = SIMPLE[loc]
    if slot then
        return ns.Stats.Score(stats, w, "main") - WornScore(slot, w, "main"), SLOT_NAMES[slot]
    end

    local mhTwoHand = worn[16] and worn[16].twoHand
    if loc == "INVTYPE_FINGER" or loc == "INVTYPE_TRINKET" then
        local a, b = (loc == "INVTYPE_FINGER") and 11 or 13, (loc == "INVTYPE_FINGER") and 12 or 14
        local weakest = math.min(WornScore(a, w, "main"), WornScore(b, w, "main"))
        return ns.Stats.Score(stats, w, "main") - weakest, SLOT_NAMES[a]
    elseif loc == "INVTYPE_2HWEAPON" then
        local current = WornScore(16, w, "main") + WornScore(17, w, "off")
        return ns.Stats.Score(stats, w, "main") - current, "Deux mains"
    elseif loc == "INVTYPE_WEAPON" or loc == "INVTYPE_WEAPONMAINHAND" then
        local best = ns.Stats.Score(stats, w, "main") - WornScore(16, w, "main")
        local label = SLOT_NAMES[16]
        if loc == "INVTYPE_WEAPON" and CanDualWield() and not mhTwoHand then
            local off = ns.Stats.Score(stats, w, "off") - WornScore(17, w, "off")
            if off > best then best, label = off, SLOT_NAMES[17] end
        end
        return best, label
    elseif loc == "INVTYPE_WEAPONOFFHAND" then
        if mhTwoHand or not CanDualWield() then return nil end
        return ns.Stats.Score(stats, w, "off") - WornScore(17, w, "off"), SLOT_NAMES[17]
    elseif loc == "INVTYPE_SHIELD" or loc == "INVTYPE_HOLDABLE" then
        if mhTwoHand then return nil end
        return ns.Stats.Score(stats, w, "main") - WornScore(17, w, "main"), SLOT_NAMES[17]
    elseif loc == "INVTYPE_RANGED" or loc == "INVTYPE_RANGEDRIGHT" or loc == "INVTYPE_THROWN"
        or loc == "INVTYPE_RELIC" then
        return ns.Stats.Score(stats, w, "ranged") - WornScore(18, w, "ranged"), SLOT_NAMES[18]
    end
    return nil
end

function Equipped.PrintSummary()
    Equipped.Refresh()
    local cur = ns.Weights.Current()
    ns.Print("Équipement porté — %s :", cur.label)
    local total = 0
    for slot = 1, 18 do
        local item = worn[slot]
        if item then
            local part = (slot == 18 and "ranged") or (slot == 17 and "off") or "main"
            local score = ns.Stats.Score(item.stats, cur.w, part)
            total = total + score
            ns.Print("  %s : %s  %.1f", SLOT_NAMES[slot], item.link, score)
        end
    end
    ns.Print("Total : %.1f", total)
end
