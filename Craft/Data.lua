-- Schéma de la base et petits utilitaires partagés.
--
-- Données de l'onglet Métiers (ns.db.craft, compte) :
--   ns.db.craft.recipes[skillLine][recipeID] = { name, out, qty, reagents = { {id, n}, ... }, trivial }
--   trainer[skillLine][outItemID] = { cost, req, name }     (vu chez un maître)
--   patterns[itemID] = { name, req }                        (patron vu chez un marchand ou à l'HdV)
--   vendor[itemID] = prix unitaire en cuivre                 (vu chez un marchand)
--   market = { t = date du scan, prices[itemID] = { p, q }, hist[itemID] = { {d, p, q}, ... } }
--   chars[clé] = { skills[skillLine] = { name, rank, max }, known[recipeID] = true,
--                 diff[skillLine] = { rank, ids[recipeID] = Enum.TradeskillRelativeDifficulty } }
local _, ns = ...
local Data = {}
ns.Data = Data
ns.Craft = ns.Craft or {}

ns.OnInit(function()
    local key = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
    local chars = ns.db.craft.chars
    chars[key] = chars[key] or { skills = {}, known = {} }
    ns.char = chars[key]
end)

function Data.ItemID(link)
    return link and tonumber(link:match("item:(%d+)"))
end

-- Retire le préfixe « Patron : » / « Recette : » … d'un nom de patron.
function Data.PatternTarget(name)
    local target = name and name:match("^[^:]+:%s*(.+)$")
    return target and strtrim(target, " \t\194\160\226\128\175")
end

-- Niveau de métier requis lu dans une infobulle : « Requires Tailoring (255) » en anglais,
-- « Couture (255) requis » en français. Le motif vient du texte du client (ITEM_REQ_SKILL), pour tout ordre
-- des mots ; les deux formes connues servent de repli.
local TOOLTIP_INFO = { SetItemByID = "GetItemByID", SetMerchantItem = "GetMerchantItem" }
local scanTip
local loggedMisses = 0

local function FormatToPattern(fmt)
    local p = fmt:gsub("%%%d?%$?s", "\1"):gsub("%%%d?%$?d", "\2")
    p = p:gsub("([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1")
    return "^" .. p:gsub("\1", "(.-)"):gsub("\2", "(%%d+)") .. "$"
end
Data.FormatToPattern = FormatToPattern

local REQ_PATTERNS = { "^Requires (.+)$", "^Requiert (.+)$", "^(.-) requis$" }
if type(ITEM_REQ_SKILL) == "string" then table.insert(REQ_PATTERNS, 1, FormatToPattern(ITEM_REQ_SKILL)) end

local function MatchReq(text)
    if type(text) ~= "string" then return nil end
    text = strtrim(text)
    for _, pattern in ipairs(REQ_PATTERNS) do
        local a, b = text:match(pattern)
        if a then
            local skill, level = a, b
            if not tonumber(level) then skill, level = a:match("^(.-)%s*%((%d+)%)$") end
            if tonumber(level) then return tonumber(level), skill end
        end
    end
end
Data.MatchReq = MatchReq

local function TooltipLines(setter, ...)
    local lines = {}
    local api = C_TooltipInfo and C_TooltipInfo[TOOLTIP_INFO[setter] or ""]
    local data = api and api(...)
    if data and data.lines then
        for _, line in ipairs(data.lines) do lines[#lines + 1] = line.leftText end
        return lines
    end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "ScoutCraftScanTip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip[setter](scanTip, ...)
    for i = 1, scanTip:NumLines() do
        local fs = _G["ScoutCraftScanTipTextLeft" .. i]
        lines[#lines + 1] = fs and fs:GetText()
    end
    return lines
end

function Data.TooltipSkillReq(setter, ...)
    local lines = TooltipLines(setter, ...)
    for _, text in ipairs(lines) do
        local level, skill = MatchReq(text)
        if level then return level, skill end
    end
    if loggedMisses < 3 then   -- aide au diagnostic : contenu d'une infobulle sans niveau trouvé
        loggedMisses = loggedMisses + 1
        ns.Log("Niveau requis introuvable dans : " .. table.concat(lines, " / "))
    end
end

-- Professions du personnage (lisibles partout).
function Data.RefreshSkills()
    if not (GetProfessions and GetProfessionInfo) then return end
    for _, idx in ipairs({ GetProfessions() }) do
        if type(idx) == "number" then
            local name, _, rank, max, _, _, skillLine = GetProfessionInfo(idx)
            if skillLine then ns.char.skills[skillLine] = { name = name, rank = rank, max = max } end
        end
    end
end

function Data.SkillLineByName(name)
    for line, s in pairs(ns.char.skills) do
        if s.name == name then return line end
    end
end

ns.On("PLAYER_LOGIN", function() Data.RefreshSkills() end)
ns.On("SKILL_LINES_CHANGED", function() if ns.char then Data.RefreshSkills() end end)
