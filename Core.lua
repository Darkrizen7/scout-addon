-- Scout : cœur (namespace, base de données, journal, événements, commandes, utilitaires).
--
-- ScoutDB :
--   equip  = { lookahead, budget, bestOnly, weights, roles }      onglet Équipement
--   craft  = { recipes, trainer, patterns, chars }                 onglet Métiers
--   farm   = { obs, seen }                                         butin observé, exporté vers scout-rs (format dans Farm/Observed.lua)
--   market = { t, n, prices[itemID] = { p, q }, hist[itemID] = {...}, names[itemID] } scan HdV partagé
--            (n / nq, t / tq = objets vus et heure du dernier scan complet / rapide,
--             names = nom de tout objet vu, class / classNames / subclassNames = sa catégorie)
--   vendor = { [itemID] = prix marchand }                          vu chez les marchands
--   merchants = { [npcID] = { name, zone, x, y, t, items = { [itemID] = { p = prix unitaire, l = stock limité } } } }
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
    market = { prices = {}, hist = {}, names = {}, class = {}, classNames = {}, subclassNames = {} },
    vendor = {},
    merchants = {},
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

-- Valeurs « secrètes » (client moderne, en instance notamment) : un addon ne peut ni les lire ni les découper.
local issecret = issecretvalue or function() return false end
function ns.IsSecret(v) return v ~= nil and issecret(v) end

-- Numéro de PNJ tiré d'un GUID « Creature-0-…-<npcID>-… » ; nil si ce n'est pas un PNJ ou si le GUID est secret.
function ns.NpcID(guid)
    if type(guid) ~= "string" or issecret(guid) then return nil end
    local ok, kind, _, _, _, _, id = pcall(strsplit, "-", guid)
    if ok and kind == "Creature" then return tonumber(id) end
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
    "/scout scan rapide — scanne seulement l'artisanat (plus court)",
    "/scout moi — score de l'équipement porté",
    "/scout poids [stat valeur] — poids des stats",
    "/scout role [clé|auto] — rôle pour les poids",
    "/scout test — Agilité / PA à distance / crit (écart depuis le dernier test)",
    "/scout reset — poids par défaut",
    "/way #<n° de carte> <x> <y> [nom] — point sur la carte (copié depuis scout-rs)",
}

SLASH_SCOUT1 = "/scout"
SlashCmdList.SCOUT = function(msg)
    local cmd, a, b = strsplit(" ", strtrim(msg or ""):lower())
    if commands[cmd] then return commands[cmd](a, b) end
    for _, line in ipairs(HELP) do ns.Print(line) end
end

---------------------------------------------------------------------------
-- Point sur la carte : « /way #1431 25.1 38.2 Nom » (n° de carte UiMap, coordonnées en %),
-- la syntaxe de TomTom, copiée depuis scout-rs. Si TomTom est installé, c'est sa commande qui sert.
---------------------------------------------------------------------------
local pendingWay

function ns.SetWaypoint(msg)
    local map, x, y, label = strtrim(msg or ""):match("^#?(%d+)%s+([%d%.,]+)%s+([%d%.,]+)%s*(.*)$")
    map = tonumber(map)
    x = x and tonumber((x:gsub(",", ".")))
    y = y and tonumber((y:gsub(",", ".")))
    if not (map and x and y) then
        return ns.Print("Usage : /way #<n° de carte> <x> <y> [nom]")
    end
    if InCombatLockdown() then
        pendingWay = msg
        return ns.Print("Point posé à la fin du combat.")
    end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(map) then
        return ns.Print(("Impossible de mettre un point sur la carte %d."):format(map))
    end
    local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
    if not ok then return ns.Print("Le jeu a refusé le point.") end
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    local info = C_Map.GetMapInfo(map)
    ns.Print(("Point : %s%s (%.1f, %.1f)"):format(label ~= "" and label .. " — " or "",
        info and info.name or tostring(map), x, y))
end

ns.On("PLAYER_REGEN_ENABLED", function()
    if pendingWay then
        local msg = pendingWay
        pendingWay = nil
        ns.SetWaypoint(msg)
    end
end)

-- Enregistrée à la connexion, quand on sait si TomTom (chargé après Scout) a déjà sa commande /way.
ns.On("PLAYER_LOGIN", function()
    if SlashCmdList.TOMTOM_WAY then return end
    SLASH_SCOUTWAY1 = "/way"
    SlashCmdList.SCOUTWAY = ns.SetWaypoint
end)
