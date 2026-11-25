-- Sheet.lua
-- The paper score sheet on the right, plus the fold tab.
-- Nothing is shown in empty cells until you hover one of yours: then it shows the points
-- you'd get, or a pen stroke if it would be 0 (striking the field out).
-- The paper keeps its size; if the window is too short, the paper scrolls (mouse wheel).

local _, Yatzy = ...
local Rules = Yatzy.Rules
local Style = Yatzy.Style
local Sheet = {}
Yatzy.Sheet = Sheet

local MAX_PLAYERS = Rules.MAX_PLAYERS
local MIN_W = 250                    -- the sheet is never narrower than this
local COL_W = 46                     -- every score column gets this much; the sheet grows with players
local LABEL_W = 98                 -- at least this much room for the row names
local MAX_COL_W = 52                 -- docked: score columns never get wider than this
local ROW_H = 19
local TOP = 34                       -- space for the title above the header row
local PAPER_INSET = 8
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local INK = { 0.12, 0.23, 0.48 }          -- your numbers (blue ink)
local GRAPHITE = { 0.23, 0.20, 0.17 }     -- other players' numbers (pencil)
local LABEL = { 0.29, 0.24, 0.19 }
local RED = { 0.61, 0.14, 0.09 }

-- Row order on the sheet
local ROWS = {}
for _, cat in ipairs(Rules.CATEGORIES) do
    if cat.upper then ROWS[#ROWS + 1] = { kind = "cat", cat = cat } end
end
ROWS[#ROWS + 1] = { kind = "sum", label = "Sum (63 = bonus)" }
ROWS[#ROWS + 1] = { kind = "bonus", label = "Bonus" }
for _, cat in ipairs(Rules.CATEGORIES) do
    if not cat.upper then ROWS[#ROWS + 1] = { kind = "cat", cat = cat } end
end
ROWS[#ROWS + 1] = { kind = "total", label = "Total" }

local CONTENT_H = TOP + ROW_H * (#ROWS + 1) + 12   -- full paper height

local function plainFont(fs, size, color)
    fs:SetFont(FONT, size, "")
    fs:SetShadowOffset(0, 0)
    fs:SetTextColor(unpack(color))
end

local function handFont(fs, size, color)
    Style.Font(fs, "hand", size, color)
    fs:SetShadowOffset(0, 0)
end

---------------------------------------------------------------------------
-- Create
---------------------------------------------------------------------------

function Sheet:Create(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(Yatzy.UI.SHEET_W)
    f:SetFrameLevel(parent:GetFrameLevel() + 40)   -- above the dice when it lies over the table
    f:EnableMouse(true)                              -- don't let clicks fall through to the dice
    self.frame = f

    -- Dark wood behind the paper, with a thin metal edge towards the table
    Style.Fill(f, Style.TEX.tableWood, { 0.45, 0.38, 0.33 })
    local edge = f:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT"); edge:SetPoint("BOTTOMLEFT"); edge:SetWidth(3)
    Style.Tile(edge, Style.TEX.metal, Style.BRONZE)

    -- Scroll area holding the paper
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", PAPER_INSET + 2, -PAPER_INSET)
    scroll:SetPoint("BOTTOMRIGHT", -PAPER_INSET - 6, PAPER_INSET)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta) Sheet:ScrollBy(-delta * ROW_H * 2) end)
    scroll:SetScript("OnSizeChanged", function() Sheet:Layout() end)
    -- Redraw shortly after the sheet appears, in case the handwriting font was still loading
    f:SetScript("OnShow", function()
        C_Timer.After(0.15, function() if Sheet.game then Sheet:Refresh() end end)
    end)
    self.scroll = scroll

    local paper = CreateFrame("Frame", nil, scroll)
    paper:SetSize(Yatzy.UI.SHEET_W - 2 * PAPER_INSET - 8, CONTENT_H)
    scroll:SetScrollChild(paper)
    -- WoW draws a scroll area's contents and then applies the window's opacity again, so
    -- a faded window made the paper look faded twice. The paper ignores its parents'
    -- opacity, and gets the fade itself, once, from UI:FadeStep (its own alpha).
    if paper.SetIgnoreParentAlpha then paper:SetIgnoreParentAlpha(true) end
    self.paper = paper

    -- Paper with fibres, darker worn edges, and a strip of tape at the top
    Style.Fill(paper, Style.TEX.paper, { 1, 1, 1 })
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do Style.EdgeShade(paper, side, 18, 0.16) end
    local tape = paper:CreateTexture(nil, "OVERLAY", nil, 6)
    tape:SetColorTexture(0.90, 0.86, 0.71, 0.75)
    tape:SetSize(70, 14)
    tape:SetPoint("TOP", 0, -1)
    tape:SetRotation(math.rad(-3))

    local title = paper:CreateFontString(nil, "OVERLAY")
    Style.Font(title, "display", 15, RED)
    title:SetShadowOffset(0, 0)
    title:SetPoint("TOP", 0, -10)
    title:SetText("YATZY")

    -- "Pop out": put the sheet in its own window (top-right of the paper)
    -- (on the paper, next to the title: it scrolls away with the paper, never over the names)
    local popOut = CreateFrame("Button", nil, paper)
    popOut:SetSize(52, 16)
    popOut:SetPoint("TOPRIGHT", paper, "TOPRIGHT", -6, -8)
    popOut:SetFrameLevel(paper:GetFrameLevel() + 5)
    popOut.text = popOut:CreateFontString(nil, "OVERLAY")
    Style.Font(popOut.text, "display", 9, { RED[1], RED[2], RED[3] })
    popOut.text:SetShadowOffset(0, 0)
    popOut.text:SetPoint("RIGHT")
    popOut.text:SetText("Pop out")
    popOut:SetScript("OnEnter", function(b)
        b.text:SetTextColor(0.85, 0.25, 0.12)
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Pop out")
        GameTooltip:AddLine("Put the score sheet in its own window that you can place anywhere.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    popOut:SetScript("OnLeave", function(b) b.text:SetTextColor(RED[1], RED[2], RED[3]); GameTooltip:Hide() end)
    popOut:SetScript("OnClick", function() Sheet:SetDetached(true) end)
    popOut:SetScript("OnShow", function(b) b.text:SetText(""); Style.SetText(b.text, "Pop out") end)
    self.popOut = popOut

    -- Highlighter stripe behind your column
    self.highlighter = paper:CreateTexture(nil, "BORDER")
    self.highlighter:SetColorTexture(1, 0.86, 0.25, 0.30)

    -- Header (player names, handwritten)
    self.headers = {}
    for p = 1, MAX_PLAYERS do
        local fs = paper:CreateFontString(nil, "OVERLAY")
        handFont(fs, 14, GRAPHITE)
        fs:SetWordWrap(false)                 -- long names are cut short in narrow columns
        self.headers[p] = fs
    end
    self.activeMark = paper:CreateTexture(nil, "ARTWORK")
    self.activeMark:SetColorTexture(unpack(RED))
    Style.ThinLine(self.activeMark, 1, true)

    -- Rows
    self.rows = {}
    for r, def in ipairs(ROWS) do
        local row = { def = def, cells = {} }
        row.label = paper:CreateFontString(nil, "OVERLAY")
        plainFont(row.label, def.kind == "cat" and 11 or 10, def.kind == "cat" and LABEL or RED)
        row.label:SetJustifyH("LEFT")
        row.label:SetText(def.kind == "cat" and def.cat.name or def.label)
        row.line = paper:CreateTexture(nil, "BORDER")
        if def.kind == "cat" then
            row.line:SetColorTexture(0.27, 0.39, 0.63, 0.30)     -- blue ruled line
        else
            row.line:SetColorTexture(RED[1], RED[2], RED[3], 0.5) -- red line under sums
        end
        for p = 1, MAX_PLAYERS do
            local cell = CreateFrame("Button", nil, paper)
            cell.text = cell:CreateFontString(nil, "OVERLAY")
            handFont(cell.text, def.kind == "total" and 17 or 15, GRAPHITE)
            cell.text:SetPoint("CENTER", 0, -1)
            cell.hover = cell:CreateTexture(nil, "BACKGROUND")
            cell.hover:SetAllPoints()
            cell.hover:SetColorTexture(1, 0.86, 0.27, 0.85)
            cell.hover:Hide()
            -- Hand-drawn, anti-aliased pen stroke (rendered image, tinted with the ink colour)
            cell.strike = cell:CreateTexture(nil, "OVERLAY")
            cell.strike:SetTexture(Style.TEX.ui.strike)
            cell.strike:SetPoint("CENTER")
            cell.strike:SetVertexColor(unpack(INK))
            cell.strike:Hide()
            cell.row = def
            cell.player = p
            cell:SetScript("OnEnter", function(c) Sheet:OnCellEnter(c) end)
            cell:SetScript("OnLeave", function(c) Sheet:OnCellLeave(c) end)
            cell:SetScript("OnClick", function(c) Sheet:OnCellClick(c) end)
            -- the mouse wheel scrolls the sheet even when the pointer is over a cell
            cell:EnableMouseWheel(true)
            cell:SetScript("OnMouseWheel", function(_, delta) Sheet:ScrollBy(-delta * ROW_H * 2) end)
            row.cells[p] = cell
        end
        self.rows[r] = row
    end
    -- Column lines (red, like a printed score pad)
    self.columnLines = {}
    for p = 1, MAX_PLAYERS do
        local t = paper:CreateTexture(nil, "BORDER")
        t:SetColorTexture(RED[1], RED[2], RED[3], 0.35)
        Style.ThinLine(t, 1, false)
        self.columnLines[p] = t
    end

    -- Sticky strips: when the paper scrolls, the names stay on top and Total at the bottom
    self.stickyTop = self:CreateSticky(f, "TOP")
    self.stickyBottom = self:CreateSticky(f, "BOTTOM")

    -- Thin scroll bar on the right (only when the paper doesn't fit)
    local track = f:CreateTexture(nil, "ARTWORK")
    track:SetPoint("TOPRIGHT", -5, -PAPER_INSET)
    track:SetPoint("BOTTOMRIGHT", -5, PAPER_INSET)
    track:SetWidth(4)
    track:SetColorTexture(0, 0, 0, 0.45)
    local thumb = f:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(4)
    Style.Tile(thumb, Style.TEX.metal, Style.BRONZE)
    self.track, self.thumb = track, thumb

    -- Fold tab: sits on the sheet's left edge, or at the window edge when folded in
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(24, 116)
    tab:SetFrameLevel(parent:GetFrameLevel() + 45)
    Style.Image(tab, Style.TEX.ui.tab)
    local hl = tab:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.85, 0.6, 0.12)
    tab.text = tab:CreateFontString(nil, "OVERLAY")
    Style.Font(tab.text, "display", 10, Style.TITLE)
    tab.text:SetPoint("CENTER")
    tab:SetScript("OnClick", function() Yatzy.UI:ToggleSheet() end)
    Yatzy.UI.Tooltip(tab, "Score sheet", "Fold the score sheet in or out.")
    self.tab = tab
end

-- The sheet grows (or shrinks) with the number of players: each score column keeps a
-- comfortable width instead of being squeezed. (2 players: 250, 4: 314, 6: 406.)
function Sheet:WidthFor(g)
    local n = g and g.players and #g.players or 2
    return math.max(MIN_W, 2 * PAPER_INSET + 8 + 8 + LABEL_W + n * COL_W)
end

-- Docked in a smaller window the sheet gets narrower before it folds in: columns down
-- to 30 px. Below this width it folds in (and slides over the table when opened).
local MIN_COL_W = 30
function Sheet:MinDockedWidth(g)
    local n = g and g.players and #g.players or 2
    return 2 * PAPER_INSET + 8 + 8 + LABEL_W + n * MIN_COL_W
end

-- Called before the game screen is laid out
function Sheet:SetWidthFor(g)
    self.widthGame = g
    local w = self:WidthFor(g)
    Yatzy.UI.SHEET_W = w
    self.frame:SetWidth(w)
    if self.window then self:FitWindow() end
end

---------------------------------------------------------------------------
-- Detached: the sheet in its own window that can be placed anywhere
-- (setting "Score sheet in its own window", or the Pop out / Dock buttons).
-- It shows and hides, fades and closes together with the main window.
---------------------------------------------------------------------------

local STRIP_H = 22

function Sheet:IsDetached()
    return Yatzy.db and Yatzy.db.options.sheetDetached == true
end

function Sheet:CreateWindow()
    if self.window then return self.window end
    local UI = Yatzy.UI
    local saved = Yatzy.db.sheetWindow or {}
    Yatzy.db.sheetWindow = saved

    local win = CreateFrame("Frame", "YatzySheetWindow", UIParent)
    -- one layer above the main window (DIALOG), so the sheet always lies on top of it
    -- when they overlap; pop-ups (FULLSCREEN_DIALOG) still come above the sheet
    win:SetFrameStrata("FULLSCREEN")
    win:SetSize(self:WidthFor(self.game), saved.height or 420)
    win:SetPoint(saved.point or "CENTER", UIParent, saved.relativePoint or "CENTER", saved.x or 300, saved.y or 0)
    win:SetMovable(true)
    win:SetResizable(true)
    if win.SetResizeBounds then win:SetResizeBounds(200, 160, 800, 900) elseif win.SetMinResize then win:SetMinResize(200, 160) end
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    Style.Fill(win, Style.TEX.tableWood, { 0.45, 0.38, 0.33 })
    Style.MetalBorder(win, 2)

    local function save()
        local point, _, relativePoint, x, y = win:GetPoint()
        saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
        saved.height = win:GetHeight()
    end

    -- Title strip: drag to move; Dock puts the sheet back in the main window
    local strip = CreateFrame("Frame", nil, win)
    strip:SetPoint("TOPLEFT", 2, -2); strip:SetPoint("TOPRIGHT", -2, -2); strip:SetHeight(STRIP_H)
    Style.LeatherPanel(strip, { border = 1 })
    strip:EnableMouse(true)
    strip:RegisterForDrag("LeftButton")
    strip:SetScript("OnDragStart", function() win:StartMoving() end)
    strip:SetScript("OnDragStop", function() win:StopMovingOrSizing(); save() end)
    local label = strip:CreateFontString(nil, "OVERLAY")
    Style.Font(label, "display", 10, Style.TITLE)
    label:SetPoint("LEFT", 8, 0)
    label:SetText("Score sheet")
    win.label = label
    local dock = UI.MakeButton(strip, "Dock", 70, 22, "secondary")
    dock:SetHeight(18)
    dock:SetPoint("RIGHT", -2, 0)
    dock:SetScript("OnClick", function() Sheet:SetDetached(false) end)
    UI.Tooltip(dock, "Dock", "Put the score sheet back in the game window.")
    UI.Tooltip(strip, "Score sheet", "Drag to move. Drag the bottom-right corner to change the size (wider = wider score columns).")

    -- Where the sheet goes
    local content = CreateFrame("Frame", nil, win)
    content:SetPoint("TOPLEFT", 2, -(STRIP_H + 2))
    content:SetPoint("BOTTOMRIGHT", -2, 2)
    win.content = content

    -- Height grip, bottom-right
    local grip = CreateFrame("Button", nil, win)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(win:GetFrameLevel() + 100)
    local gripTex = grip:CreateTexture(nil, "OVERLAY")
    gripTex:SetAllPoints()
    gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    -- Width and height: wider makes the score columns wider
    grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        win:StopMovingOrSizing()
        saved.width = math.max(win:GetWidth(), Sheet:MinWindowWidth(Sheet.game))
        win:SetWidth(saved.width)
        save()
    end)

    UI:SetupFade(win)
    win:Hide()
    self.window = win

    -- Follow the main window and the game screen
    for _, frame in ipairs({ UI.game, Yatzy.mainWindow }) do
        frame:HookScript("OnShow", function() Sheet:UpdateWindow() end)
        frame:HookScript("OnHide", function() Sheet:UpdateWindow() end)
    end
    return win
end

-- Narrowest the detached window may be: room for the row names and 34 px per player.
function Sheet:MinWindowWidth(g)
    local n = g and g.players and #g.players or 2
    return 2 * PAPER_INSET + 8 + 8 + 4 + LABEL_W + n * 34
end

-- Detached window width: what you dragged it to (saved), but never too narrow for the
-- players in this game. Without a saved width: the normal sheet width.
function Sheet:FitWindow()
    local win = self.window
    if not win then return end
    local minW = self:MinWindowWidth(self.game)
    if win.SetResizeBounds then win:SetResizeBounds(minW, 160, 1200, 1000)
    elseif win.SetMinResize then win:SetMinResize(minW, 160) end
    local saved = Yatzy.db.sheetWindow or {}
    win:SetWidth(math.max(minW, saved.width or (self:WidthFor(self.game) + 4)))
end

-- Show the detached window only while a game is on screen in the main window.
function Sheet:UpdateWindow()
    if not self.window then return end
    local UI = Yatzy.UI
    self.window:SetShown(self:IsDetached() and UI.game:IsVisible() and true or false)
end

-- Move the sheet frame into the window or back into the main window.
function Sheet:ApplyDetached()
    local UI = Yatzy.UI
    local f = self.frame
    if self:IsDetached() then
        local win = self:CreateWindow()
        self:FitWindow()
        f:SetParent(win.content)
        f:ClearAllPoints()
        f:SetAllPoints(win.content)
        f:Show()
        self.tab:Hide()
        if self.animator then self.animator:SetScript("OnUpdate", nil) end
    else
        f:SetParent(UI.game)
        f:SetWidth(UI.SHEET_W)
    end
    -- take the new parent's layer (its own window on top, or the main window), and keep
    -- the pinned strips and the pop-out link above the paper after the move
    f:SetFrameStrata(f:GetParent():GetFrameStrata())
    f:SetFrameLevel(f:GetParent():GetFrameLevel() + 40)
    for _, s in ipairs({ self.stickyTop, self.stickyBottom }) do s:SetFrameLevel(f:GetFrameLevel() + 20) end
    if self.popOut then
        self.popOut:SetFrameLevel(self.paper:GetFrameLevel() + 5)
        self.popOut:SetShown(not self:IsDetached())
    end
    self:UpdateWindow()
    UI:Layout()
    if self.game then self:Refresh() end
end

function Sheet:SetDetached(on)
    Yatzy.db.options.sheetDetached = on and true or false
    self:ApplyDetached()
    if Yatzy.Settings.RefreshAll then Yatzy.Settings:RefreshAll() end
end

-- A strip of paper pinned to the top (player names) or bottom (Total) of the scroll area.
-- Only shown while the real row is scrolled out of view.
function Sheet:CreateSticky(f, side)
    local s = CreateFrame("Frame", nil, f)
    s:SetPoint(side .. "LEFT", self.scroll, side .. "LEFT")
    s:SetPoint(side .. "RIGHT", self.scroll, side .. "RIGHT")
    s:SetHeight(ROW_H + 2)
    s:SetFrameLevel(f:GetFrameLevel() + 20)          -- above the paper's cells
    s:EnableMouse(true)                               -- the rows underneath can't be clicked
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(_, delta) Sheet:ScrollBy(-delta * ROW_H * 2) end)
    Style.Fill(s, Style.TEX.paper, { 1, 1, 1 })

    s.highlighter = s:CreateTexture(nil, "BORDER")
    s.highlighter:SetColorTexture(1, 0.86, 0.25, 0.30)
    s.lines, s.texts = {}, {}
    for p = 1, MAX_PLAYERS do
        local t = s:CreateTexture(nil, "BORDER")
        t:SetColorTexture(RED[1], RED[2], RED[3], 0.35)
        Style.ThinLine(t, 1, false)
        s.lines[p] = t
        local fs = s:CreateFontString(nil, "OVERLAY")
        handFont(fs, side == "TOP" and 14 or 17, GRAPHITE)
        fs:SetWordWrap(false)
        s.texts[p] = fs
    end

    -- Red rule on the edge towards the rows, and a soft shadow on the rows it covers
    local inner, outer = side == "TOP" and "BOTTOM" or "TOP", side
    local rule = s:CreateTexture(nil, "ARTWORK")
    rule:SetPoint(inner .. "LEFT", 4, 0); rule:SetPoint(inner .. "RIGHT", -4, 0); Style.ThinLine(rule, 2, true)
    rule:SetColorTexture(RED[1], RED[2], RED[3], 0.55)
    for i, a in ipairs({ 0.16, 0.08, 0.04 }) do
        local sh = s:CreateTexture(nil, "ARTWORK")
        sh:SetColorTexture(0, 0, 0, a)
        Style.ThinLine(sh, 1, true)
        local dy = side == "TOP" and -(i - 1) or (i - 1)
        sh:SetPoint(outer .. "LEFT", s, inner .. "LEFT", 0, dy)
        sh:SetPoint(outer .. "RIGHT", s, inner .. "RIGHT", 0, dy)
    end

    if side == "TOP" then
        s.mark = s:CreateTexture(nil, "ARTWORK")      -- red line under whose turn it is
        s.mark:SetColorTexture(unpack(RED))
        Style.ThinLine(s.mark, 1, true)
    else
        s.label = s:CreateFontString(nil, "OVERLAY")
        plainFont(s.label, 10, RED)
        s.label:SetText("Total")
        s.label:SetPoint("LEFT", 8, 0)
    end
    -- Text set while a strip is hidden may not draw with a custom font: write it again on show
    s:SetScript("OnShow", function()
        if Sheet.game then
            Sheet:RefreshSticky(Sheet.game, Sheet.game.status == "active" and Rules.CurrentPlayer(Sheet.game) or nil)
        end
    end)
    s:Hide()
    return s
end

-- Position the sheet and the tab (called from UI:Layout). With `animate`, the sheet
-- slides in/out; the table (anchored to the sheet's left edge) grows/shrinks with it.
-- self.slide = how far the sheet is pushed out to the right (0 = fully in).
local SLIDE_TIME = 0.25

function Sheet:Place(parent, open, narrow, animate)
    local f, tab = self.frame, self.tab
    if self:IsDetached() then          -- in its own window: no sliding, no fold tab
        tab:Hide()
        self:Layout()
        return
    end
    tab:Show()
    self.parent, self.open, self.narrow = parent, open, narrow
    tab:ClearAllPoints()
    tab:SetPoint("RIGHT", f, "LEFT", 0, 0)                 -- the tab always rides on the sheet's edge
    tab.text:SetText(open and "S\nC\nO\nR\nE\nS\n\n>" or "<\n\nS\nC\nO\nR\nE\nS")
    if not self.animator then
        self.animator = CreateFrame("Frame", nil, parent)
    end
    local target = open and 0 or Yatzy.UI.SHEET_W
    if open then f:Show() end
    if animate and self.slide ~= nil and self.slide ~= target then
        self.slideFrom, self.slideTarget, self.slideT = self.slide, target, 0
        self.animator:SetScript("OnUpdate", function(_, elapsed) Sheet:SlideStep(elapsed) end)
    else
        self.animator:SetScript("OnUpdate", nil)
        self.slide = target
        self:ApplySlide()
    end
    if open then self:Layout() end
end

function Sheet:ApplySlide()
    local f = self.frame
    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", self.parent, "TOPRIGHT", self.slide, 0)
    f:SetPoint("BOTTOMRIGHT", self.parent, "BOTTOMRIGHT", self.slide, 0)
    f:SetShown(self.open or self.slide < Yatzy.UI.SHEET_W)
end

function Sheet:SlideStep(elapsed)
    self.slideT = math.min(1, self.slideT + elapsed / SLIDE_TIME)
    local e = 1 - (1 - self.slideT) ^ 3
    self.slide = self.slideFrom + (self.slideTarget - self.slideFrom) * e
    self:ApplySlide()
    if self.slideT >= 1 then
        self.animator:SetScript("OnUpdate", nil)
    end
end

---------------------------------------------------------------------------
-- Scrolling
---------------------------------------------------------------------------

function Sheet:ScrollBy(dy)
    local scroll = self.scroll
    local maxScroll = math.max(0, CONTENT_H - (scroll:GetHeight() or 0))
    local value = math.max(0, math.min(maxScroll, (scroll:GetVerticalScroll() or 0) + dy))
    scroll:SetVerticalScroll(value)
    self:UpdateScrollBar()
end

function Sheet:UpdateScrollBar()
    local scroll = self.scroll
    local viewH = scroll:GetHeight() or 0
    local overflow = CONTENT_H - viewH
    if overflow <= 1 then
        self.track:Hide(); self.thumb:Hide()
        self.stickyTop:Hide(); self.stickyBottom:Hide()
        if (scroll:GetVerticalScroll() or 0) ~= 0 then scroll:SetVerticalScroll(0) end
        return
    end
    self.track:Show(); self.thumb:Show()
    -- Names pinned once their row starts to scroll away; Total until its row comes into view
    local s = scroll:GetVerticalScroll() or 0
    self.stickyTop:SetShown(s > TOP + 1)
    self.stickyBottom:SetShown(s + viewH < TOP + ROW_H * (#ROWS + 1) - 1)
    local trackH = self.track:GetHeight() or viewH
    local thumbH = math.max(20, trackH * viewH / CONTENT_H)
    local pos = (scroll:GetVerticalScroll() or 0) / overflow
    self.thumb:SetHeight(thumbH)
    self.thumb:ClearAllPoints()
    self.thumb:SetPoint("TOP", self.track, "TOP", 0, -(trackH - thumbH) * pos)
end

---------------------------------------------------------------------------
-- Layout: fixed row height; the columns share the paper's width
---------------------------------------------------------------------------

function Sheet:Layout()
    local g = self.game
    local paper = self.paper
    local w = (self.scroll:GetWidth() or 0)
    if w == 0 then return end
    paper:SetWidth(w)
    local players = g and #g.players or 2
    -- Score columns are at most MAX_COL_W wide; the rest goes to the row names
    -- (in its own window the columns take whatever width you give the window)
    local colW = (w - 8 - LABEL_W) / players
    if not self:IsDetached() then colW = math.min(MAX_COL_W, colW) end
    local labelW = w - 8 - colW * players
    self.labelW = labelW

    local function colX(p) return 6 + labelW + (p - 1) * colW end

    for p = 1, MAX_PLAYERS do
        local hdr = self.headers[p]
        hdr:ClearAllPoints()
        hdr:SetPoint("CENTER", paper, "TOPLEFT", colX(p) + colW / 2, -TOP - ROW_H / 2)
        hdr:SetWidth(colW - 2)
        hdr:SetShown(p <= players)
        local line = self.columnLines[p]
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", paper, "TOPLEFT", colX(p), -TOP)
        line:SetPoint("BOTTOMLEFT", paper, "TOPLEFT", colX(p), -TOP - ROW_H * (#ROWS + 1))
        line:SetShown(p <= players)
    end

    for r, row in ipairs(self.rows) do
        local y = -TOP - ROW_H * r
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", paper, "TOPLEFT", 8, y - ROW_H / 2)
        row.line:ClearAllPoints()
        row.line:SetPoint("TOPLEFT", paper, "TOPLEFT", 4, y - ROW_H)
        row.line:SetPoint("TOPRIGHT", paper, "TOPRIGHT", -4, y - ROW_H)
        Style.ThinLine(row.line, row.def.kind == "cat" and 1 or 2, true)   -- whole screen pixels: never vanishes
        for p = 1, MAX_PLAYERS do
            local cell = row.cells[p]
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", paper, "TOPLEFT", colX(p) + 1, y - 1)
            cell:SetSize(colW - 2, ROW_H - 1)
            -- A clear pen stroke: never shorter than 30 px or thinner than 5 px
            local strikeW = math.max(30, math.min((colW - 2) * 0.85, 64))
            cell.strike:SetSize(math.min(strikeW, colW - 4), math.max(5, strikeW / 8))
            cell:SetShown(p <= players)
        end
    end

    -- Sticky strips: same columns as the paper (they start at the same left edge)
    for _, s in ipairs({ self.stickyTop, self.stickyBottom }) do
        local h = s:GetHeight() or (ROW_H + 2)
        for p = 1, MAX_PLAYERS do
            local fs = s.texts[p]
            fs:ClearAllPoints()
            fs:SetPoint("CENTER", s, "TOPLEFT", colX(p) + colW / 2, -ROW_H / 2 - (s == self.stickyTop and 1 or 2))
            fs:SetWidth(colW - 2)
            fs:SetShown(p <= players)
            local line = s.lines[p]
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", s, "TOPLEFT", colX(p), 0)
            line:SetHeight(h)
            line:SetShown(p <= players)
        end
    end

    self.colW = colW
    self:PlaceHighlighter()
    self:ScrollBy(0)        -- keep the scroll position valid after a resize
end

function Sheet:PlaceHighlighter()
    local g = self.game
    if not g or not self.colW then self.highlighter:Hide(); return end
    local x = 6 + (self.labelW or LABEL_W) + (g.me - 1) * self.colW
    self.highlighter:ClearAllPoints()
    self.highlighter:SetPoint("TOPLEFT", self.paper, "TOPLEFT", x, -TOP)
    self.highlighter:SetSize(self.colW, ROW_H * (#ROWS + 1))
    self.highlighter:Show()
    for _, s in ipairs({ self.stickyTop, self.stickyBottom }) do
        s.highlighter:ClearAllPoints()
        s.highlighter:SetPoint("TOPLEFT", s, "TOPLEFT", x, 0)
        s.highlighter:SetSize(self.colW, s:GetHeight() or ROW_H)
        s.highlighter:Show()
    end
end

---------------------------------------------------------------------------
-- Content
---------------------------------------------------------------------------

function Sheet:SetGame(g)
    local relayout = not self.game or (#self.game.players ~= #g.players)
    self.game = g
    if relayout then self:Layout() end
end

-- Can the local player write in this cell right now?
function Sheet:IsPickable(cell)
    local g = self.game
    return g and cell.row.kind == "cat" and cell.player == g.me
        and Rules.CanScore(g, cell.row.cat.id) and Yatzy.Games:IsMyTurn(g)
        and not Yatzy.Board.animating and not Yatzy.Play.committing
end

local function showValue(cell, value, color)
    cell.strike:Hide()
    cell.text:SetTextColor(unpack(color))
    if value == 0 then
        cell.text:SetText("")
        cell.strike:SetVertexColor(unpack(color))
        cell.strike:Show()
    else
        Style.SetText(cell.text, value or "")
    end
end

function Sheet:Refresh(g)
    g = g or self.game
    if not g then return end
    if g ~= self.game then self:SetGame(g) end
    local current = g.status == "active" and Rules.CurrentPlayer(g) or nil

    for p = 1, #g.players do
        local name = Yatzy.Games:PlayerName(g, p, true)
        self.headers[p]:Show()
        Style.SetText(self.headers[p], name)
        self.headers[p]:SetTextColor(unpack(p == g.me and INK or GRAPHITE))
    end
    if current and self.colW then
        local hdr = self.headers[current]
        self.activeMark:ClearAllPoints()
        self.activeMark:SetPoint("TOP", hdr, "BOTTOM", 0, -1)
        self.activeMark:SetWidth(math.min(hdr:GetStringWidth() + 6, self.colW - 4))
        self.activeMark:Show()
    else
        self.activeMark:Hide()
    end

    for _, row in ipairs(self.rows) do
        for p = 1, #g.players do
            local cell = row.cells[p]
            local sheet = g.sheets[p]
            local color = (p == g.me) and INK or GRAPHITE
            cell.hover:Hide()
            local kind = row.def.kind
            if kind == "cat" then
                showValue(cell, sheet[row.def.cat.id], color)
                cell:EnableMouse(self:IsPickable(cell))
            else
                cell:EnableMouse(false)
                if kind == "sum" then
                    local sum = Rules.UpperSum(sheet)
                    showValue(cell, sum > 0 and sum or nil, color)
                elseif kind == "bonus" then
                    local upperDone = true
                    for _, cat in ipairs(Rules.CATEGORIES) do
                        if cat.upper and sheet[cat.id] == nil then upperDone = false end
                    end
                    local bonus = Rules.Bonus(sheet)
                    showValue(cell, bonus > 0 and bonus or (upperDone and 0 or nil), color)
                elseif kind == "total" then
                    -- totals stay secret until the game is over (a dash while it runs)
                    local total = Rules.Total(sheet)
                    if g.status == "active" then showValue(cell, total > 0 and "–" or nil, color)
                    else showValue(cell, total > 0 and total or nil, color) end
                end
            end
        end
    end
    self:RefreshSticky(g, current)
    self:PlaceHighlighter()
end

-- Names and totals in the pinned strips
function Sheet:RefreshSticky(g, current)
    local top, bottom = self.stickyTop, self.stickyBottom
    for p = 1, #g.players do
        local color = (p == g.me) and INK or GRAPHITE
        top.texts[p]:SetText("")                        -- force a redraw (font may have loaded since)
        Style.SetText(top.texts[p], Yatzy.Games:PlayerName(g, p, true))
        top.texts[p]:SetTextColor(unpack(color))
        bottom.texts[p]:SetText("")
        local total = Rules.Total(g.sheets[p])
        if g.status == "active" and total > 0 then total = "–" end      -- secret until the end
        Style.SetText(bottom.texts[p], (total ~= 0 and total) or "")
        bottom.texts[p]:SetTextColor(unpack(color))
    end
    if current and self.colW then
        local hdr = top.texts[current]
        top.mark:ClearAllPoints()
        top.mark:SetPoint("TOP", hdr, "BOTTOM", 0, -1)
        top.mark:SetWidth(math.min(hdr:GetStringWidth() + 6, self.colW - 4))
        top.mark:Show()
    else
        top.mark:Hide()
    end
end

---------------------------------------------------------------------------
-- Hover and click
---------------------------------------------------------------------------

function Sheet:OnCellEnter(cell)
    if not self:IsPickable(cell) then return end
    local points = Rules.Score(cell.row.cat.id, self.game.dice)
    cell.hover:Show()
    if points == 0 then
        cell.text:SetText("")
        cell.strike:SetVertexColor(INK[1], INK[2], INK[3], 0.6)
        cell.strike:Show()
    else
        cell.text:SetTextColor(unpack(INK))
        cell.text:SetText(points)
        cell.strike:Hide()
    end
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:AddLine(points == 0 and ("Strike out " .. cell.row.cat.name) or ("Write %d in %s"):format(points, cell.row.cat.name))
    GameTooltip:Show()
end

function Sheet:OnCellLeave(cell)
    GameTooltip:Hide()
    if not self.game then return end
    cell.hover:Hide()
    if cell.row.kind == "cat" then
        local v = self.game.sheets[cell.player][cell.row.cat.id]
        showValue(cell, v, cell.player == self.game.me and INK or GRAPHITE)
    end
end

function Sheet:OnCellClick(cell)
    if not self:IsPickable(cell) then return end
    GameTooltip:Hide()
    if self:WouldWaste(cell) then
        self:ConfirmStrike(cell)
        return
    end
    Yatzy.Play:Score(cell.row.cat.id)
end

-- Striking this field out (0 points) while another open field would score?
function Sheet:WouldWaste(cell)
    local g = self.game
    if Rules.Score(cell.row.cat.id, g.dice) > 0 then return false end
    for _, cat in ipairs(Rules.CATEGORIES) do
        if cat.id ~= cell.row.cat.id and Rules.CanScore(g, cat.id) and Rules.Score(cat.id, g.dice) > 0 then
            return true
        end
    end
    return false
end

-- Small question right above the clicked field. Clicking elsewhere or Escape = cancel.
function Sheet:ConfirmStrike(cell)
    local UI = Yatzy.UI
    local pop = self.confirm
    if not pop then
        local cover = CreateFrame("Button", nil, UIParent)       -- click anywhere else: cancel
        cover:SetAllPoints(UIParent)
        cover:SetFrameStrata("FULLSCREEN_DIALOG")                -- above the popped-out sheet too
        cover:SetScript("OnClick", function() Sheet:CloseConfirm() end)
        cover:Hide()

        pop = CreateFrame("Frame", nil, UIParent)
        pop:SetSize(256, 66)
        pop:SetFrameStrata("FULLSCREEN_DIALOG")
        pop:SetFrameLevel(cover:GetFrameLevel() + 10)            -- above its click-catcher
        pop:EnableMouse(true)
        Style.LeatherPanel(pop, { border = 2 })
        pop.text = pop:CreateFontString(nil, "OVERLAY")
        Style.Font(pop.text, "display", 10, Style.TEXT)
        pop.text:SetPoint("TOP", 0, -8)
        pop.text:SetWidth(240)
        local yes = UI.MakeButton(pop, "Strike out", 130, 26)
        yes:SetPoint("BOTTOMLEFT", 8, 7)
        yes:SetScript("OnClick", function()
            local id = pop.catId
            Sheet:CloseConfirm()
            if id then Yatzy.Play:Score(id) end
        end)
        local no = UI.MakeButton(pop, "Cancel", 100, 26, "secondary")
        no:SetPoint("BOTTOMRIGHT", -8, 7)
        no:SetScript("OnClick", function() Sheet:CloseConfirm() end)
        -- Escape cancels (other keys still reach the game)
        pop:EnableKeyboard(true)
        pop:SetScript("OnKeyDown", function(p, key)
            local esc = key == "ESCAPE"
            if p.SetPropagateKeyboardInput then p:SetPropagateKeyboardInput(not esc) end
            if esc then Sheet:CloseConfirm() end
        end)
        pop.cover = cover
        pop:Hide()
        self.frame:HookScript("OnHide", function() Sheet:CloseConfirm() end)
        self.confirm = pop
    end
    pop.catId = cell.row.cat.id
    pop.text:SetText("")
    Style.SetText(pop.text, ("Strike out %s?\nYou could score elsewhere."):format(cell.row.cat.name))
    pop:ClearAllPoints()
    pop:SetPoint("BOTTOM", cell, "TOP", 0, 4)
    pop:SetClampedToScreen(true)
    pop.cover:Show()
    pop:Show()
end

function Sheet:CloseConfirm()
    local pop = self.confirm
    if not pop then return end
    pop.catId = nil
    pop:Hide()
    pop.cover:Hide()
end
