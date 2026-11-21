-- Liste générique : en-têtes triables + ScrollBox qui garde sa position de défilement.
--
-- spec = {
--   columns = { { key, title, width, justify, text = function(d) return texte, r, g, b end, ascending = bool }, ... },
--   icon = function(d) return texture end,   -- optionnel, avant la 1re colonne
--   onEnter = function(row, d), onClick = function(row, d),
--   sortKey, sortDesc, tiebreak = function(a, b) return bool end,
-- }
local _, ns = ...
local ListView = {}
ns.ListView = ListView

local ROW_HEIGHT = 20
local HEADER_HEIGHT = 18

local function Compare(lv)
    local key, desc, tiebreak = lv.sortKey, lv.sortDesc, lv.spec.tiebreak
    return function(a, b)
        local x, y = a[key], b[key]
        if x == nil and y == nil or x == y then
            if tiebreak then return tiebreak(a, b) end
            return false
        end
        if x == nil then return false end
        if y == nil then return true end
        if desc then return x > y end
        return x < y
    end
end

local function InitRow(lv, row, d)
    local spec = lv.spec
    if not row.cells then
        row:SetHeight(ROW_HEIGHT)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        local x = 4
        if spec.icon then
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(ROW_HEIGHT - 2, ROW_HEIGHT - 2)
            row.icon:SetPoint("LEFT", 2, 0)
            x = ROW_HEIGHT + 2
        end
        row.cells = {}
        for i, col in ipairs(spec.columns) do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetSize(col.width, ROW_HEIGHT)
            fs:SetPoint("LEFT", x, 0)
            fs:SetJustifyH(col.justify or "LEFT")
            fs:SetWordWrap(false)
            row.cells[i] = fs
            x = x + col.width + 4
        end
        row:SetScript("OnEnter", function(self) if spec.onEnter and self.data then spec.onEnter(self, self.data) end end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row:SetScript("OnClick", function(self) if spec.onClick and self.data then spec.onClick(self, self.data) end end)
    end
    row.data = d
    if row.icon then row.icon:SetTexture(spec.icon(d)) end
    for i, col in ipairs(spec.columns) do
        local text, r, g, b = col.text(d)
        row.cells[i]:SetText(text or "")
        row.cells[i]:SetTextColor(r or 1, g or 1, b or 1)
    end
end

function ListView.Create(parent, spec)
    local lv = { spec = spec, sortKey = spec.sortKey, sortDesc = spec.sortDesc ~= false, rows = {} }
    local x = 14 + (spec.icon and ROW_HEIGHT - 2 or 0)
    for _, col in ipairs(spec.columns) do
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(col.width, HEADER_HEIGHT)
        b:SetPoint("TOPLEFT", x, 0)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetAllPoints()
        fs:SetJustifyH(col.justify or "LEFT")
        fs:SetText(col.title)
        b:SetScript("OnClick", function()
            if lv.sortKey == col.key then lv.sortDesc = not lv.sortDesc
            else lv.sortKey, lv.sortDesc = col.key, not col.ascending end
            lv:SetRows(lv.rows)
        end)
        x = x + col.width + 4
    end

    local scrollBox = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT - 2)
    scrollBox:SetPoint("BOTTOMRIGHT", -20, 0)
    local scrollBar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", function(row, d) InitRow(lv, row, d) end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    lv.scrollBox = scrollBox

    function lv:SetRows(rows)
        self.rows = rows
        table.sort(rows, Compare(self))
        self.scrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
    end
    return lv
end
