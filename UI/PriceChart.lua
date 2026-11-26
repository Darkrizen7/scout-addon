-- Panneau de détail : courbe du prix d'un objet sur 30 jours (ScoutHistory, écrit par scout-rs).
local _, ns = ...
local PriceChart = {}
ns.PriceChart = PriceChart

local DAYS = 30
local W, H = 360, 250
local CX, CY, CW, CH = 70, -40, 270, 110 -- zone de la courbe (depuis le coin haut gauche du panneau)


-- Calcul pur : points { jour, prix } de la fenêtre, min, médiane, max (nil sans relevé).
function PriceChart.Compute(days, today)
    if not days then return nil end
    local list, sorted = {}, {}
    for d = today - DAYS + 1, today do
        if days[d] then
            list[#list + 1] = { d, days[d] }
            sorted[#sorted + 1] = days[d]
        end
    end
    local k = #sorted
    if k == 0 then return nil end
    table.sort(sorted)
    local med
    if k % 2 == 1 then med = sorted[(k + 1) / 2] else med = (sorted[k / 2] + sorted[k / 2 + 1]) / 2 end
    return list, sorted[1], math.floor(med), sorted[k]
end

-- Un « canevas » regroupe le cadre et les éléments dessinés (segments, points, textes).
local Canvas = {}
Canvas.__index = Canvas

function Canvas:Fs(key, point, x, y, justify)
    local f = self.texts[key]
    if not f then
        f = self.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        self.texts[key] = f
    end
    f:ClearAllPoints()
    f:SetPoint(point, self.frame, "TOPLEFT", x, y)
    f:SetJustifyH(justify or "LEFT")
    f:SetTextColor(1, 1, 1)
    f:Show()
    return f
end

function Canvas:Segment(i)
    if not self.segs[i] then
        local l = self.frame:CreateLine(nil, "ARTWORK")
        l:SetThickness(2)
        l:SetColorTexture(1, 0.82, 0.2, 1)
        self.segs[i] = l
    end
    return self.segs[i]
end

function Canvas:Dot(i)
    if not self.dots[i] then
        local t = self.frame:CreateTexture(nil, "ARTWORK")
        t:SetSize(3, 3)
        t:SetColorTexture(1, 0.82, 0.2, 1)
        self.dots[i] = t
    end
    return self.dots[i]
end

-- Crée un canevas dans `frame` (titre, repère du prix actuel, fond de la courbe).
local function NewCanvas(frame, titleY)
    local c = setmetatable({ frame = frame, segs = {}, dots = {}, texts = {} }, Canvas)
    c.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    c.title:SetPoint("TOP", 0, titleY)
    c.title:SetPoint("LEFT", 30, 0)
    c.title:SetPoint("RIGHT", -30, 0)
    c.title:SetWordWrap(false)
    c.current = frame:CreateLine(nil, "OVERLAY")
    c.current:SetThickness(1)
    c.current:SetColorTexture(0.4, 0.8, 1, 0.9)
    c.bg = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    c.bg:SetColorTexture(0, 0, 0, 0.35)
    c.bg:SetPoint("TOPLEFT", CX, CY)
    c.bg:SetSize(CW, CH)
    return c
end

function Canvas:HideAll()
    for _, s in ipairs(self.segs) do s:Hide() end
    for _, s in ipairs(self.dots) do s:Hide() end
    for _, f in pairs(self.texts) do f:Hide() end
    self.current:Hide()
    self.bg:Hide()
    self.title:SetText("")
end

-- Dessine la courbe 30 j de l'objet ; sans objet, le canevas reste vide.
function Canvas:Draw(itemID, name)
    self:HideAll()
    if not itemID then return end
    local frame = self.frame
    if not name then name = C_Item.GetItemInfo(itemID) end
    self.title:SetText(name or ("Objet " .. itemID))

    local today = ns.Prices.Today()
    local list, lo, med, hi = PriceChart.Compute(ns.Prices.Daily(itemID), today)
    local current = ns.Prices.AH(itemID)
    if not list then
        if current and current > 0 then
            self:Fs("last", "TOPLEFT", 20, -60):SetText("Dernier prix scanné : " .. ns.Money(current))
        end
        self:Fs("empty", "TOPLEFT", 20, -80):SetText("Pas d'historique : ouvre l'appli Scout pour l'envoyer")
        return
    end
    self.bg:Show()

    local top, bottom = hi, lo
    if top == bottom then top, bottom = hi * 1.1, lo * 0.9 end
    local function X(day) return CX + (day - (today - DAYS + 1)) / (DAYS - 1) * CW end
    local function Y(p) return CY - CH + (p - bottom) / (top - bottom) * CH end

    local nseg, ndot = 0, 0
    for i, pt in ipairs(list) do
        local prev, nxt = list[i - 1], list[i + 1]
        if nxt and nxt[1] == pt[1] + 1 then
            nseg = nseg + 1
            local l = self:Segment(nseg)
            -- ancrage au coin haut gauche : Y négatif vers le bas
            l:SetStartPoint("TOPLEFT", frame, X(pt[1]), Y(pt[2]))
            l:SetEndPoint("TOPLEFT", frame, X(nxt[1]), Y(nxt[2]))
            l:Show()
        end
        if not (prev and prev[1] == pt[1] - 1) and not (nxt and nxt[1] == pt[1] + 1) then
            ndot = ndot + 1
            local t = self:Dot(ndot)
            t:ClearAllPoints()
            t:SetPoint("CENTER", frame, "TOPLEFT", X(pt[1]), Y(pt[2]))
            t:Show()
        end
    end

    -- Repère du prix actuel, borné à la zone
    if current and current > 0 then
        local y = math.max(CY - CH, math.min(CY, Y(current)))
        self.current:SetStartPoint("TOPLEFT", frame, CX, y)
        self.current:SetEndPoint("TOPLEFT", frame, CX + CW, y)
        self.current:Show()
        local t = self:Fs("cur", "TOPLEFT", 14, CY - CH - 34)
        t:SetText("Actuel : " .. ns.Money(current))
        t:SetTextColor(0.4, 0.8, 1)
    end

    self:Fs("hi", "TOPRIGHT", CX - 4, CY - 2, "RIGHT"):SetText(ns.Money(hi))
    self:Fs("lo", "BOTTOMRIGHT", CX - 4, CY - CH + 2, "RIGHT"):SetText(ns.Money(lo))
    self:Fs("d1", "TOPLEFT", CX, CY - CH - 4):SetText(date("%d/%m", (today - DAYS + 1) * 86400 + 43200))
    self:Fs("d2", "TOPRIGHT", CX + CW, CY - CH - 4, "RIGHT"):SetText(date("%d/%m", today * 86400 + 43200))
    self:Fs("stats", "TOPLEFT", 14, CY - CH - 20):SetText(
        ("Min %s · Médiane %s · Max %s"):format(ns.Money(lo), ns.Money(med), ns.Money(hi)))
end

-- Canevas intégré à un cadre existant (onglet Objets) ; renvoie l'objet avec :Draw(itemID, name).
function PriceChart.Embed(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(W, H)
    return NewCanvas(f, -12), f
end

-- Panneau flottant collé à ScoutFrame (Maj-clic des onglets Équipement et Métiers).
local frame, canvas

local function Create()
    -- Enfant de ScoutFrame : se ferme avec elle.
    frame = CreateFrame("Frame", "ScoutPriceChart", ScoutFrame, "BasicFrameTemplateWithInset")
    frame:SetSize(W, H)
    frame:SetFrameStrata("HIGH")
    frame:Hide()
    tinsert(UISpecialFrames, "ScoutPriceChart")
    canvas = NewCanvas(frame, -5)
end

function PriceChart.Hide() if frame then frame:Hide() end end

function PriceChart.Show(itemID, name)
    if not itemID then return end
    if not frame then Create() end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", ScoutFrame, "TOPRIGHT", 0, 0)
    frame:Show()
    canvas:Draw(itemID, name)
end
