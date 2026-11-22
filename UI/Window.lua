-- Fenêtre principale à onglets. Se colle à droite de l'HdV quand il s'ouvre ; /scout ailleurs.
local _, ns = ...
local UI = {}
ns.UI = UI

local tabs = {}        -- { name, build(toolbar, content), refresh(), status() }
local frame, current, scanButton, quickButton, ticker
local autoShown = false
local RECENT_SCAN = 20 * 60   -- un scan plus récent que ça : bouton vert

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

-- Bouton de scan : orange pendant le scan, vert si le dernier scan date de moins de 20 min.
local function TintButton(b, r, g, bl)
    for _, key in ipairs({ "Left", "Middle", "Right" }) do
        if b[key] then b[key]:SetVertexColor(r, g, bl) end
    end
end

local function PaintScanButton(b, running, last, label, done)
    local age = last and time() - last
    if running then
        TintButton(b, 1, 0.65, 0.2)
        b:SetText("|cffffd27fEn cours…|r")
    elseif age and age < RECENT_SCAN then
        TintButton(b, 0.35, 1, 0.35)
        b:SetText(("|cff9cff9c%s (%d min)|r"):format(done, math.floor(age / 60)))
    else
        TintButton(b, 1, 1, 1)
        b:SetText(label)
    end
end

local function UpdateScanButton()
    if not (scanButton and quickButton) then return end
    local m, running, isQuick = ns.db.market, ns.Scan.IsRunning(), ns.Scan.IsQuick()
    PaintScanButton(scanButton, running and not isQuick, m.t, "Scanner l'HdV", "Scanné")
    -- Un scan complet couvre aussi l'artisanat.
    PaintScanButton(quickButton, running and isQuick, math.max(m.t or 0, m.tq or 0), "Rapide", "Rapide")
end
UI.UpdateScanButton = UpdateScanButton

-- L'âge du dernier scan avance tout seul : mise à jour du bouton tant que la fenêtre est ouverte.
local function StartTicker()
    if not ticker then ticker = C_Timer.NewTicker(15, UpdateScanButton) end
end

function UI.RefreshAll()
    UpdateScanButton()
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
    frame:SetScript("OnShow", function()
        UI.RefreshAll()
        StartTicker()
    end)
    frame:SetScript("OnHide", function()
        if ticker then ticker:Cancel() ticker = nil end
    end)
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
    scanButton = Button(frame, 130, "Scanner l'HdV", function() ns.Scan.Start() end,
        "Lit tout l'HdV (HdV ouvert) : prix, quantités, patrons, améliorations d'équipement.\n"
        .. "Orange : scan en cours. Vert : dernier scan il y a moins de 20 minutes.")
    scanButton:SetPoint("TOPRIGHT", -12, -28)
    quickButton = Button(frame, 100, "Rapide", function() ns.Scan.Start("rapide") end,
        "Scan rapide : seulement l'artisanat (composants, recettes, consommables, réactifs, gemmes).\n"
        .. "Bien plus court, sans analyse d'équipement ; les autres prix restent ceux du dernier scan complet.\n"
        .. "Orange : en cours. Vert : scan (rapide ou complet) il y a moins de 20 minutes.")
    quickButton:SetPoint("RIGHT", scanButton, "LEFT", -4, 0)

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("TOPLEFT", 12, -82)
    frame.status:SetPoint("RIGHT", -12, 0)
    frame.status:SetJustifyH("LEFT")

    Select(ns.db.ui.tab or 1)
    StartTicker()   -- la fenêtre vient d'être créée visible : OnShow ne s'est pas déclenché
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
