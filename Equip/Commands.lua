-- Commandes de l'onglet Équipement (/scout moi, poids, role, test, reset, debug).
local _, ns = ...
local commands = ns.commands

function commands.moi() ns.Equipped.PrintSummary() end
function commands.poids(stat, value) ns.Weights.Command(stat, value) end
function commands.role(key) ns.Weights.RoleCommand(key) end

-- Mesure Agilité / PA à distance / crit et l'écart avec la mesure précédente :
-- /scout test, changer une pièce, /scout test → combien de PA vaut 1 Agilité.
local lastTest
function commands.test()
    local _, agi = UnitStat("player", 2)
    local base, pos, neg = UnitRangedAttackPower("player")
    local rap = base + pos + neg
    local crit = GetRangedCritChance and GetRangedCritChance() or 0
    ns.Print("Agilité %d · PA à distance %d · crit distance %.2f %%", agi, rap, crit)
    if lastTest then
        local dAgi, dRap, dCrit = agi - lastTest.agi, rap - lastTest.rap, crit - lastTest.crit
        ns.Print("Écart : Agilité %+d · PA à distance %+d · crit %+.2f %%", dAgi, dRap, dCrit)
        if dAgi ~= 0 then
            ns.Print("→ 1 Agilité = %.2f PA à distance et %.3f %% de crit", dRap / dAgi, dCrit / dAgi)
        end
    end
    lastTest = { agi = agi, rap = rap, crit = crit }
end

function commands.reset()
    local class, role = ns.Weights.CurrentKeys()
    local weights = ns.db.equip.weights
    if weights[class] then weights[class][role] = nil end
    ns.Print("Poids remis par défaut pour %s.", ns.Weights.Current().label)
end

function commands.debug(id)
    id = tonumber(id)
    if not id then return ns.Print("Usage : /scout debug <itemID>") end
    local stats = ns.Stats.FromLink("item:" .. id)
    if not stats then return ns.Print("Pas de stats (objet pas encore en cache ? réessaie).") end
    for k, v in pairs(stats) do ns.Print("  %s = %s", k, v) end
    ns.Print("Score : %.1f", ns.Stats.Score(stats, ns.Weights.Current().w, "main"))
end
