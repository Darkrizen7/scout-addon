-- Fusionne les SavedVariables d'UpgradeScout, CraftScout et FarmScout dans ScoutDB.
-- Usage : lua tools/migrate.lua <dossier SavedVariables>
-- N'écrase jamais un Scout.lua existant.
local dir = assert(arg[1], "usage : lua tools/migrate.lua <dossier SavedVariables>")

local function exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

local out = dir .. "/Scout.lua"
assert(not exists(out), "Scout.lua existe déjà : rien à faire")

local function loadSV(name)
    local path = dir .. "/" .. name .. ".lua"
    if not exists(path) then return end
    local env = {}
    assert(loadfile(path, "t", env))()
    return env
end

local up = (loadSV("UpgradeScout") or {}).UpgradeScoutDB or {}
local craft = (loadSV("CraftScout") or {}).CraftScoutDB or {}
local farm = (loadSV("FarmScout") or {}).FarmScoutDB or {}

local db = {
    equip = { lookahead = up.lookahead, budget = up.budget, bestOnly = up.bestOnly, weights = up.weights, roles = up.roles },
    craft = { recipes = craft.recipes, trainer = craft.trainer, patterns = craft.patterns, chars = craft.chars },
    vendor = craft.vendor,
    market = craft.market,
    farm = { obs = farm.obs, seen = farm.seen },
    ui = { tab = 1 },
}

local function serialize(v, indent, buf)
    local t = type(v)
    if t == "string" then buf[#buf + 1] = string.format("%q", v)
    elseif t == "number" or t == "boolean" then buf[#buf + 1] = tostring(v)
    elseif t == "table" then
        buf[#buf + 1] = "{\n"
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then return a < b end
            return type(a) == "number"
        end)
        for _, k in ipairs(keys) do
            buf[#buf + 1] = indent .. "\t["
            serialize(k, "", buf)
            buf[#buf + 1] = "] = "
            serialize(v[k], indent .. "\t", buf)
            buf[#buf + 1] = ",\n"
        end
        buf[#buf + 1] = indent .. "}"
    else
        buf[#buf + 1] = "nil"
    end
end

local buf = { "\nScoutDB = " }
serialize(db, "", buf)
buf[#buf + 1] = "\n"
local f = assert(io.open(out, "w"))
f:write(table.concat(buf))
f:close()

local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
local recipes = 0
for _, r in pairs(craft.recipes or {}) do recipes = recipes + count(r) end
print(("Migré : %d recettes, %d patrons, %d prix marchands, %d prix HdV, %d monstres observés, poids %s"):format(
    recipes, count(craft.patterns), count(craft.vendor), count(craft.market and craft.market.prices),
    count(farm.obs), up.weights and "oui" or "non"))
