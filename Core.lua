-- Scout : cœur (namespace, base de données, journal, événements, commandes, utilitaires).
--
-- ScoutDB :
--   equip  = { lookahead, budget, bestOnly, weights, roles }      onglet Équipement
--   craft  = { recipes, trainer, patterns, chars }                 onglet Métiers
--   farm   = { obs, seen }                                         onglet Farm (butin observé)
--   market = { t, prices[itemID] = { p, q }, hist[itemID] = {...} } scan HdV partagé
--   vendor = { [itemID] = prix marchand }                          vu chez les marchands
--   ui     = { tab }
--   log    = journal de la session (lisible sur disque après /reload)
local ADDON, ns = ...

local LOG_MAX = 800
local log = {}

function ns.Log(msg)
    msg = tostring(msg):gsub("|cn.-:", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
    table.insert(log, date("%H:%M:%S ") .. msg)
    if #log > LOG_MAX then table.remove(log, 1) end
end

function ns.Print(fmt, ...)
    local msg = select("#", ...) > 0 and fmt:format(...) or fmt
    print("|cff33ff99Scout|r " .. msg)
    ns.Log(msg)
end

local previousHandler = geterrorhandler()
seterrorhandler(function(err, ...)
    ns.Log("ERREUR : " .. tostring(err))
    if debugstack then ns.Log(debugstack(2, 8, 0)) end
    return previousHandler(err, ...)
end)

function ns.Money(copper)
    if not copper then return "—" end
    if math.abs(copper) < 0.5 then return "0" end
    return GetMoneyString(math.floor(math.abs(copper) + 0.5), true)
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}

function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        frame:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event]) do fn(...) end
end)

---------------------------------------------------------------------------
-- Base de données
---------------------------------------------------------------------------
local DEFAULTS = {
    equip = { lookahead = 0, budget = 0, bestOnly = true, weights = {}, roles = {} },
    craft = { recipes = {}, trainer = {}, patterns = {}, chars = {} },
    farm = { obs = {}, seen = {} },
    market = { prices = {}, hist = {} },
    vendor = {},
    ui = { tab = 1 },
}

local function Fill(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            if type(v) == "table" then
                target[k] = {}
                Fill(target[k], v)
            else
                target[k] = v
            end
        elseif type(v) == "table" and type(target[k]) == "table" then
            Fill(target[k], v)
        end
    end
end

local inits = {}
function ns.OnInit(fn) table.insert(inits, fn) end

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    ScoutDB = ScoutDB or {}
    Fill(ScoutDB, DEFAULTS)
    ScoutDB.log = log
    ns.db = ScoutDB
    for _, fn in ipairs(inits) do fn() end
end)

---------------------------------------------------------------------------
-- Commandes /scout
---------------------------------------------------------------------------
local commands = {}
ns.commands = commands

local HELP = {
    "/scout — ouvre/ferme la fenêtre",
    "/scout scan — scanne l'HdV (HdV ouvert)",
    "/scout moi — score de l'équipement porté",
    "/scout poids [stat valeur] — poids des stats",
    "/scout role [clé|auto] — rôle pour les poids",
    "/scout test — Agilité / PA à distance / crit (écart depuis le dernier test)",
    "/scout reset — poids par défaut",
}

SLASH_SCOUT1 = "/scout"
SlashCmdList.SCOUT = function(msg)
    local cmd, a, b = strsplit(" ", strtrim(msg or ""):lower())
    if commands[cmd] then return commands[cmd](a, b) end
    for _, line in ipairs(HELP) do ns.Print(line) end
end
