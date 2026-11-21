-- Fenêtre principale à onglets. Se colle à droite de l'HdV quand il s'ouvre ; /scout ailleurs.
local _, ns = ...
local UI = {}
ns.UI = UI

local tabs = {}        -- { name, build(toolbar, content), refresh(), status() }
local frame, current
local autoShown = false

function UI.RegisterTab(tab) table.insert(tabs, tab) end

local function Button(parent, width, text, onClick, tip)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    if tip then
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tip, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
    end
    return b
end
UI.Button = Button

function UI.SetStatus(text)
    if frame then frame.status:SetText(text) end
end

local function Select(index)
    current = tabs[index] and index or 1
    ns.db.ui.tab = current
    for i, tab in ipairs(tabs) do
        tab.toolbar:SetShown(i == current)
        tab.content:SetShown(i == current)
        tab.button:SetEnabled(i ~= current)   -- onglet actif = bouton grisé
    end
    UI.RefreshAll()
end

function UI.RefreshAll()
    if not (frame and frame:IsShown()) then return end
    local tab = tabs[current]
    tab.refresh()
    if not ns.Scan.IsRunning() and tab.status then UI.SetStatus(tab.status()) end
end

local function Create()
    frame = CreateFrame("Frame", "ScoutFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(760, 520)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnShow", UI.RefreshAll)
    tinsert(UISpecialFrames, "ScoutFrame")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
    title:SetText("Scout")

    local x = 10
    for i, tab in ipairs(tabs) do
        tab.button = Button(frame, 110, tab.name, function() Select(i) end)
        tab.button:SetPoint("TOPLEFT", x, -28)
        x = x + 114
        tab.toolbar = CreateFrame("Frame", nil, frame)
        tab.toolbar:SetPoint("TOPLEFT", 10, -54)
        tab.toolbar:SetSize(560, 22)
        tab.content = CreateFrame("Frame", nil, frame)
        tab.content:SetPoint("TOPLEFT", 10, -100)
        tab.content:SetPoint("BOTTOMRIGHT", -12, 10)
        tab.build(tab.toolbar, tab.content)
    end
    local scan = Button(frame, 120, "Scanner l'HdV", function() ns.Scan.Start() end,
        "Lit tout l'HdV (HdV ouvert) : prix, quantités, patrons, améliorations d'équipement.\n"
        .. "Un scan par session construit l'historique des quantités.")
    scan:SetPoint("TOPRIGHT", -12, -28)

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("TOPLEFT", 12, -82)
    frame.status:SetPoint("RIGHT", -12, 0)
    frame.status:SetJustifyH("LEFT")

    Select(ns.db.ui.tab or 1)
end

function UI.Toggle()
    if not frame then Create() return end
    autoShown = false
    frame:SetShown(not frame:IsShown())
end

-- Collée à l'HdV quand il s'ouvre, remise au centre (ou fermée) quand il se ferme.
ns.On("AUCTION_HOUSE_SHOW", function()
    if not frame then Create() end
    if not frame:IsShown() then autoShown = true end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0)
    frame:Show()
end)
ns.On("AUCTION_HOUSE_CLOSED", function()
    if not frame then return end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER")
    if autoShown then frame:Hide() end
    autoShown = false
end)

-- Noms d'objets reçus du serveur : rafraîchissement groupé (au plus une fois par seconde).
local queued = false
ns.On("GET_ITEM_INFO_RECEIVED", function()
    if queued or not (frame and frame:IsShown()) then return end
    queued = true
    C_Timer.After(1, function() queued = false UI.RefreshAll() end)
end)

ns.commands[""] = UI.Toggle
