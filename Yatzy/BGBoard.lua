-- BGBoard.lua
-- The backgammon window: its own movable, resizable window with the board, the checkers,
-- the dice and the buttons. It only draws and passes clicks on; the turn flow is in
-- BGPlay.lua and the rules in BGRules.lua.
--
-- You always play from the bottom: your home board is bottom right, and your checkers
-- travel from the top right, along the top, down the left and along the bottom. Your
-- checkers are red, the opponent's ivory. The whole board is drawn at one design size
-- and scaled to fit the window.
--
-- Moving: click a checker (the points it can reach light up) and click a lit point,
-- or drag the checker there. A point that needs both dice plays both steps.

local _, Yatzy = ...
local BG = Yatzy.BG
local Style = Yatzy.Style
local Board = {}
Yatzy.BGBoard = Board

-- Board geometry, in design units (the board is scaled as a whole)
local RIM, PW, BARW, TRAYW = 12, 36, 40, 48
local C, PH, MID = 34, 170, 50         -- checker size, point length, middle strip
local LEFT_X = RIM
local BAR_X = LEFT_X + 6 * PW          -- 228
local RIGHT_X = BAR_X + BARW           -- 268
local FIELD_R = RIGHT_X + 6 * PW       -- 484
local TRAY_X = FIELD_R + RIM           -- 496
local BOARD_W = TRAY_X + TRAYW + RIM   -- 556
local TOP_Y = RIM
local MID_Y = TOP_Y + PH               -- top of the middle strip
local BOT_Y = MID_Y + MID
local BOTTOM = BOT_Y + PH              -- bottom edge of the field
local BOARD_H = BOTTOM + RIM
local CENTER_Y = MID_Y + MID / 2
local CTRL_H = 46                      -- status line (with the picture and Poke) above the board
local CONTENT_W, CONTENT_H = BOARD_W, BOARD_H + CTRL_H
local CHECKER_TEX = C * 64 / 52        -- the checker art fills 52 of its 64 px
local SLICE_H = 9                      -- a borne-off checker, seen from the side
-- Dice sizes (design units): tumbling, lying in the row, the "primary" die, doubles (2x2)
local DIE_ROLL, DIE_LINE, DIE_PRIMARY, DIE_DOUBLE = 36, 44, 66, 40
local DIE_SECOND = 38              -- dice-first play: the die you are not using
local THROW_TIME = 0.75        -- dice tumble about this long (each one varies)
local REST_TIME = 0.35         -- they lie still a moment where they landed ...
local LINE_TIME = 0.3          -- ... then glide into a row in the middle of the half
local BONUS_TIME = 0.25        -- doubles: two more dice slide out from under the first two
local SELECT_TIME = 0.1        -- a selected checker grows / lights fade in this fast

local DEFAULT_W, DEFAULT_H = 680, 600
local MIN_W, MIN_H = 380, 330
local MAX_W, MAX_H = 1600, 1200
local TITLE_H, BORDER = 30, 6

local FLY_TIME = 0.30
local HIT_TIME = 0.32          -- a hit checker flying to the bar
local ROLL_TIME = 0.5
local GOLD = Style.TITLE
local DIM = { 0.70, 0.64, 0.52 }

local PIPS = {
    [1] = { 5 }, [2] = { 1, 9 }, [3] = { 1, 5, 9 },
    [4] = { 1, 3, 7, 9 }, [5] = { 1, 3, 5, 7, 9 }, [6] = { 1, 3, 4, 6, 7, 9 },
}

local function Play() return Yatzy.BGPlay end
local function Games() return Yatzy.Games end

---------------------------------------------------------------------------
-- Geometry: where things are on the board (x right, y DOWN from the top-left)
---------------------------------------------------------------------------

-- Centre x of my point r (1..24, my numbering: 1 = deepest in my home board)
local function pointX(r)
    if r <= 6 then return RIGHT_X + (6 - r) * PW + PW / 2 end
    if r <= 12 then return LEFT_X + (12 - r) * PW + PW / 2 end
    if r <= 18 then return LEFT_X + (r - 13) * PW + PW / 2 end
    return RIGHT_X + (r - 19) * PW + PW / 2
end
local function isTop(r) return r >= 13 end

-- Distance between checkers in a stack of n: they overlap when they don't fit
local function stackStep(n, room)
    if n <= 1 then return C end
    return math.min(C, (room - C) / (n - 1))
end

-- Centre of checker i (1 = at the board edge) in a stack of n on my point r
local function checkerXY(r, i, n)
    local step = stackStep(n, PH)
    if isTop(r) then return pointX(r), TOP_Y + C / 2 + (i - 1) * step end
    return pointX(r), BOTTOM - C / 2 - (i - 1) * step
end

-- On the bar: mine below the middle, theirs above
local function barXY(mine, i, n)
    local step = stackStep(n, PH - 6)
    local x = BAR_X + BARW / 2
    if mine then return x, CENTER_Y + 4 + C / 2 + (i - 1) * step end
    return x, CENTER_Y - 4 - C / 2 - (i - 1) * step
end

-- Borne off, in the tray on the right: mine in the bottom half, theirs in the top
local function offXY(mine, i)
    local x = TRAY_X + TRAYW / 2
    if mine then return x, BOTTOM - 4 - SLICE_H / 2 - (i - 1) * (SLICE_H + 1) end
    return x, TOP_Y + 4 + SLICE_H / 2 + (i - 1) * (SLICE_H + 1)
end

-- What is under (x, y): my point number 1..24, "bar", "off", or nil
local function hitTest(x, y)
    if y < TOP_Y or y > BOTTOM then return nil end
    if x >= TRAY_X - 4 and x <= TRAY_X + TRAYW + 4 then return "off" end
    if x >= BAR_X and x < RIGHT_X then return "bar" end
    local top = y < CENTER_Y
    if x >= LEFT_X and x < BAR_X then
        local col = math.floor((x - LEFT_X) / PW)
        return top and (13 + col) or (12 - col)
    end
    if x >= RIGHT_X and x < FIELD_R then
        local col = math.floor((x - RIGHT_X) / PW)
        return top and (19 + col) or (6 - col)
    end
    return nil
end

-- Place a region's centre at a board position
local function at(region, x, y)
    region:ClearAllPoints()
    region:SetPoint("CENTER", Board.board, "TOPLEFT", x, -y)
end

---------------------------------------------------------------------------
-- Viewer: board positions (0..25) <-> my numbering
---------------------------------------------------------------------------

function Board:Me() return self.g and self.g.me or 1 end
function Board:Them() return 3 - self:Me() end

function Board:Rel(pos)            -- absolute point -> my number
    return self:Me() == 1 and pos or 25 - pos
end
function Board:Abs(r)              -- my number -> absolute point
    return self:Me() == 1 and r or 25 - r
end

-- A hitTest result as a board position for my checkers
function Board:KeyToPos(key)
    if key == "bar" then return BG.BAR[self:Me()] end
    if key == "off" then return BG.OFF[self:Me()] end
    if type(key) == "number" then return self:Abs(key) end
end

-- Where the top checker of `seat` at `pos` is drawn
function Board:TopXY(seat, pos)
    local b = self.g.board
    local mine = seat == self:Me()
    local n = math.max(1, BG.Count(b, seat, pos))
    if pos == BG.BAR[seat] then return barXY(mine, n, n) end
    if pos == BG.OFF[seat] then return offXY(mine, n) end
    return checkerXY(self:Rel(pos), n, n)
end

local function checkerTex(mine)
    return mine and Style.TEX.ui.checkerRed or Style.TEX.ui.checkerIvory
end

---------------------------------------------------------------------------
-- Building the window
---------------------------------------------------------------------------

local function savePosition(f)
    local saved = Yatzy.db.bgWindow
    local point, _, relativePoint, x, y = f:GetPoint()
    saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
    saved.width, saved.height = f:GetWidth(), f:GetHeight()
end

local function addResizeHandle(f, sizingPoint, setPoints)
    local h = CreateFrame("Frame", nil, f)
    setPoints(h)
    h:SetFrameLevel(f:GetFrameLevel() + 100)
    h:EnableMouse(true)
    h:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then f:StartSizing(sizingPoint) end
    end)
    h:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        savePosition(f)
    end)
    return h
end

function Board:CreateWindow()
    if self.window then return end
    Yatzy.db.bgWindow = Yatzy.db.bgWindow or {}
    local saved = Yatzy.db.bgWindow

    local f = CreateFrame("Frame", "YatzyBGWindow", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:EnableMouse(true)
    if f.SetResizeBounds then f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    else f:SetMinResize(MIN_W, MIN_H); f:SetMaxResize(MAX_W, MAX_H) end
    f:SetPoint(saved.point or "CENTER", UIParent, saved.relativePoint or "CENTER", saved.x or 60, saved.y or -20)
    f:SetSize(saved.width or DEFAULT_W, saved.height or DEFAULT_H)

    local fill = Style.Fill(f, Style.TEX.leather, { 0.26, 0.21, 0.18 })
    fill:ClearAllPoints()
    fill:SetPoint("TOPLEFT", BORDER, -BORDER)
    fill:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    Style.WindowFrame(f, BORDER)

    -- Title bar: leather strip with a stitched seam and the red name plaque
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", BORDER, -BORDER)
    bar:SetPoint("TOPRIGHT", -BORDER, -BORDER)
    bar:SetHeight(TITLE_H)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() f:StartMoving() end)
    bar:SetScript("OnDragStop", function() f:StopMovingOrSizing(); savePosition(f) end)
    Style.Fill(bar, Style.TEX.leather, Style.LEATHER_DARK)
    local seam = bar:CreateTexture(nil, "ARTWORK")
    seam:SetTexture(Style.TEX.stitchH, "REPEAT", "REPEAT")
    seam:SetHorizTile(true)
    seam:SetPoint("BOTTOMLEFT", 8, 4); seam:SetPoint("BOTTOMRIGHT", -8, 4); seam:SetHeight(2)
    local barLine = bar:CreateTexture(nil, "BORDER")
    barLine:SetPoint("BOTTOMLEFT"); barLine:SetPoint("BOTTOMRIGHT"); barLine:SetHeight(2)
    Style.Tile(barLine, Style.TEX.metal, Style.BRONZE)

    local plaque = CreateFrame("Frame", nil, bar)
    plaque:SetSize(220, 26)
    plaque:SetPoint("CENTER", 0, 1)
    Style.Image(plaque, Style.TEX.ui.plaque)
    local title = plaque:CreateFontString(nil, "OVERLAY")
    Style.Font(title, "title", 16, GOLD)
    title:SetShadowOffset(1, -1)
    title:SetPoint("CENTER")
    title:SetText("Backgammon")
    bar:SetScript("OnSizeChanged", function(_, w) plaque:SetShown((w or 0) >= 500) end)

    local close = Style.Button(bar, "X", 22, 22, "secondary")
    close:SetPoint("RIGHT", -4, 1)
    close:SetScript("OnClick", function() f:Hide() end)
    Yatzy.UI.Tooltip(close, "Close", "Your game is saved.")

    -- the same Settings list as in the main window (with "move with the lit die")
    local settings = Style.Button(bar, "", 22, 22, "secondary")        -- a cog, like the main window
    Yatzy.UI.ButtonIcon(settings, Style.TEX.ui.gear)
    settings:SetPoint("RIGHT", close, "LEFT", -4, 0)
    Yatzy.UI.Tooltip(settings, "Settings", "How you move checkers, fading, notices, Escape key and sound.")
    Yatzy.Settings:AttachToButton(settings, f, "bg")

    local home = Style.Button(bar, "", 28, 22, "secondary")
    home:SetPoint("LEFT", 4, 1)
    local homeIcon = home:CreateTexture(nil, "OVERLAY")
    homeIcon:SetTexture(Style.TEX.ui.home)
    homeIcon:SetSize(16, 16)
    homeIcon:SetPoint("CENTER")
    home:SetScript("OnClick", function()
        Yatzy.UI:ShowStart()
        if Yatzy.mainWindow and not Yatzy.mainWindow:IsShown() then Yatzy.mainWindow:Show() end
        if Yatzy.mainWindow and Yatzy.mainWindow.Raise then Yatzy.mainWindow:Raise() end
    end)
    Yatzy.UI.Tooltip(home, "Main menu", "Your games and the other games.")

    addResizeHandle(f, "LEFT", function(h) h:SetPoint("TOPLEFT", 0, -TITLE_H - BORDER); h:SetPoint("BOTTOMLEFT", 0, 14); h:SetWidth(BORDER) end)
    addResizeHandle(f, "RIGHT", function(h) h:SetPoint("TOPRIGHT", 0, -TITLE_H - BORDER); h:SetPoint("BOTTOMRIGHT", 0, 22); h:SetWidth(BORDER) end)
    addResizeHandle(f, "BOTTOM", function(h) h:SetPoint("BOTTOMLEFT", 14, 0); h:SetPoint("BOTTOMRIGHT", -22, 0); h:SetHeight(BORDER) end)
    addResizeHandle(f, "BOTTOMLEFT", function(h) h:SetPoint("BOTTOMLEFT"); h:SetSize(14, 14) end)
    local grip = addResizeHandle(f, "BOTTOMRIGHT", function(h) h:SetPoint("BOTTOMRIGHT", -1, 1); h:SetSize(20, 20) end)
    local gripTex = grip:CreateTexture(nil, "OVERLAY")
    gripTex:SetAllPoints()
    gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")

    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", BORDER + 8, -(BORDER + TITLE_H + 8))
    body:SetPoint("BOTTOMRIGHT", -BORDER - 8, BORDER + 6)
    self.body = body
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do Style.EdgeShade(f, side, 40, 0.45) end

    -- Everything below lives in `content`, drawn at design size and scaled to fit
    local content = CreateFrame("Frame", nil, body)
    content:SetSize(CONTENT_W, CONTENT_H)
    content:SetPoint("CENTER")
    self.content = content
    self:CreateBoard(content)
    self:CreateControls(content)
    self:CreateOverPanel(content)

    f:SetScript("OnSizeChanged", function() Board:Fit() end)
    f:SetScript("OnShow", function()
        Yatzy:PlayUISound("IG_CHARACTER_INFO_OPEN")
        Board:Fit()
        if Board.g then Board:Refresh() end
    end)
    f:SetScript("OnHide", function()
        Yatzy:PlayUISound("IG_CHARACTER_INFO_CLOSE")
        Board:StopAnimations()
        Board:Deselect()
    end)
    -- Fading follows the main window's setting; this window keeps the fade going on its own
    -- while the main window is closed
    Yatzy.UI:SetupFade(f)
    f:HookScript("OnUpdate", function(_, elapsed)
        if not (Yatzy.mainWindow and Yatzy.mainWindow:IsShown()) then Yatzy.UI:FadeStep(elapsed) end
    end)
    f:Hide()
    self.window = f
    self:ApplyEscape()

    -- Whole-window size: Ctrl + mouse wheel over the title bar (its own, saved), as in Yatzy
    f:SetScale(saved.scale or 1)
    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", function(_, delta)
        if IsControlKeyDown and IsControlKeyDown() then
            Yatzy.UI:SetWindowScale(Yatzy.UI:WindowScale("bg") + delta * 0.05, false, "bg")
        end
    end)
    Yatzy.UI.Tooltip(bar, "Backgammon", "Drag to move. Ctrl + mouse wheel to make the window smaller or bigger.")
    self:Fit()
end

-- Escape closes this window too (unless turned off in Settings)
function Board:ApplyEscape()
    local name = "YatzyBGWindow"
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == name then table.remove(UISpecialFrames, i) end
    end
    if Yatzy.db.options.escCloses ~= false then tinsert(UISpecialFrames, name) end
end

-- Scale the board so it fills the window
function Board:Fit()
    local w, h = self.body:GetWidth(), self.body:GetHeight()
    if not w or w <= 0 or not h or h <= 0 then return end
    local s = math.min(w / CONTENT_W, h / CONTENT_H, 1.8)
    self.content:SetScale(math.max(0.3, s))
    Style.UpdateThinLines()
end

---------------------------------------------------------------------------
-- The board
---------------------------------------------------------------------------

local function rect(parent, layer, sub, x, y, w, h)
    local t = parent:CreateTexture(nil, layer, nil, sub or 0)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    t:SetSize(w, h)
    return t
end

local function createDie(parent, index)
    local die = CreateFrame("Button", nil, parent)
    die:SetSize(DIE_LINE, DIE_LINE)
    die.index = index
    die.shadow = die:CreateTexture(nil, "BACKGROUND")
    die.shadow:SetTexture(Style.TEX.shadow)
    die.glow = die:CreateTexture(nil, "BACKGROUND", nil, 1)     -- lights up in the row
    die.glow:SetTexture(Style.TEX.ui.dieGlow)
    die.glow:SetPoint("CENTER")
    die.glow:SetBlendMode("ADD")
    die.face = die:CreateTexture(nil, "BORDER")
    die.face:SetTexture(Style.TEX.ui.dice[(index - 1) % #Style.TEX.ui.dice + 1])
    die.face:SetPoint("CENTER")
    die.pips = {}
    for k = 1, 9 do
        local t = die:CreateTexture(nil, "ARTWORK")
        t:SetTexture(Style.TEX.ui.pip)
        die.pips[k] = t
    end
    -- dice-first play: click a die to make it the one you move with
    die:SetScript("OnClick", function(self) Board:OnDieClick(self.index) end)
    die:Hide()
    return die
end

-- Size, value, rotation (degrees), height in the air (0 = lying), glow (0..1)
local function poseDie(die, size, value, angle, height, glow)
    angle, height = angle or 0, height or 0
    die:SetSize(size, size)
    local s = size * (1 + 0.25 * height)               -- closer to the camera = bigger
    local a = math.rad(angle)
    local cosA, sinA = math.cos(a), math.sin(a)
    die.face:SetSize(s * 64 / 44, s * 64 / 44)
    die.face:SetRotation(a)
    die.shadow:ClearAllPoints()
    die.shadow:SetPoint("CENTER", die, "CENTER", 2 + height * 12, -3 - height * 14)
    die.shadow:SetSize(s * 1.15, s * 1.15)
    die.shadow:SetRotation(a)
    die.shadow:SetAlpha(1 - 0.45 * height)
    die.glow:SetSize(s * 2.05, s * 2.05)
    die.glow:SetRotation(a)
    die.glow:SetAlpha(glow or 0)
    die.glow:SetShown((glow or 0) > 0)
    local unit, pip = s * 0.25, s * 0.2 * 16 / 14
    local show = {}
    for _, k in ipairs(PIPS[value] or {}) do show[k] = true end
    for k = 1, 9 do
        local col, row = (k - 1) % 3 - 1, 1 - math.floor((k - 1) / 3)
        local x, y = col * unit, row * unit
        local t = die.pips[k]
        t:SetSize(pip, pip)
        t:ClearAllPoints()
        t:SetPoint("CENTER", die, "CENTER", x * cosA - y * sinA, x * sinA + y * cosA)
        t:SetShown(show[k] == true)
    end
end

function Board:CreateBoard(content)
    local b = CreateFrame("Frame", nil, content)
    b:SetSize(BOARD_W, BOARD_H)
    b:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -CTRL_H)       -- the status line is above the board
    b:EnableMouse(true)
    self.board = b

    -- Wooden case with a bronze edge
    Style.Fill(b, Style.TEX.tableWood, { 0.80, 0.64, 0.50 })
    Style.MetalBorder(b, 3)
    -- The two playing fields: dark leather, a little shade towards the edges
    for _, x in ipairs({ LEFT_X, RIGHT_X }) do
        local field = CreateFrame("Frame", nil, b)
        field:SetPoint("TOPLEFT", x, -TOP_Y)
        field:SetSize(6 * PW, PH * 2 + MID)
        Style.Fill(field, Style.TEX.leather, { 0.36, 0.29, 0.24 })
        for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do Style.EdgeShade(field, side, 14, 0.55) end
    end
    -- The bar: a darker wooden strip with a seam in the middle
    local barShade = rect(b, "BORDER", 3, BAR_X, 0, BARW, BOARD_H)
    barShade:SetColorTexture(0, 0, 0, 0.22)
    for _, x in ipairs({ BAR_X, RIGHT_X - 1 }) do
        local line = rect(b, "BORDER", 4, x, TOP_Y, 1, PH * 2 + MID)
        line:SetColorTexture(0.05, 0.03, 0.01, 0.8)
    end
    -- The tray for borne-off checkers: red felt in a metal rim, split in two halves
    local tray = CreateFrame("Frame", nil, b)
    tray:SetPoint("TOPLEFT", TRAY_X, -TOP_Y)
    tray:SetSize(TRAYW, PH * 2 + MID)
    Style.Fill(tray, Style.TEX.leather, { 0.46, 0.10, 0.06 })     -- red lacquered leather
    Style.EdgeShade(tray, "TOP", 18, 0.6)
    Style.EdgeShade(tray, "LEFT", 8, 0.5)
    Style.MetalBorder(tray, 2)
    local split = rect(tray, "ARTWORK", 0, 2, PH + MID / 2 - 1, TRAYW - 4, 3)
    Style.Tile(split, Style.TEX.metal, Style.BRONZE)
    self.tray = tray

    -- Points (alternating red and ivory) and their gold "you can go here" light,
    -- on their own layer above the leather fields
    local pts = CreateFrame("Frame", nil, b)
    pts:SetAllPoints()
    pts:SetFrameLevel(b:GetFrameLevel() + 3)
    self.points, self.pointGlow = {}, {}
    for r = 1, 24 do
        local x, top = pointX(r) - PW / 2, isTop(r)
        local y = top and TOP_Y or BOTTOM - PH + 6
        local t = rect(pts, "ARTWORK", 0, x + 1, y, PW - 2, PH - 6)
        t:SetTexture(r % 2 == 1 and Style.TEX.ui.pointRed or Style.TEX.ui.pointIvory)
        if top then t:SetTexCoord(0, 1, 0, 1) else t:SetTexCoord(0, 1, 1, 0) end
        self.points[r] = t
        local glow = pts:CreateTexture(nil, "ARTWORK", nil, 2)
        glow:SetAllPoints(t)
        glow:SetTexture(Style.TEX.ui.pointIvory)
        if top then glow:SetTexCoord(0, 1, 0, 1) else glow:SetTexCoord(0, 1, 1, 0) end
        glow:SetBlendMode("ADD")
        glow:SetVertexColor(1, 0.78, 0.3, 0.45)
        glow:Hide()
        self.pointGlow[r] = glow
    end
    local trayGlow = tray:CreateTexture(nil, "ARTWORK", nil, 3)
    trayGlow:SetPoint("TOPLEFT", 2, -(PH + MID / 2 + 2))
    trayGlow:SetPoint("BOTTOMRIGHT", -2, 2)
    trayGlow:SetColorTexture(1, 0.8, 0.35, 0.3)
    trayGlow:SetBlendMode("ADD")
    trayGlow:Hide()
    self.trayGlow = trayGlow

    -- Checkers live on a layer above the points
    local layer = CreateFrame("Frame", nil, b)
    layer:SetAllPoints()
    layer:SetFrameLevel(b:GetFrameLevel() + 5)
    self.layer = layer
    self.pool = {}
    for i = 1, 30 do
        local shadow = layer:CreateTexture(nil, "BACKGROUND")
        shadow:SetTexture(Style.TEX.shadow)
        shadow:SetSize(C * 1.12, C * 1.12)
        local glow = layer:CreateTexture(nil, "BORDER")
        glow:SetTexture(Style.TEX.ui.softGlow)
        glow:SetBlendMode("ADD")
        glow:SetSize(C * 1.7, C * 1.7)
        local tex = layer:CreateTexture(nil, "ARTWORK")
        tex:SetSize(CHECKER_TEX, CHECKER_TEX)
        self.pool[i] = { tex = tex, shadow = shadow, glow = glow }
    end
    -- Gold light where the selected checker would land
    self.spots = {}
    for i = 1, 16 do
        local s = layer:CreateTexture(nil, "BORDER", nil, 1)
        s:SetTexture(Style.TEX.ui.softGlow)
        s:SetBlendMode("ADD")
        s:SetVertexColor(1, 0.82, 0.38, 1)
        s:SetSize(C * 1.6, C * 1.6)
        local ring = layer:CreateTexture(nil, "ARTWORK", nil, 2)
        ring:SetTexture(Style.TEX.ui.checkerIvory)
        ring:SetBlendMode("ADD")
        ring:SetVertexColor(1, 0.8, 0.35, 0.45)
        ring:SetSize(CHECKER_TEX, CHECKER_TEX)
        self.spots[i] = { glow = s, ring = ring }
    end
    self.slices = {}
    for i = 1, 30 do
        local s = layer:CreateTexture(nil, "ARTWORK", nil, 1)
        s:SetSize(TRAYW - 12, SLICE_H)
        self.slices[i] = s
    end
    self.counts = {}
    for i = 1, 28 do
        local fs = layer:CreateFontString(nil, "OVERLAY")
        Style.Font(fs, "display", 12, nil, "OUTLINE")
        self.counts[i] = fs
    end

    -- Dice: up to four (doubles)
    local diceLayer = CreateFrame("Frame", nil, b)
    diceLayer:SetAllPoints()
    diceLayer:SetFrameLevel(b:GetFrameLevel() + 8)
    self.dice = {}
    for i = 1, 4 do self.dice[i] = createDie(diceLayer, i) end
    -- the two bonus dice of doubles slide out from UNDER the first two
    for i = 3, 4 do self.dice[i]:SetFrameLevel(diceLayer:GetFrameLevel() + 1) end
    for i = 1, 2 do self.dice[i]:SetFrameLevel(diceLayer:GetFrameLevel() + 3) end

    -- Roll button, lying big on my half of the board
    local roll = Style.Button(b, "Roll dice", 170, 44)
    roll:SetFrameLevel(b:GetFrameLevel() + 12)
    roll:SetPoint("CENTER", b, "TOPLEFT", RIGHT_X + 3 * PW, -CENTER_Y)
    roll:SetScript("OnClick", function() Play():Roll() end)
    roll:Hide()
    self.rollButton = roll

    -- Done and Undo live on the board too, right under the dice, so everything you click
    -- during a game is in the middle of the board (Undo is a small square icon button)
    local done = Style.Button(b, "", 48, 48)              -- big square button with a check mark
    done:SetFrameLevel(b:GetFrameLevel() + 12)
    local doneIcon = done:CreateTexture(nil, "OVERLAY")
    doneIcon:SetTexture(Style.TEX.ui.check)
    doneIcon:SetSize(32, 32)
    doneIcon:SetPoint("CENTER", 0, 1)
    done.icon = doneIcon
    done:SetScript("OnDisable", function() done.face:SetDesaturated(true); doneIcon:SetDesaturated(true); doneIcon:SetAlpha(0.4) end)
    done:SetScript("OnEnable", function() done.face:SetDesaturated(false); doneIcon:SetDesaturated(false); doneIcon:SetAlpha(1) end)
    done:SetScript("OnClick", function() Play():Done() end)
    Yatzy.UI.Tooltip(done, "Done", "End your turn. Until then you can undo your moves.")
    done:Hide()
    self.doneButton = done
    local undo = Style.Button(b, "", 30, 30, "secondary")
    undo:SetFrameLevel(b:GetFrameLevel() + 12)
    local undoIcon = undo:CreateTexture(nil, "OVERLAY")
    undoIcon:SetTexture(Style.TEX.ui.undo)
    undoIcon:SetSize(18, 18)
    undoIcon:SetPoint("CENTER")
    undo.icon = undoIcon
    undo:SetScript("OnDisable", function() undo.face:SetDesaturated(true); undoIcon:SetDesaturated(true); undoIcon:SetAlpha(0.5) end)
    undo:SetScript("OnEnable", function() undo.face:SetDesaturated(false); undoIcon:SetDesaturated(false); undoIcon:SetAlpha(1) end)
    undo:SetScript("OnClick", function() Play():Undo() end)
    Yatzy.UI.Tooltip(undo, "Undo", "Take back all your moves this turn.")
    undo:Hide()
    self.undoButton = undo
    -- Soft pulsing light around Done when it's the only thing left to do
    local glowFrame = CreateFrame("Frame", nil, b)
    glowFrame:SetAllPoints()
    glowFrame:SetFrameLevel(b:GetFrameLevel() + 11)
    local glow = glowFrame:CreateTexture(nil, "ARTWORK")
    glow:SetTexture(Style.TEX.ui.softGlow)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.8, 0.35)
    glow:SetPoint("TOPLEFT", done, "TOPLEFT", -22, 22)
    glow:SetPoint("BOTTOMRIGHT", done, "BOTTOMRIGHT", 22, -22)
    glow:Hide()
    self.doneGlow = glow

    -- "Auto finish": shown once the checkers have passed each other. When both players have
    -- ticked it, the computer plays the rest of the game for both, a bit faster.
    local auto = CreateFrame("CheckButton", nil, b, "UICheckButtonTemplate")
    auto:SetSize(22, 22)
    auto:SetFrameLevel(b:GetFrameLevel() + 12)
    local plate = auto:CreateTexture(nil, "BACKGROUND")
    plate:SetColorTexture(0.08, 0.05, 0.03, 0.62)
    auto.text = auto:CreateFontString(nil, "OVERLAY")
    Style.Font(auto.text, "display", 11, Style.TEXT)
    auto.text:SetPoint("LEFT", auto, "RIGHT", -1, 0)
    auto.text:SetText("Auto finish")
    plate:SetPoint("TOPLEFT", auto, "TOPLEFT", 1, -1)
    plate:SetPoint("BOTTOMRIGHT", auto.text, "BOTTOMRIGHT", 6, -4)
    auto:SetScript("OnClick", function(self) Play():SetAuto(Board.g, self:GetChecked() and true or false) end)
    Yatzy.UI.Tooltip(auto, "Auto finish",
        "Your checkers have passed each other, so nothing can be hit any more. When both players have ticked this, the computer plays the rest of the game for both of you, a bit faster.")
    auto:Hide()
    self.autoBox = auto

    -- The checker that flies (moves, drags), above everything else
    local fly = CreateFrame("Frame", nil, b)
    fly:SetAllPoints()
    fly:SetFrameLevel(b:GetFrameLevel() + 20)
    self.flyShadow = fly:CreateTexture(nil, "BACKGROUND")
    self.flyShadow:SetTexture(Style.TEX.shadow)
    self.flyTex = fly:CreateTexture(nil, "ARTWORK")
    self.flyShadow:Hide(); self.flyTex:Hide()

    b:SetScript("OnMouseDown", function(_, button) Board:OnMouseDown(button) end)
    b:SetScript("OnMouseUp", function(_, button) Board:OnMouseUp(button) end)
    b:SetScript("OnUpdate", function(_, elapsed) Board:OnUpdate(elapsed) end)
end

function Board:CreateControls(content)
    -- the opponent's picture, left of the status line
    local portrait = Yatzy.Portrait:Create(content, 36)
    portrait:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -5)
    self.portrait = portrait

    local status = content:CreateFontString(nil, "OVERLAY")
    Style.Font(status, "display", 12, Style.TEXT)
    status:SetPoint("TOPLEFT", content, "TOPLEFT", 46, -8)
    status:SetPoint("RIGHT", content, "RIGHT", -84, 0)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(false)
    self.status = status
    local sub = content:CreateFontString(nil, "OVERLAY")
    Style.Font(sub, "display", 10, DIM)
    sub:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -5)
    sub:SetPoint("RIGHT", status, "RIGHT")
    sub:SetJustifyH("LEFT")
    sub:SetWordWrap(false)
    self.sub = sub

    -- Fast games: poke the other player (on their turn, where Done sits on yours)
    local poke = Style.Button(content, "Poke", 70, 22, "secondary")
    poke:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -11)
    poke:SetScript("OnClick", function()
        if Board.g then Yatzy.Fast:Poke(Board.g); Board:RefreshControls() end
    end)
    Yatzy.UI.Tooltip(poke, "Poke", "Remind the other player that it's their turn (once per turn).")
    poke:Hide()
    self.pokeButton = poke
end

-- Game over: a leather panel over the middle of the board
function Board:CreateOverPanel(content)
    local p = CreateFrame("Frame", nil, content)
    p:SetSize(270, 132)
    p:SetPoint("CENTER", self.board, "CENTER")
    p:SetFrameLevel(self.board:GetFrameLevel() + 30)
    p:EnableMouse(true)
    Style.LeatherPanel(p, { color = { 0.22, 0.17, 0.14 }, border = 2, stitch = 5 })
    p.title = p:CreateFontString(nil, "OVERLAY")
    Style.Font(p.title, "title", 30, GOLD)
    p.title:SetShadowOffset(2, -2)
    p.title:SetPoint("TOP", 0, -16)
    p.sub = p:CreateFontString(nil, "OVERLAY")
    Style.Font(p.sub, "display", 11, Style.TEXT)
    p.sub:SetPoint("TOP", p.title, "BOTTOM", 0, -6)
    -- Replay: a new round with the same players. Against the computer it starts at once; with a
    -- guild member they get an invitation. (A full list is handled by Yatzy.UI:ReplayGame.)
    p.again = Style.Button(p, "Replay", 130, 26)
    p.again:SetPoint("BOTTOMLEFT", 16, 16)
    p.again:SetScript("OnClick", function() Yatzy.UI:ReplayGame(Board.g) end)
    p.menu = Style.Button(p, "Main menu", 100, 26, "secondary")
    p.menu:SetPoint("BOTTOMRIGHT", -16, 16)
    p.menu:SetScript("OnClick", function()
        Board.window:Hide()
        Yatzy.UI:ShowStart()
        if Yatzy.mainWindow and not Yatzy.mainWindow:IsShown() then Yatzy.mainWindow:Show() end
    end)
    p:Hide()
    self.overPanel = p
end

---------------------------------------------------------------------------
-- Showing a game
---------------------------------------------------------------------------

function Board:IsShown()
    return self.window ~= nil and self.window:IsShown()
end

function Board:Show(g)
    self:CreateWindow()
    if self.g ~= g then
        self:StopAnimations()
        self:Deselect()
        self.overPanel:Hide()
    end
    self.g = g
    if not self.window:IsShown() then self.window:Show() end
    if self.window.Raise then self.window:Raise() end
    self:Refresh()
end

function Board:Close()
    self:StopAnimations()
    self.g = nil
    if self.window then self.window:Hide() end
end

-- An animation is running: the board doesn't take clicks
function Board:Busy()
    return self.flight ~= nil or self.rolling ~= nil
end

function Board:StopAnimations()
    local f, r = self.flight, self.rolling
    self.flight, self.rolling, self.hide = nil, nil, nil
    self.hitStay, self.hideBar = nil, nil
    if r and self.board then self:RefreshDice() end
    if self.flyTex then self.flyTex:Hide(); self.flyShadow:Hide() end
    self.drag = nil
    -- finish what was waiting for the animation (the move itself is already made)
    self.stopping = true
    if f and f.done then f.done() end
    if r and r.done then r.done() end
    self.stopping = nil
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

function Board:Refresh()
    local g = self.g
    if not g or not self.board then return end
    local me, them = self:Me(), self:Them()
    local b = g.board
    local used, sliceUsed, countUsed = 0, 0, 0
    local hide = self.hide

    -- What lights up: in the normal way, the checkers that can move (faintly) and, once one
    -- is selected, where it can go. Dice-first: the checkers that can move with the
    -- primary die, and where each would land.
    local movable = {}
    local targets = self.targets
    self.primaryMoves = nil
    local myMove = Play():CanAct(g, true) and g.dice and not self.rolling and not self:NeedsOpening(g)
    if myMove then
        local pv = self:DiceFirst() and self:PrimaryValue()
        if pv and not self.selected then
            self.primaryMoves, targets = {}, {}
            for _, m in ipairs((BG.Legal(g))) do
                if m.die == pv then
                    self.primaryMoves[m.from] = m.to
                    movable[m.from] = 0.9
                    targets[m.to] = true
                end
            end
        else
            for _, m in ipairs((BG.Legal(g))) do movable[m.from] = 0.45 end
        end
    end
    -- New lights fade in (and a selected checker grows) quickly
    local keyParts = { tostring(self.selected) }
    for pos in pairs(targets or {}) do keyParts[#keyParts + 1] = pos end
    for pos in pairs(movable) do keyParts[#keyParts + 1] = "m" .. pos end
    table.sort(keyParts, function(a, b) return tostring(a) < tostring(b) end)
    local hlKey = table.concat(keyParts, ",")
    if hlKey ~= self.hlKey then self.hlKey, self.selectT = hlKey, 0 end
    local p = math.min(1, (self.selectT or SELECT_TIME) / SELECT_TIME)
    local fade = p * (2 - p)                                  -- ease out

    local function put(mine, x, y, glowAlpha, lifted)
        used = used + 1
        local c = self.pool[used]
        if not c then return end
        c.tex:SetTexture(checkerTex(mine))
        local lift = lifted and fade or 0
        local size = CHECKER_TEX * (1 + 0.12 * lift)
        c.tex:SetSize(size, size)
        at(c.tex, x, y + 0.6 - 2 * lift)
        at(c.shadow, x + 2 + 2 * lift, y + 3 + 3 * lift)
        c.tex:Show(); c.shadow:Show()
        if glowAlpha then
            at(c.glow, x, y)
            c.glow:SetVertexColor(1, 0.8, 0.35, glowAlpha * fade)
            c.glow:Show()
        else
            c.glow:Hide()
        end
    end

    local function stack(seat, pos, xyFor)
        local n = BG.Count(b, seat, pos)
        if n == 0 then return end
        local mine = seat == me
        local shown = n
        if hide and hide.seat == seat and hide.pos == pos then shown = shown - 1 end
        local hide2 = self.hideBar          -- a hit checker still on its way to the bar
        if hide2 and hide2.seat == seat and hide2.pos == pos then shown = shown - 1 end
        for i = 1, shown do
            local x, y = xyFor(i, n)
            local glow, lifted
            if i == shown and mine then
                if self.selected == pos then glow, lifted = 1, true
                elseif movable[pos] and not self.selected then glow = movable[pos] end
            end
            put(mine, x, y, glow, lifted)
        end
        -- more than 5: the number on the outermost checker
        if n > 5 and shown > 0 then
            countUsed = countUsed + 1
            local fs = self.counts[countUsed]
            local x, y = xyFor(shown, n)
            at(fs, x, y)
            fs:SetText(n)
            fs:SetTextColor(mine and 1 or 0.25, mine and 0.9 or 0.16, mine and 0.75 or 0.08)
            fs:Show()
        end
    end

    for pos = 1, 24 do
        local r = self:Rel(pos)
        for _, seat in ipairs({ me, them }) do
            stack(seat, pos, function(i, n) return checkerXY(r, i, n) end)
        end
    end
    stack(me, BG.BAR[me], function(i, n) return barXY(true, i, n) end)
    stack(them, BG.BAR[them], function(i, n) return barXY(false, i, n) end)
    -- A hit checker stays on its point until the hitting checker has landed
    local hs = self.hitStay
    if hs then
        local x, y = checkerXY(self:Rel(hs.pos), 1, 1)
        put(hs.seat == me, x, y)
    end
    for i = used + 1, #self.pool do
        local c = self.pool[i]
        c.tex:Hide(); c.shadow:Hide(); c.glow:Hide()
    end
    for i = countUsed + 1, #self.counts do self.counts[i]:Hide() end

    -- Borne off: thin slices in the tray
    for _, seat in ipairs({ me, them }) do
        local n = b.off[seat]
        if hide and hide.seat == seat and hide.pos == BG.OFF[seat] then n = n - 1 end
        for i = 1, n do
            sliceUsed = sliceUsed + 1
            local s = self.slices[sliceUsed]
            local x, y = offXY(seat == me, i)
            at(s, x, y)
            if seat == me then s:SetColorTexture(0.55, 0.12, 0.07) else s:SetColorTexture(0.86, 0.78, 0.60) end
            s:Show()
        end
    end
    for i = sliceUsed + 1, #self.slices do self.slices[i]:Hide() end

    -- Where the selected checker can go: the point lights up, and a gold ghost checker
    -- shows the spot it would land on
    for r = 1, 24 do self.pointGlow[r]:Hide() end
    self.trayGlow:Hide()
    local spot = 0
    if targets then
        for pos in pairs(targets) do
            local x, y
            if pos == BG.OFF[me] then
                self.trayGlow:SetAlpha(fade)
                self.trayGlow:Show()
                x, y = offXY(true, b.off[me] + 1)
            elseif pos >= 1 and pos <= 24 then
                local r = self:Rel(pos)
                self.pointGlow[r]:SetAlpha(fade)
                self.pointGlow[r]:Show()
                local n = BG.Count(b, me, pos) + 1
                x, y = checkerXY(r, n, n)
            end
            spot = spot + 1
            local s = self.spots[spot]
            if s and x and pos ~= BG.OFF[me] then
                at(s.glow, x, y); at(s.ring, x, y)
                s.glow:SetAlpha(fade); s.ring:SetAlpha(fade)
                s.glow:Show(); s.ring:Show()
            elseif s then
                s.glow:Hide(); s.ring:Hide()
            end
        end
    end
    for i = spot + 1, #self.spots do self.spots[i].glow:Hide(); self.spots[i].ring:Hide() end

    self:RefreshDice()
    self:RefreshControls()
end

-- Where the dice lie once they've settled: a row of two in the middle of the half, or 2x2
-- for doubles (the first two on top, the bonus dice below)
-- `sizes` (two dice only): how big each die is, so a bigger die gets more room.
-- Also returns half the width of the whole group (for the buttons beside it).
local function lineSlots(n, mine, sizes)
    local cx = (mine and RIGHT_X or LEFT_X) + 3 * PW
    local cy = CENTER_Y
    if n == 4 then
        local s = DIE_DOUBLE + 6
        return { { cx - s / 2, cy - s / 2 }, { cx + s / 2, cy - s / 2 },
                 { cx - s / 2, cy + s / 2 }, { cx + s / 2, cy + s / 2 } }, s / 2 + DIE_DOUBLE / 2
    end
    local s1, s2 = sizes and sizes[1] or DIE_LINE, sizes and sizes[2] or DIE_LINE
    local w = s1 + s2 + 14
    return { { cx - w / 2 + s1 / 2, cy }, { cx + w / 2 - s2 / 2, cy } }, w / 2
end

-- How big the dice lie. Dice-first play: the die I move with is much bigger and the other
-- one is plain (no light); otherwise both are alike. Returns sizes, primary index (or nil).
function Board:DiePlan(g, values, usedFlags, mine)
    local n = #values
    local base = n == 4 and DIE_DOUBLE or DIE_LINE
    local sizes, primary = {}, nil
    for i = 1, n do sizes[i] = base end
    if n == 2 and mine and self:DiceFirst() and g.status == "active" then
        local pv = self:PrimaryValue()
        for i, v in ipairs(values) do
            if not primary and v == pv and not (usedFlags and usedFlags[i]) then primary = i end
        end
        if primary then
            for i = 1, 2 do sizes[i] = i == primary and DIE_PRIMARY or DIE_SECOND end
        end
    end
    return sizes, primary
end

---------------------------------------------------------------------------
-- Dice-first play (setting): one die is "primary"; the board shows what it can do,
-- and a click on a lit checker moves it by that die. Click a die to switch.
---------------------------------------------------------------------------

function Board:DiceFirst()
    return Yatzy.db.options.bgDiceFirst == true
end

-- The value of the primary die: the one you picked if it can still be used, otherwise
-- the highest die that can be used now
function Board:PrimaryValue()
    local g = self.g
    if not g or not g.dice then return nil end
    local left = BG.DiceLeft(g)
    if #left == 0 then return nil end
    local legal = BG.Legal(g)
    local function usable(v)
        for _, m in ipairs(legal) do if m.die == v then return true end end
        return false
    end
    local v = self.primaryValue
    local still = false
    for _, d in ipairs(left) do if d == v then still = true end end
    if still and usable(v) then return v end
    table.sort(left, function(a, b) return a > b end)
    for _, d in ipairs(left) do if usable(d) then return d end end
    return left[1]
end

function Board:OnDieClick(index)
    local g = self.g
    if not g or not self:DiceFirst() or not Play():CanAct(g) or not g.dice then return end
    local values, usedFlags = self:DiceState()
    if not values or usedFlags[index] then return end
    self.primaryValue = values[index]
    self:Deselect()
    Yatzy.Sound:Play("hold")
    self:Refresh()
end

-- This turn's dice and which of them are used up
function Board:DiceState()
    local g = self.g
    if not g.dice then return nil end
    local values = BG.DiceSteps(g.dice)              -- doubles: four dice
    local usedFlags = {}
    for _, m in ipairs(g.moves or {}) do
        for i, v in ipairs(values) do
            if not usedFlags[i] and v == m.die then usedFlags[i] = true; break end
        end
    end
    return values, usedFlags
end

-- The dice at rest: my dice on my (right) half, the opponent's on theirs, lit up.
-- Used dice are dimmed; in dice-first play the primary die is bigger and brighter.
-- The very first turn of a game comes with the opening roll already decided (so both
-- copies agree), but the player who starts still throws the dice by hand.
function Board:NeedsOpening(g)
    return g.status == "active" and g.turn == 1 and g.dice ~= nil and not g.openRolled
        and #(g.moves or {}) == 0 and Games():IsMyTurn(g)
end

function Board:RefreshDice()
    local g = self.g
    if self.rolling then return end                 -- the throw draws them itself
    local me = self:Me()
    for i = 1, 4 do self.dice[i]:Hide() end
    if self:NeedsOpening(g) then return end         -- not thrown yet
    local values, usedFlags, mine, glow
    if g.status == "active" and g.dice then
        values, usedFlags = self:DiceState()
        mine = BG.CurrentPlayer(g) == me
        glow = mine and 0.55 or 0.4
    elseif g.status == "active" and g.lastDice and BG.CurrentPlayer(g) == me then
        -- before I roll: what the opponent rolled last, dimmed on their side
        values, mine = { g.lastDice[1], g.lastDice[2] }, false
        usedFlags = { true, true }
    end
    if not values then return end
    local n = #values
    local sizes, primary = self:DiePlan(g, values, usedFlags, mine)
    local slots = lineSlots(n, mine, sizes)
    local firstMode = mine and self:DiceFirst() and primary ~= nil
    for i = 1, n do
        local d = self.dice[i]
        local used = usedFlags and usedFlags[i]
        local size = sizes[i]
        local light = (not used) and glow or 0
        if firstMode then light = i == primary and 1 or 0 end   -- only the die to use is lit
        poseDie(d, size, values[i], 0, 0, light)
        at(d, slots[i][1], slots[i][2])
        d:SetAlpha(used and 0.35 or 1)
        d:EnableMouse(self:DiceFirst() and mine and not used and n == 2)
        d:Show()
    end
end

function Board:RefreshControls()
    local g = self.g
    local Games = Games()
    local me, them = self:Me(), self:Them()
    local themName = Games:PlayerName(g, them)
    local canAct = Play():CanAct(g)
    local status, sub = "", ""
    self.rollButton:Hide()
    self.doneButton:Hide(); self.undoButton:Hide(); self.doneGlow:Hide(); self.pokeButton:Hide()

    if g.status ~= "active" then
        local won = g.winner == me
        status = won and "You won!" or (themName .. " won.")
        if g.resigned then status = status .. (g.resigned == me and " (you gave up)" or " (they gave up)") end
        self.overPanel.title:SetText(won and "You won!" or (themName .. " won"))
        local op = self.overPanel
        if self.overFull and not Games:CanCreate() then
            op.sub:SetWidth(238)
            op.sub:SetText(Games:FullText())
            op:SetHeight(104 + (op.sub:GetStringHeight() or 30))
        else
            self.overFull = nil
            op.sub:SetWidth(0)
            op.sub:SetText("Backgammon vs " .. themName)
            op:SetHeight(132)
        end
        self.overPanel.again:Show()
        self.overPanel.again:SetText(Games:ReplayTarget(g) and "Go to replay" or "Replay")
        if not self:Busy() then self.overPanel:Show() end
    else
        self.overPanel:Hide()
        local myTurn = Games:IsMyTurn(g)
        local auto = Play():AutoRunning(g)             -- Auto finish is playing for me
        if myTurn then
            local opening = self:NeedsOpening(g)
            if g.dice and not self.rolling and not opening then
                self.doneButton:Show(); self.undoButton:Show()
                self.undoButton:SetEnabled(canAct and BG.CanUndo(g))
                self.doneButton:SetEnabled(canAct and BG.CanFinish(g))
            end
            if auto then
                status = "Auto finish is playing for you..."
            elseif opening then
                status = "You start! Roll the dice."
                self.rollButton:SetShown(not self.rolling)
                self.rollButton:SetEnabled(canAct)
            elseif not g.dice then
                status = "Your turn: roll the dice."
                self.rollButton:SetShown(not self.rolling)
                self.rollButton:SetEnabled(canAct)
            elseif self.rolling then
                status = "Rolling..."
            else
                local legal = BG.Legal(g)
                local dice = g.dice[1] .. "-" .. g.dice[2]
                if #legal > 0 then
                    if self.selected then
                        status = "Click a lit point, or drag there."
                    elseif self.primaryMoves then
                        status = ("Click a lit checker to move it %d."):format(self:PrimaryValue())
                    elseif g.turn == 1 and #g.moves == 0 then
                        status = ("You start (opening roll %d-%d)."):format(g.dice[me], g.dice[them])
                    else
                        status = ("You rolled %s. Move a checker."):format(dice)
                    end
                elseif #g.moves == 0 then
                    status = "No possible move."
                    if canAct then self.doneGlow:Show() end
                else
                    status = "Press Done, or Undo."
                    if canAct then self.doneGlow:Show() end
                end
            end
        else
            if g.turn == 1 and g.dice and #g.moves == 0 and not self.flight then
                status = ("%s starts (opening roll %d-%d)."):format(themName, g.dice[them], g.dice[me])
            elseif g.kind == "computer" then
                status = themName .. " is playing..."
            elseif g.dice then
                status = ("%s is moving (%d-%d)."):format(themName, g.dice[1], g.dice[2])
            else
                status = themName .. "'s turn."
            end
            -- fast games: poke the player whose turn it is (once per turn)
            if Yatzy.Fast:IsFast(g) then
                self.pokeButton:Show()
                self.pokeButton:SetEnabled(Yatzy.Fast:CanPoke(g))
            end
        end
    end
    sub = ("Pips:  You %d  ·  %s %d"):format(BG.Pips(g.board, me), themName, BG.Pips(g.board, them))
    local left = g.status == "active" and Yatzy.Fast:TimeLeft(g)
    if left then
        local who = Games:IsMyTurn(g) and "your" or (themName .. "'s")
        sub = sub .. ("     Fast  ·  %s left for %s turn"):format(Yatzy.Fast:Format(left), who)
    end
    -- Auto finish: I've ticked it, the other player hasn't yet
    if g.status == "active" and g.kind == "guild" and not BG.Contact(g.board)
        and g.auto and g.auto[me] and not g.auto[them] then
        sub = sub .. ("     Auto finish: waiting for %s"):format(themName)
    end
    Style.SetText(self.status, status)
    Style.SetText(self.sub, sub)
    Yatzy.Portrait:Set(self.portrait, g, them)
    self:PlaceControls()
end

-- Done and Undo sit right under the dice, in the middle of my half; the Auto finish tick
-- box sits under whichever button is showing (or where the Roll button would be)
function Board:PlaceControls()
    local g = self.g
    local cx = RIGHT_X + 3 * PW
    local y = CENTER_Y + 22 + 14                           -- under the Roll button
    if self.doneButton:IsShown() and g.dice then
        -- the dice are in the middle; Undo is left of them and the big Done button right of them
        local values, used = self:DiceState()
        local sizes = self:DiePlan(g, values, used, true)
        local _, half = lineSlots(#values, true, sizes)
        at(self.undoButton, cx - half - 8 - 15, CENTER_Y)
        at(self.doneButton, cx + half + 8 + 24, CENTER_Y)
        y = CENTER_Y + (#values == 4 and 43 or math.max(sizes[1], sizes[2]) / 2) + 14
    end
    local box = self.autoBox
    local show = g.status == "active" and not BG.Contact(g.board)
        and not (g.kind == "guild" and not g.players)
    box:SetShown(show)
    if show then
        box:SetChecked(g.auto and g.auto[g.me or 1] and true or false)
        local w = 22 + (box.text:GetStringWidth() or 60)
        box:ClearAllPoints()
        box:SetPoint("LEFT", self.board, "TOPLEFT", cx - w / 2, -y)
    end
end

-- Fast games: the time left, every second
function Board:UpdateTimer(g)
    if g == self.g and self:IsShown() then self:RefreshControls() end
end

---------------------------------------------------------------------------
-- Selecting and moving (mouse)
---------------------------------------------------------------------------

function Board:Cursor()
    local cx, cy = GetCursorPosition()
    local s = self.board:GetEffectiveScale()
    local left, top = self.board:GetLeft(), self.board:GetTop()
    if not left or not top then return -1000, -1000 end
    return cx / s - left, top - cy / s
end

function Board:Deselect()
    self.selected, self.targets = nil, nil
end

-- Can I move a checker from this position right now?
function Board:IsSource(pos)
    for _, m in ipairs((BG.Legal(self.g))) do
        if m.from == pos then return true end
    end
    return false
end

function Board:Select(pos)
    self.selected = pos
    self.targets = BG.Reachable(self.g, pos)
end

function Board:OnMouseDown(button)
    local g = self.g
    if not g or button ~= "LeftButton" then
        self:Deselect(); if g then self:Refresh() end
        return
    end
    if not Play():CanAct(g, true) or not g.dice or self:NeedsOpening(g) then return end
    local x, y = self:Cursor()
    local pos = self:KeyToPos(hitTest(x, y))
    -- A lit point: go there
    if pos and self.selected and self.targets and self.targets[pos] then
        local steps = self.targets[pos]
        self:Deselect()
        Play():Move(steps)
        return
    end
    -- Dice-first: a lit checker moves at once by the primary die (you can still drag it);
    -- a lit landing spot that only one checker can reach does the same
    local pm = self.primaryMoves
    if pos and pm and not self.selected then
        local from = pm[pos] and pos
        if not from then
            for f, to in pairs(pm) do
                if to == pos then
                    if from then from = nil; break end      -- two checkers can land there: pick one
                    from = f
                end
            end
        end
        if from then
            if from == pos then
                -- wait to see if it's a drag; a plain click moves it (OnMouseUp)
                self.drag = { from = pos, x = x, y = y, quick = pm[pos] }
                return
            end
            Play():Move({ { from = from, to = pm[from] } })
            return
        end
    end
    if pos and self:IsSource(pos) then
        if self.selected ~= pos then self:Select(pos) end
        -- Bearing off: when the tray is the only place this checker can go, one click is
        -- enough, it goes there by itself
        local count, only = 0, nil
        for to in pairs(self.targets or {}) do count = count + 1; only = to end
        if count == 1 and only == BG.OFF[self:Me()] then
            local steps = self.targets[only]
            self:Deselect()
            Play():Move(steps)
            return
        end
        self.drag = { from = pos, x = x, y = y }
    else
        self:Deselect()
    end
    self:Refresh()
end

function Board:OnMouseUp()
    local d = self.drag
    self.drag = nil
    if not d or not self.g then return end
    if not d.moving then
        -- a plain click: dice-first moves it by the primary die; otherwise it stays selected
        if d.quick then Play():Move({ { from = d.from, to = d.quick } }) end
        return
    end
    self.hide = nil
    self.flyTex:Hide(); self.flyShadow:Hide()
    local x, y = self:Cursor()
    local pos = self:KeyToPos(hitTest(x, y))
    if pos and self.targets and self.targets[pos] and pos ~= d.from then
        local steps = self.targets[pos]
        self:Deselect()
        Play():Move(steps, { x, y })
    else
        self:Refresh()                         -- dropped somewhere else: it goes back
    end
end

---------------------------------------------------------------------------
-- Animations: flying checkers, rolling dice, the drag
---------------------------------------------------------------------------

local function smooth(t) return t * t * (3 - 2 * t) end

function Board:ShowFlyer(mine, x, y, lift)
    local size = CHECKER_TEX * (1 + 0.12 * (lift or 0))
    self.flyTex:SetTexture(checkerTex(mine))
    self.flyTex:SetSize(size, size)
    at(self.flyTex, x, y)
    self.flyShadow:SetSize(C * 1.12, C * 1.12)
    at(self.flyShadow, x + 3 + 8 * (lift or 0), y + 4 + 9 * (lift or 0))
    self.flyTex:Show(); self.flyShadow:Show()
end

-- The flying checker lands now (also when you click the next checker before it has landed)
function Board:FinishFlight()
    local f = self.flight
    if not f then return end
    self.flight, self.hide = nil, nil
    self.flyTex:Hide(); self.flyShadow:Hide()
    Yatzy.Sound:Play("hold")
    self:Refresh()
    if f.done then f.done() end
end

function Board:OnUpdate(elapsed)
    elapsed = elapsed * Play():Speed(self.g)           -- Auto finish: everything moves faster
    -- dragging a checker
    local d = self.drag
    if d then
        local x, y = self:Cursor()
        if not d.moving and math.abs(x - d.x) + math.abs(y - d.y) > 5 then
            d.moving = true
            if self.selected ~= d.from then self:Select(d.from) end     -- (dice-first: show where it can go)
            self.hide = { seat = self:Me(), pos = d.from }
            self:Refresh()
        end
        if d.moving then self:ShowFlyer(true, x, y, 0.6) end
    end

    -- a checker flying to its new place
    local f = self.flight
    if f then
        f.t = f.t + elapsed
        local p = math.min(1, f.t / f.dur)
        local e = smooth(p)
        local lift = math.sin(p * math.pi)
        self:ShowFlyer(f.mine, f.x0 + (f.x1 - f.x0) * e, f.y0 + (f.y1 - f.y0) * e, lift)
        if p >= 1 then self:FinishFlight() end
    end

    -- dice: thrown, lying still, gliding into the row (doubles: two more slide out)
    if self.rolling then self:RollStep(elapsed) end

    -- a selected checker grows and the lights fade in (quickly)
    if self.selectT and self.selectT < SELECT_TIME then
        self.selectT = self.selectT + elapsed
        self:Refresh()
    end

    -- Done glow pulses
    if self.doneGlow and self.doneGlow:IsShown() then
        self.pulse = (self.pulse or 0) + elapsed
        self.doneGlow:SetAlpha(0.35 + 0.3 * math.sin(self.pulse * 4))
    end
end

local function rnd(a, b) return a + math.random() * (b - a) end

-- The dice of this turn are already decided (g.dice). Two dice are thrown onto the
-- player's half: each from its own start, with its own speed, spin and bounces, landing
-- on a free spot. They lie still a moment, then glide into the row in the middle, growing
-- and lighting up. Doubles: only then do the two bonus dice slide out from under them.
function Board:AnimateRoll(g, done)
    if g ~= self.g or not self:IsShown() then if done then done() end; return end
    local mine = BG.CurrentPlayer(g) == self:Me()
    local half = mine and RIGHT_X or LEFT_X
    local x0, x1 = half + 34, half + 6 * PW - 34
    local y0, y1 = TOP_Y + 44, BOTTOM - 44
    local doubles = g.dice[1] == g.dice[2]
    local n = doubles and 4 or 2
    local sizes, primary = self:DiePlan(g, BG.DiceSteps(g.dice), nil, mine)
    local slots = lineSlots(n, mine, sizes)
    local dice = {}
    for i = 1, 2 do
        local tx, ty
        for _ = 1, 40 do
            tx, ty = rnd(x0, x1), rnd(y0, y1)
            local free = true
            for _, o in ipairs(dice) do
                if (o.tx - tx) ^ 2 + (o.ty - ty) ^ 2 < 64 ^ 2 then free = false end
            end
            if free then break end
        end
        local spin = (math.random() < 0.5 and -1 or 1) * rnd(260, 720)
        dice[i] = {
            sx = half + 3 * PW + rnd(-70, 70), sy = mine and (BOTTOM + 26) or (TOP_Y - 26),
            tx = tx, ty = ty, endA = rnd(-40, 40), spin = spin,
            delay = i == 1 and 0 or rnd(0, 0.14), dur = THROW_TIME * rnd(0.8, 1.1),
            bounces = math.random(1, 3), face = math.random(1, 6), nextFace = 0,
            value = g.dice[i], slot = slots[i],
        }
    end
    self.rolling = { phase = "throw", t = 0, dice = dice, mine = mine, done = done,
        doubles = doubles, slots = slots, sizes = sizes, primary = primary, value = g.dice }
    for i = 1, 4 do self.dice[i]:Hide() end
    Yatzy.Sound:Play("roll")
    self:Refresh()
end

function Board:RollStep(elapsed)
    local r = self.rolling
    r.t = r.t + elapsed
    local glow = r.mine and 0.55 or 0.4
    if r.phase == "throw" then
        local landed = true
        for i, d in ipairs(r.dice) do
            local die = self.dice[i]
            local p = math.max(0, math.min(1, (r.t - d.delay) / d.dur))
            if p < 1 then landed = false end
            local e = 1 - (1 - p) ^ 2                               -- fast, then slowing down
            local height = (1 - p) * math.abs(math.sin(p * math.pi * (d.bounces + 0.5)))
            local angle = d.endA - d.spin * (1 - e)
            d.nextFace = d.nextFace - elapsed
            if p < 0.8 and d.nextFace <= 0 then d.face, d.nextFace = math.random(1, 6), 0.07 end
            local face = p >= 0.8 and d.value or d.face
            poseDie(die, DIE_ROLL, face, angle, height, 0)
            at(die, d.sx + (d.tx - d.sx) * e, d.sy + (d.ty - d.sy) * e)
            die:SetAlpha(1)
            die:SetShown(r.t >= d.delay)
        end
        if landed then r.phase, r.t = "rest", 0 end
    elseif r.phase == "rest" then
        if r.t >= REST_TIME then r.phase, r.t = "line", 0 end
    elseif r.phase == "line" then
        local p = math.min(1, r.t / LINE_TIME)
        local e = smooth(p)
        for i, d in ipairs(r.dice) do
            local size = DIE_ROLL + (r.sizes[i] - DIE_ROLL) * e
            local gl = (r.primary and r.primary ~= i) and 0 or glow    -- dice-first: only the big die is lit
            poseDie(self.dice[i], size, d.value, d.endA * (1 - e), 0.25 * math.sin(p * math.pi), gl * e)
            at(self.dice[i], d.tx + (d.slot[1] - d.tx) * e, d.ty + (d.slot[2] - d.ty) * e)
        end
        if p >= 1 then r.phase, r.t = r.doubles and "bonus" or "end", 0 end
    elseif r.phase == "bonus" then
        local p = math.min(1, r.t / BONUS_TIME)
        local e = smooth(p)
        for k = 3, 4 do
            local from, to = r.slots[k - 2], r.slots[k]
            local die = self.dice[k]
            poseDie(die, DIE_DOUBLE, r.value[1], 0, 0, glow * e)
            at(die, from[1] + (to[1] - from[1]) * e, from[2] + (to[2] - from[2]) * e)
            die:SetAlpha(1)
            die:Show()
        end
        if p >= 1 then r.phase = "end" end
    end
    if r.phase == "end" then
        self.rolling = nil
        self:Refresh()
        if r.done then r.done() end
    end
end

-- Play moves one checker step at a time, each flying to its place.
-- `startXY`: where the first checker starts (the drop point after a drag).
function Board:AnimatePath(g, steps, startXY, done)
    -- a checker is still flying (you clicked quickly): it lands at once, then this one goes
    for _ = 1, 20 do
        if not self.flight then break end
        self:FinishFlight()
    end
    local i = 0
    local function nextStep()
        i = i + 1
        local s = steps[i]
        if not s or self.stopping or g ~= self.g or not self:IsShown() then
            -- not on screen any more: make the remaining steps without animation
            if s then
                for k = i, #steps do BG.Play(g, steps[k].from, steps[k].to) end
            end
            self:Refresh()
            if done then done() end
            return
        end
        local seat = BG.CurrentPlayer(g)
        local x0, y0
        if i == 1 and startXY then x0, y0 = startXY[1], startXY[2]
        else x0, y0 = self:TopXY(seat, s.from) end
        local m = BG.Play(g, s.from, s.to)
        if not m then
            self:Refresh()
            if done then done() end
            return
        end
        local x1, y1 = self:TopXY(seat, s.to)
        self.hide = { seat = seat, pos = s.to }
        local after = nextStep
        if m.hit then
            -- The hit checker waits on its point, then flies to the bar once we've landed
            local them = 3 - seat
            local bar = BG.BAR[them]
            self.hitStay = { seat = them, pos = s.to }
            self.hideBar = { seat = them, pos = bar }
            after = function()
                if self.stopping or g ~= self.g or not self:IsShown() then
                    self.hitStay, self.hideBar = nil, nil
                    return nextStep()
                end
                local hx0, hy0 = checkerXY(self:Rel(s.to), 1, 1)
                -- (it lifts off from under the checker that just landed)
                local hx1, hy1 = self:TopXY(them, bar)
                self.hitStay = nil
                self.flight = { t = 0, dur = HIT_TIME, x0 = hx0, y0 = hy0, x1 = hx1, y1 = hy1,
                    mine = them == self:Me(), done = function()
                        self.hideBar = nil
                        self:Refresh()
                        nextStep()
                    end }
                self:Refresh()
            end
        end
        local dist = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
        self.flight = { t = 0, dur = FLY_TIME * math.min(1.4, math.max(0.6, dist / 200)),
            x0 = x0, y0 = y0, x1 = x1, y1 = y1, mine = seat == self:Me(), done = after }
        self:Refresh()
    end
    nextStep()
end
