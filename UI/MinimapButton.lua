-- Bouton de minimap (ramassé par MinimapButtonButton grâce à son nom) + menu des addons de la minimap.
local _, ns = ...

local RADIUS = 105   -- distance au centre de la minimap

local function Tooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText("Scout")
    GameTooltip:AddLine("Clic : ouvrir / fermer", 1, 1, 1)
    GameTooltip:AddLine("Glisser : déplacer le bouton", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function Place(button)
    local angle = math.rad(ns.db.ui.minimapAngle or 210)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
end

local function OnDragUpdate(button)
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    ns.db.ui.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
    Place(button)
end

ns.OnInit(function()
    local b = CreateFrame("Button", "ScoutMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_02")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -5)
    b.icon = icon
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function() ns.UI.Toggle() end)
    b:SetScript("OnEnter", Tooltip)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    Place(b)
end)

-- Menu des addons de la minimap (## AddonCompartmentFunc dans le .toc).
function Scout_Compartment() ns.UI.Toggle() end
function Scout_CompartmentEnter(_, button) Tooltip(button) end
Scout_CompartmentLeave = GameTooltip_Hide
