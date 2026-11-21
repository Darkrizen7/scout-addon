-- Poids de stats par classe et rôle.
-- Valeurs de base : simulateur WoWSims (règles Classic de Forever), unités WoWSims
-- (toucher/crit par 1 %, puissance par point), converties en poids par point de stat d'objet.
local _, ns = ...
local Weights = {}
ns.Weights = Weights

-- Points de score par 1 % (les objets donnent des scores, pas des pourcentages).
local PER = { hit = 10, crit = 14, haste = 10, dodge = 12, parry = 15, block = 5, def = 1 }

local SPECS = {
    WARRIOR = {
        { key = "dps", label = "Guerrier DPS", w = { Strength = 2.51, Agility = 1.86, AttackPower = 1, MeleeHit = 28.67, MeleeCrit = 25.1, MainHandDps = 11.92, OffHandDps = 4.69 }, sta = 0.6 },
        { key = "tank", label = "Guerrier tank", w = { Armor = 0.174, Stamina = 2.336, Strength = 1.555, Agility = 2.771, AttackPower = 0.32, MeleeHit = 1.432, MeleeCrit = 0.925, Block = 1.32, BlockValue = 1.373, Dodge = 2.606, Parry = 2.649, Defense = 3.305, MainHandDps = 11.92 } },
    },
    PALADIN = {
        { key = "ret", label = "Paladin Vindicte", w = { Strength = 2.53, Agility = 1.13, Intellect = 0.15, SpellPower = 0.32, SpellHit = 0.41, MP5 = 0.05, AttackPower = 1, MeleeHit = 1.96, MeleeCrit = 1.16, MainHandDps = 7.33 }, sta = 0.6 },
        { key = "holy", label = "Paladin Sacré", w = { Intellect = 0.38, Spirit = 0.34, SpellPower = 1, SpellCrit = 0.69, SpellHaste = 0.77, MP5 = 0.6 }, sta = 0.15 },
        { key = "tank", label = "Paladin Protection", w = { Strength = 0.2, Agility = 1.1, Stamina = 0.7, SpellPower = 0.02, AttackPower = 0.06, Armor = 0.06, Defense = 1.8, BlockValue = 1.05, Dodge = 13, Parry = 13, MainHandDps = 0.6 } },
    },
    HUNTER = {
        -- Mesuré en jeu (/us test, niv 22) : 1 Agi = 2 PA à distance + 0,06 % crit ≈ 2,2 PA.
        -- 14 PA = 1 DPS, donc 1 DPS d'arc = 14 PA. Corps à corps peu utilisé → armes de mêlée faibles.
        { key = "dps", label = "Chasseur", w = { Strength = 0.1, Agility = 2.2, Intellect = 0.05, AttackPower = 1, RangedAttackPower = 1, MeleeHit = 3.29, MeleeCrit = 4.45, MP5 = 0.05, MainHandDps = 2, OffHandDps = 1.4, RangedDps = 14 }, sta = 0.3 },
    },
    ROGUE = {
        { key = "dps", label = "Voleur", w = { Agility = 2.38, Strength = 1.26, AttackPower = 1, MeleeHit = 29.44, MeleeCrit = 17.92, MainHandDps = 10.49, OffHandDps = 3.74 }, sta = 0.6 },
    },
    PRIEST = {
        { key = "heal", label = "Prêtre soins", w = { Intellect = 2.73, Spirit = 1.63, SpellPower = 1, SpellCrit = 0.75, SpellHaste = 0.28, MP5 = 2.05 }, sta = 0.3, wand = 1 },
        { key = "shadow", label = "Prêtre Ombre", w = { Intellect = 0.16, Spirit = 0.01, SpellPower = 1, SpellHit = 5.51, SpellCrit = 5.99, SpellHaste = 1.65 }, sta = 0.2, wand = 1 },
    },
    SHAMAN = {
        { key = "ele", label = "Chaman Élémentaire", w = { Intellect = 0.14, SpellPower = 1, SpellHit = 12.37, SpellCrit = 7.57, SpellHaste = 1.49, MP5 = 0.02 }, sta = 0.2 },
        { key = "enh", label = "Chaman Amélioration", w = { Intellect = 0.02, Agility = 1.12, Strength = 2.29, SpellPower = 1.15, SpellCrit = 1.94, AttackPower = 1, MeleeHit = 9.62, MeleeCrit = 14.8, MainHandDps = 8.15, OffHandDps = 5.81 }, sta = 0.6 },
        { key = "resto", label = "Chaman Restauration", w = { Intellect = 0.22, Spirit = 0.05, SpellPower = 1, SpellCrit = 0.67, SpellHaste = 1.29, MP5 = 0.08 }, sta = 0.15 },
    },
    MAGE = {
        { key = "dps", label = "Mage", w = { Intellect = 0.49, SpellPower = 1, SpellHit = 18.59, SpellCrit = 13.91, SpellHaste = 6.85, MP5 = 0.11 }, sta = 0.2, wand = 1 },
    },
    WARLOCK = {
        { key = "dps", label = "Démoniste", w = { Intellect = 0.23, MP5 = 0.14, SpellPower = 1, SpellHit = 12.79, SpellCrit = 7.92, SpellHaste = 7.83 }, sta = 0.25, wand = 1 },
    },
    DRUID = {
        { key = "balance", label = "Druide Équilibre", w = { Intellect = 0.16, SpellPower = 1, SpellHit = 11.75, SpellCrit = 7.5, SpellHaste = 0.8 }, sta = 0.2 },
        { key = "cat", label = "Druide Félin", w = { Strength = 2.4, Agility = 2.43, Intellect = 0.61, Spirit = 0.38, MP5 = 0.79, AttackPower = 1, FeralAttackPower = 1, MeleeHit = 26.59, MeleeCrit = 28.68 }, sta = 0.6 },
        { key = "bear", label = "Druide Ours", w = { Armor = 3.5665, Stamina = 7.3021, Strength = 2.3786, Agility = 4.4974, AttackPower = 1, FeralAttackPower = 1, MeleeHit = 2.9282, MeleeCrit = 1.5143, Defense = 1.8171, Dodge = 2.0196 } },
        { key = "resto", label = "Druide Restauration", w = { Intellect = 0.38, Spirit = 0.34, SpellPower = 1, SpellCrit = 0.69, SpellHaste = 0.77, MP5 = 0.3 }, sta = 0.15 },
    },
}

-- Onglet de talents le plus investi → rôle.
local TALENT_ROLE = {
    WARRIOR = { "dps", "dps", "tank" }, PALADIN = { "holy", "tank", "ret" },
    PRIEST = { "heal", "heal", "shadow" }, SHAMAN = { "ele", "enh", "resto" },
    DRUID = { "balance", "cat", "resto" },
}

-- Poids WoWSims → poids par point de stat (clés courtes utilisées par Stats.lua).
local function Convert(spec)
    local w = spec.w
    local function v(k) return w[k] or 0 end
    local hit, crit = v("MeleeHit") + v("SpellHit"), v("MeleeCrit") + v("SpellCrit")
    local out = {
        str = v("Strength"), agi = v("Agility"), sta = v("Stamina"), int = v("Intellect"), spi = v("Spirit"),
        sp = v("SpellPower"), ap = v("AttackPower"), rap = v("RangedAttackPower"), fap = v("FeralAttackPower"),
        hit = hit / PER.hit, crit = crit / PER.crit, haste = v("SpellHaste") / PER.haste, mp5 = v("MP5"),
        def = v("Defense") / PER.def, dodge = v("Dodge") / PER.dodge, parry = v("Parry") / PER.parry,
        block = v("Block") / PER.block, bv = v("BlockValue"), armor = v("Armor"),
        mh = v("MainHandDps"), oh = v("OffHandDps"), rd = v("RangedDps"),
    }
    -- Leveling : un peu d'endurance pour tout le monde.
    if out.sta == 0 then
        out.sta = (spec.sta or 0.3) * math.max(out.str, out.agi, out.int, out.sp, out.ap)
    end
    if out.rd == 0 and spec.wand then out.rd = spec.wand end
    return out
end

local function PlayerClass()
    local _, class = UnitClass("player")
    return class or "WARRIOR"
end

local function TalentRole(class)
    local map = TALENT_ROLE[class]
    if not (map and GetTalentTabInfo) then return nil end
    local best, bestTab = 0, nil
    for tab = 1, 3 do
        local r = { pcall(GetTalentTabInfo, tab) }
        if r[1] then
            -- Les retours varient selon les clients : premier nombre plausible = points dépensés.
            for i = 3, #r do
                local n = r[i]
                if type(n) == "number" and n >= 0 and n <= 61 then
                    if n > best then best, bestTab = n, tab end
                    break
                end
            end
        end
    end
    return bestTab and map[bestTab]
end

local function CurrentSpec()
    local class = PlayerClass()
    local list = SPECS[class] or SPECS.WARRIOR
    local want = ns.db.equip.roles[class] or TalentRole(class)
    for _, spec in ipairs(list) do
        if spec.key == want then return class, spec end
    end
    return class, list[1]
end

function Weights.CurrentKeys()
    local class, spec = CurrentSpec()
    return class, spec.key
end

-- { label, w = poids finaux (défauts + surcharges) }
function Weights.Current()
    local class, spec = CurrentSpec()
    local w = Convert(spec)
    local over = ns.db.equip.weights[class] and ns.db.equip.weights[class][spec.key]
    if over then
        for k, v in pairs(over) do w[k] = v end
    end
    return { label = spec.label, w = w }
end

function Weights.Command(stat, value)
    local cur = Weights.Current()
    if not stat then
        ns.Print("Poids — %s :", cur.label)
        local keys = {}
        for k, v in pairs(cur.w) do if v ~= 0 then keys[#keys + 1] = k end end
        table.sort(keys)
        for _, k in ipairs(keys) do ns.Print("  %s = %.3f", k, cur.w[k]) end
        return
    end
    value = tonumber(value)
    if cur.w[stat] == nil or not value then
        return ns.Print("Usage : /us poids <stat> <valeur> (stat parmi celles listées par /us poids)")
    end
    local class, role = Weights.CurrentKeys()
    ns.db.equip.weights[class] = ns.db.equip.weights[class] or {}
    ns.db.equip.weights[class][role] = ns.db.equip.weights[class][role] or {}
    ns.db.equip.weights[class][role][stat] = value
    ns.Print("%s : %s = %.3f", cur.label, stat, value)
end

function Weights.RoleCommand(key)
    local class = PlayerClass()
    local list = SPECS[class] or {}
    if key then
        if key == "auto" then
            ns.db.equip.roles[class] = nil
        else
            for _, spec in ipairs(list) do
                if spec.key == key then ns.db.equip.roles[class] = key end
            end
        end
    end
    ns.Print("Rôle actuel : %s", Weights.Current().label)
    local keys = {}
    for _, spec in ipairs(list) do keys[#keys + 1] = spec.key end
    ns.Print("Rôles : %s, auto", table.concat(keys, ", "))
end
