-- Lecture des stats d'un objet et calcul du score pondéré.
local _, ns = ...
local Stats = {}
ns.Stats = Stats

-- Clés renvoyées par GetItemStats → clés courtes des poids (Weights.lua).
local MOD = {
    ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STAMINA_SHORT = "sta",
    ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi",
    ITEM_MOD_ATTACK_POWER_SHORT = "ap", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap",
    ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "fap",
    ITEM_MOD_SPELL_POWER_SHORT = "sp", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "sp", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "sp",
    ITEM_MOD_HIT_RATING_SHORT = "hit", ITEM_MOD_HIT_MELEE_RATING_SHORT = "hit",
    ITEM_MOD_HIT_RANGED_RATING_SHORT = "hit", ITEM_MOD_HIT_SPELL_RATING_SHORT = "hit",
    ITEM_MOD_CRIT_RATING_SHORT = "crit", ITEM_MOD_CRIT_MELEE_RATING_SHORT = "crit",
    ITEM_MOD_CRIT_RANGED_RATING_SHORT = "crit", ITEM_MOD_CRIT_SPELL_RATING_SHORT = "crit",
    ITEM_MOD_HASTE_RATING_SHORT = "haste", ITEM_MOD_HASTE_SPELL_RATING_SHORT = "haste",
    ITEM_MOD_MANA_REGENERATION_SHORT = "mp5",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "def", ITEM_MOD_DODGE_RATING_SHORT = "dodge",
    ITEM_MOD_PARRY_RATING_SHORT = "parry", ITEM_MOD_BLOCK_RATING_SHORT = "block",
    ITEM_MOD_BLOCK_VALUE_SHORT = "bv",
    RESISTANCE0_NAME = "armor",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps",
}

local GetItemStats = (C_Item and C_Item.GetItemStats) or GetItemStats

-- Renvoie { clé = valeur } ou nil si le client n'a pas (encore) l'info.
function Stats.FromLink(link)
    if type(link) ~= "string" then return nil end
    local ok, raw = pcall(GetItemStats, link)
    if not ok or type(raw) ~= "table" then return nil end
    local out, any = {}, false
    for k, v in pairs(raw) do
        local key = MOD[k]
        if key and type(v) == "number" then
            out[key] = (out[key] or 0) + v
            any = true
        end
    end
    return any and out or nil
end

-- part : "main" (main droite / pièce d'armure), "off" (main gauche) ou "ranged".
function Stats.Score(stats, w, part)
    if not stats then return 0 end
    local score = 0
    for k, v in pairs(stats) do
        if k ~= "dps" then score = score + (w[k] or 0) * v end
    end
    if stats.dps then
        local dw = (part == "ranged" and w.rd) or (part == "off" and w.oh) or w.mh
        score = score + (dw or 0) * stats.dps
    end
    return score
end
