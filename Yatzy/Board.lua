-- Board.lua
-- The dice table: status line, the 5 dice, the Roll button, the tray for saved dice,
-- the YATZY celebration and the game-over panel.
-- Dice art is rendered from the browser prototype (tools/render-assets.ps1).

local _, Yatzy = ...
local Rules = Yatzy.Rules
local Board = {}
Yatzy.Board = Board

local DIE_SIZE = 64
local TRAY_DIE_SIZE = 40
local TRAY_W, TRAY_H = 262, 56
local ROLL_W = 210                -- Roll button: as tall as the tray, a bit narrower
local BOTTOM_GAP = 16             -- at least this much space between tray and button

-- Breakpoint: on a small table the tray, its dice and the Roll button get smaller.
local COMPACT_BELOW_W, COMPACT_BELOW_H = 470, 270
local SIZES = {
    normal  = { trayH = 56, trayW = 262, minTrayW = 256, die = 40, step = 50, first = 31,
                rollW = 210, minRollW = 140, font = 22, sub = 11, textUp = 6 },
    compact = { trayH = 40, trayW = 192, minTrayW = 192, die = 30, step = 36, first = 24,
                rollW = 160, minRollW = 110, font = 16, sub = 9, textUp = 5 },
}
local ROLL_TIME = 0.85            -- a whole throw takes about this long; each die varies inside it
local LINE_UP_TIME = 0.4          -- dice glide into a row after the 3rd roll ...
local LINE_UP_DELAY = 0.6        -- ... after lying still this long, so you can see what you rolled
-- Dice never land closer than this (centre to centre): a 64 px die turned 45 degrees is
-- 90 px corner to corner, so at this distance two dice can't overlap whichever way they lie.
local MIN_DIE_DISTANCE = 92
-- Both shrink together on a table too small for five full-size dice (see Board:FitDice).
local FULL_DIE_SIZE, SPACING = 64, 92 / 64
local FACE_SCALE = 64 / 44        -- the die art fills 44 of its 64 px (room to rotate without clipping)
local PIP_SCALE = 16 / 14         -- the pip art fills 14 of its 16 px

-- Pip positions on a 3x3 grid (1 = top-left, 9 = bottom-right)
local PIPS = {
    [1] = { 5 }, [2] = { 1, 9 }, [3] = { 1, 5, 9 },
    [4] = { 1, 3, 7, 9 }, [5] = { 1, 3, 5, 7, 9 }, [6] = { 1, 3, 4, 6, 7, 9 },
}

local function rnd(a, b) return a + math.random() * (b - a) end
-- Nearest angle where the die lies upright. Whole turns only: a die turned 90 degrees
-- shows 2, 3 and 6 the other way round, so saved dice looked mixed in the tray.
local function straight(angle) return math.floor((angle or 0) / 360 + 0.5) * 360 end

---------------------------------------------------------------------------
-- One die
---------------------------------------------------------------------------

local function setFace(die, value)
    local show = {}
    for _, k in ipairs(PIPS[value]) do show[k] = true end
    for k = 1, 9 do die.pips[k]:SetShown(show[k] == true) end
end

-- Size, rotation (degrees) and height above the table (0 = lying, 1 = high in the air).
local function poseDie(die, size, angle, height)
    angle, height = angle or 0, height or 0
    die.angle = angle
    die:SetSize(size, size)
    local s = size * (1 + 0.22 * height)          -- closer to the camera = bigger
    local a = math.rad(angle)
    local cosA, sinA = math.cos(a), math.sin(a)

    die.face:SetSize(s * FACE_SCALE, s * FACE_SCALE)
    die.face:SetRotation(a)
    die.glow:SetRotation(a)                       -- the square glow turns with the die

    die.shadow:ClearAllPoints()
    die.shadow:SetPoint("CENTER", die, "CENTER", 3 + height * 14, -4 - height * 16)
    die.shadow:SetSize(s * 1.15, s * 1.15)
    die.shadow:SetRotation(a)
    die.shadow:SetAlpha(1 - 0.45 * height)

    local unit = s * 0.25
    local pip = s * 0.2 * PIP_SCALE
    for k = 1, 9 do
        local col, row = (k - 1) % 3 - 1, 1 - math.floor((k - 1) / 3)
        local x, y = col * unit, row * unit
        local t = die.pips[k]
        t:SetSize(pip, pip)
        t:ClearAllPoints()
        t:SetPoint("CENTER", die, "CENTER", x * cosA - y * sinA, x * sinA + y * cosA)
    end
end

local function createDie(parent, index)
    local TEX = Yatzy.Style.TEX
    local die = CreateFrame("Button", nil, parent)
    die:SetFrameLevel(parent:GetFrameLevel() + 10)

    die.shadow = die:CreateTexture(nil, "BACKGROUND", nil, -3)     -- soft shadow on the table
    die.shadow:SetTexture(TEX.shadow)

    die.glow = die:CreateTexture(nil, "BACKGROUND", nil, -2)       -- shown when the die is saved
    die.glow:SetTexture(TEX.ui.dieGlow)
    die.glow:SetPoint("CENTER")
    die.glow:Hide()

    die.face = die:CreateTexture(nil, "BORDER")                    -- wood + worn gold rim
    die.face:SetTexture(TEX.ui.dice[((index - 1) % #TEX.ui.dice) + 1])
    die.face:SetPoint("CENTER")

    die.pips = {}
    for k = 1, 9 do
        local t = die:CreateTexture(nil, "ARTWORK")
        t:SetTexture(TEX.ui.pip)                                    -- inlaid gold pips
        die.pips[k] = t
    end

    die:SetScript("OnClick", function() Yatzy.Play:ToggleHold(index) end)
    poseDie(die, DIE_SIZE, 0, 0)
    setFace(die, 1)
    return die
end

---------------------------------------------------------------------------
-- Board frame
---------------------------------------------------------------------------

function Board:Create(parent)
    local f = CreateFrame("Frame", nil, parent)
    self.frame = f
    self.positions = {}     -- [gameId] = { {x=,y=,r=}, ... } where dice lie on the table

    local Style = Yatzy.Style

    -- Worn wooden table with darkened edges
    Style.Fill(f, Style.TEX.tableWood, { 0.80, 0.72, 0.66 })
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do Style.EdgeShade(f, side, 70, 0.6) end
    f:SetScript("OnSizeChanged", function() self:Relayout() end)
    if f.SetClipsChildren then f:SetClipsChildren(true) end         -- dice never draw outside the table

    -- Status: leather strip with stitching. Big line = whose turn it is; small line = details.
    local status = CreateFrame("Frame", nil, f)
    status:SetPoint("TOPLEFT", 10, -8)
    status:SetPoint("TOPRIGHT", -10, -8)
    status:SetHeight(46)
    Style.LeatherPanel(status, { border = 2, stitch = 5 })
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do Style.EdgeShade(status, side, 10, 0.5) end
    self.statusText = status:CreateFontString(nil, "OVERLAY")
    Style.Font(self.statusText, "title", 20, Style.TITLE)
    self.statusText:SetShadowOffset(1, -1)
    self.statusText:SetPoint("CENTER", 0, 6)
    self.statusSub = status:CreateFontString(nil, "OVERLAY")
    Style.Font(self.statusSub, "display", 10, { 0.82, 0.76, 0.62 })
    self.statusSub:SetShadowOffset(0, -1)
    self.statusSub:SetPoint("TOP", self.statusText, "BOTTOM", 0, -1)
    -- the picture of the player whose turn it is, in a gold ring on the left (Portrait.lua).
    -- Bigger than the box: it sticks out at the left and below (the table clips anything
    -- above, so it only peeks out a little at the top)
    local portrait = Yatzy.Portrait:Create(status, 64)
    portrait:SetPoint("TOPLEFT", status, "TOPLEFT", -6, 6)
    portrait:SetFrameLevel(status:GetFrameLevel() + 30)
    portrait:Hide()
    self.portrait = portrait
    -- Fast games: poke the player whose turn it is (once per turn)
    -- Fast games: time left, small, in the top-right corner of the box (same colour as "Round 1/15")
    self.timerText = status:CreateFontString(nil, "OVERLAY")
    Style.Font(self.timerText, "display", 11, { 0.82, 0.76, 0.62 })
    self.timerText:SetShadowColor(0, 0, 0, 0.9)
    self.timerText:SetShadowOffset(0, -1)
    self.timerText:SetPoint("TOPRIGHT", -10, -6)
    self.timerText:SetJustifyH("RIGHT")
    local poke = Yatzy.UI.MakeButton(status, "Poke", 70, 22, "secondary")
    poke:SetPoint("BOTTOMRIGHT", -8, 3)
    poke:SetMotionScriptsWhileDisabled(true)
    poke:SetScript("OnClick", function()
        local g = Yatzy.Play.game
        if g then Yatzy.Fast:Poke(g); self:UpdateTimer(g) end
    end)
    Yatzy.UI.Tooltip(poke, "Poke", "Remind the player whose turn it is (once per turn). "
        .. "If their time runs out, the computer plays their turn.")
    poke:Hide()
    self.pokeButton = poke

    -- Tray for saved dice: red felt in a bronze frame (rendered from the prototype)
    local tray = CreateFrame("Frame", nil, f)
    tray:SetSize(TRAY_W, TRAY_H)
    tray:SetPoint("BOTTOMLEFT", 12, 12)
    Style.Image(tray, Style.TEX.ui.tray)
    local trayLabel = tray:CreateFontString(nil, "OVERLAY")
    Style.Font(trayLabel, "display", 10, Style.TITLE)
    trayLabel:SetPoint("BOTTOMLEFT", tray, "TOPLEFT", 4, 3)
    trayLabel:SetText("Saved")
    self.tray = tray

    -- Roll button: bottom-right, as big as the tray (a bit narrower on a small table)
    local roll = Yatzy.UI.MakeButton(f, "Roll dice", ROLL_W, TRAY_H)
    roll:SetPoint("BOTTOMRIGHT", -12, 12)
    roll:SetScript("OnClick", function() self:StopFlash(); Yatzy.Play:Roll() end)
    -- "Your turn": a yellow border that pulses around the button for a few seconds
    local flash = CreateFrame("Frame", nil, roll)
    flash:SetPoint("TOPLEFT", -4, 4)
    flash:SetPoint("BOTTOMRIGHT", 4, -4)
    flash:SetFrameLevel(roll:GetFrameLevel() + 5)
    for _, edge in ipairs({ { "TOP", 3, 0.95 }, { "BOTTOM", 3, 0.95 }, { "LEFT", 3, 0.95 }, { "RIGHT", 3, 0.95 },
                            { "TOP", 7, 0.30 }, { "BOTTOM", 7, 0.30 }, { "LEFT", 7, 0.30 }, { "RIGHT", 7, 0.30 } }) do
        local side, thick, a = edge[1], edge[2], edge[3]
        local t = flash:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 0.84, 0.20, a)
        t:SetBlendMode("ADD")
        local outer = thick == 7 and -2 or 0          -- the soft part reaches a bit further out
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT", flash, side .. "LEFT", outer, side == "TOP" and -outer or outer)
            t:SetPoint(side .. "RIGHT", flash, side .. "RIGHT", -outer, side == "TOP" and -outer or outer)
            t:SetHeight(thick)
        else
            t:SetPoint("TOP" .. side, flash, "TOP" .. side, side == "LEFT" and outer or -outer, -outer)
            t:SetPoint("BOTTOM" .. side, flash, "BOTTOM" .. side, side == "LEFT" and outer or -outer, outer)
            t:SetWidth(thick)
        end
    end
    flash:Hide()
    roll.flash = flash
    -- Big "Roll dice", with "2 left" in small text underneath
    local fs = roll.label
    Style.Font(fs, "display", 22, Style.TEXT)
    roll:SetPushedTextOffset(0, 0)          -- we position the text ourselves
    roll.sub = roll:CreateFontString(nil, "OVERLAY")
    Style.Font(roll.sub, "display", 11, { 0.90, 0.80, 0.62 })
    roll.sub:SetShadowColor(0, 0, 0, 0.9)
    roll.sub:SetShadowOffset(0, -1)
    roll.sub:SetPoint("TOP", fs, "BOTTOM", 0, -1)
    roll:HookScript("OnDisable", function() roll.sub:SetTextColor(0.55, 0.52, 0.48) end)
    roll:HookScript("OnEnable", function() roll.sub:SetTextColor(0.90, 0.80, 0.62) end)
    roll:HookScript("OnShow", function()
        local t = roll.sub:GetText()
        if t and t ~= "" then Style.SetText(roll.sub, t) end
    end)
    self.rollButton = roll

    -- Dice
    self.dice = {}
    for i = 1, Rules.NUM_DICE do self.dice[i] = createDie(f, i) end

    -- YATZY! celebration: rotating light rays, a big title that pops in, subtitle
    local cel = CreateFrame("Frame", nil, f)
    cel:SetAllPoints()
    cel:SetFrameLevel(f:GetFrameLevel() + 20)
    cel.rays = cel:CreateTexture(nil, "BACKGROUND")
    cel.rays:SetTexture(Style.TEX.ui.rays)
    cel.rays:SetBlendMode("ADD")
    cel.rays:SetPoint("CENTER", 0, 10)
    cel.text = CreateFrame("Frame", nil, cel)            -- scaled as a whole for the "pop"
    cel.text:SetSize(400, 140)
    cel.text:SetPoint("CENTER", 0, 10)
    cel.big = cel.text:CreateFontString(nil, "OVERLAY")
    Style.Font(cel.big, "title", 72, { 1, 0.86, 0.35 }, "THICKOUTLINE")
    cel.big:SetShadowColor(0.35, 0.22, 0.03, 1)
    cel.big:SetShadowOffset(2, -4)
    cel.big:SetPoint("CENTER", 0, 12)
    cel.big:SetText("YATZY!")
    cel.sub = cel.text:CreateFontString(nil, "OVERLAY")
    Style.Font(cel.sub, "display", 16, Style.TEXT, "OUTLINE")
    cel.sub:SetPoint("TOP", cel.big, "BOTTOM", 0, -2)
    cel:Hide()
    self.celebration = cel

    -- Game over panel
    local over = CreateFrame("Frame", nil, f)
    over:SetSize(340, 190)
    over:SetPoint("CENTER")
    over:SetFrameLevel(f:GetFrameLevel() + 25)
    over:EnableMouse(true)
    Style.LeatherPanel(over, { border = 4, stitch = 9 })
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do Style.EdgeShade(over, side, 30, 0.5) end
    over.title = over:CreateFontString(nil, "OVERLAY")
    Style.Font(over.title, "title", 26, Style.TITLE)
    over.title:SetShadowOffset(1, -2)
    over.title:SetPoint("TOP", 0, -16)
    -- One line per player (up to 6). Winners: bigger, in the title font, inside a glowing
    -- gold frame with small sparks of light running round it (our own take on WoW's
    -- "proc" highlight).
    over.lines, over.glows = {}, {}
    local SPARKS = 6
    for i = 1, Yatzy.Rules.MAX_PLAYERS do
        local box = CreateFrame("Frame", nil, over)
        box:SetFrameLevel(over:GetFrameLevel() + 1)
        -- warm light around the frame
        local halo = box:CreateTexture(nil, "BACKGROUND")
        halo:SetTexture(Style.TEX.ui.softGlow)
        halo:SetTexCoord(0, 1, 0, 1)           -- the light fills its whole file (drawn at 2x)
        halo:SetBlendMode("ADD")
        halo:SetVertexColor(1, 0.70, 0.22)
        halo:SetPoint("TOPLEFT", -22, 14); halo:SetPoint("BOTTOMRIGHT", 22, -14)
        box.halo = halo
        -- the frame: a bright gold line with a softer outer line
        box.edges = {}
        for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                             { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
            for k, spec in ipairs({ { 0, 2, { 1, 0.86, 0.38, 1 } }, { -2, 2, { 1, 0.70, 0.20, 0.45 } } }) do
                local t = box:CreateTexture(nil, "BORDER", nil, k)
                local off, size, col = spec[1], spec[2], spec[3]
                t:SetColorTexture(col[1], col[2], col[3], col[4])
                local function o(p) return (p:find("LEFT") and off or -off), (p:find("TOP") and -off or off) end
                t:SetPoint(e[1], o(e[1])); t:SetPoint(e[2], o(e[2]))
                if e[3] then t:SetHeight(size) else t:SetWidth(size) end
                box.edges[#box.edges + 1] = t
            end
        end
        -- a faint golden wash inside
        local wash = box:CreateTexture(nil, "BACKGROUND", nil, 1)
        wash:SetAllPoints()
        wash:SetColorTexture(1, 0.80, 0.30, 0.10)
        -- sparks running round the frame
        box.sparks = {}
        for s = 1, SPARKS do
            local sp = box:CreateTexture(nil, "OVERLAY", nil, 2)
            sp:SetTexture(Style.TEX.ui.softGlow)
            sp:SetTexCoord(0, 1, 0, 1)
            sp:SetBlendMode("ADD")
            sp:SetVertexColor(1, 0.95, 0.70)
            sp:SetSize(14, 7)
            box.sparks[s] = sp
        end
        box:Hide()
        over.glows[i] = box
        local line = over:CreateFontString(nil, "OVERLAY")
        Style.Font(line, "display", 13, Style.TEXT)
        line:SetJustifyH("CENTER")
        over.lines[i] = line
    end
    over:SetScript("OnUpdate", function(o, elapsed)
        o.t = (o.t or 0) + elapsed
        local s = math.sin(o.t * 2.2)           -- calm breathing
        for _, box in ipairs(o.glows) do
            if box:IsShown() then
                box.halo:SetAlpha(0.45 + 0.20 * s)
                for _, e in ipairs(box.edges) do e:SetAlpha(0.85 + 0.15 * s) end
                -- sparks travel clockwise along the frame, evenly spaced
                local w, h = box:GetWidth() or 0, box:GetHeight() or 0
                local perim = 2 * (w + h)
                if perim > 0 then
                    for k, sp in ipairs(box.sparks) do
                        local d = (o.t * 45 + (k - 1) * perim / #box.sparks) % perim
                        local x, y
                        if d < w then x, y = d, 0
                        elseif d < w + h then x, y = w, -(d - w)
                        elseif d < 2 * w + h then x, y = w - (d - w - h), -h
                        else x, y = 0, -(h - (d - 2 * w - h)) end
                        sp:ClearAllPoints()
                        sp:SetPoint("CENTER", box, "TOPLEFT", x, y)
                        sp:SetAlpha(0.65 + 0.35 * math.sin(o.t * 6 + k))
                    end
                end
            end
        end
    end)
    -- Replay: a new round with the same players (invitations to the others, who accept or decline)
    local replay = Yatzy.UI.MakeButton(over, "Replay", 104, 26)
    replay:SetPoint("BOTTOMLEFT", 14, 16)
    replay:SetScript("OnClick", function() Yatzy.UI:ReplayGame(self.game) end)
    over.replay = replay
    local back = Yatzy.UI.MakeButton(over, "Back to games", 118, 26, "secondary")
    back:SetPoint("LEFT", replay, "RIGHT", 8, 0)
    back:SetScript("OnClick", function() Yatzy.UI:ShowStart() end)
    local closeOver = Yatzy.UI.MakeButton(over, "Close", 66, 26, "secondary")
    closeOver:SetPoint("BOTTOMRIGHT", -14, 16)
    closeOver:SetScript("OnClick", function() over:Hide(); self.overDismissed = true end)
    over:Hide()
    self.overPanel = over

    -- If the board is hidden mid-roll, finish the roll at once (OnUpdate doesn't run on hidden frames).
    f:SetScript("OnHide", function() self:FinishAnimation(true) end)
end

-- Anchor the board: to the left of the sheet, or the whole area.
function Board:Place(parent, sheetFrame)
    local f = self.frame
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", parent, "TOPLEFT")
    if sheetFrame then
        f:SetPoint("BOTTOMRIGHT", sheetFrame, "BOTTOMLEFT", -2, 0)
    else
        f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT")
    end
end

---------------------------------------------------------------------------
-- Where dice may lie
---------------------------------------------------------------------------

-- Area for die centres, measured from the board's bottom-left corner.
function Board:Area()
    local w, h = self.frame:GetWidth(), self.frame:GetHeight()
    local trayH = (self.size or SIZES.normal).trayH
    return 46, w - 46, 12 + trayH + 44, h - 90           -- below the status (46 px high)
end

function Board:FreeSpot(taken)
    local x0, x1, y0, y1 = self:Area()
    if x1 < x0 then x1 = x0 end
    if y1 < y0 then y1 = y0 end
    local function pick() return x0 + math.random() * (x1 - x0), y0 + math.random() * (y1 - y0) end
    local function nearest(x, y)
        local best = math.huge
        for _, p in ipairs(taken) do
            local dx, dy = p.x - x, p.y - y
            best = math.min(best, dx * dx + dy * dy)
        end
        return best
    end
    -- Short table: the free zigzag spot furthest from the other dice (a little jitter so it
    -- doesn't look like a grid)
    if self.zigzag then
        local best, bd = nil, -1
        for _, s in ipairs(self:ZigzagSpots()) do
            local d = nearest(s.x, s.y) + math.random()        -- random tie-break
            if d > bd then best, bd = s, d end
        end
        local jx = math.max(0, ((x1 - x0) / 4 - MIN_DIE_DISTANCE) / 2)
        local x = math.max(x0, math.min(x1, best.x + rnd(-1, 1) * math.min(jx, 10)))
        local y = math.max(y0, math.min(y1, best.y + rnd(-1, 1) * 3))
        return { x = x, y = y, r = 0 }
    end
    -- A random spot with room around it ...
    for _ = 1, 150 do
        local x, y = pick()
        if nearest(x, y) >= MIN_DIE_DISTANCE * MIN_DIE_DISTANCE then return { x = x, y = y, r = 0 } end
    end
    -- ... or, on a small table, the roomiest of many tries (dice spread out along the table)
    local bx, by, bd = x0, y0, -1
    for _ = 1, 400 do
        local x, y = pick()
        local d = nearest(x, y)
        if d > bd then bx, by, bd = x, y, d end
    end
    return { x = bx, y = by, r = 0 }
end

local function positionsFor(self, g)
    local p = self.positions[g.id]
    if not p then
        p = {}
        self.positions[g.id] = p
    end
    return p
end

-- Tray (left) and Roll button (right) share the bottom row, with space between them.
-- On a small table the button gets narrower first (the tray needs room for 5 dice).
-- Below the breakpoint (small table) everything in the bottom row is smaller.
function Board:LayoutBottom()
    local w, h = self.frame:GetWidth() or 0, self.frame:GetHeight() or 0
    if w <= 0 then return end
    local compact = w < COMPACT_BELOW_W or h < COMPACT_BELOW_H
    local s = compact and SIZES.compact or SIZES.normal
    if self.size ~= s then
        self.size = s
        local roll = self.rollButton
        Yatzy.Style.Font(roll.label, "display", s.font, Yatzy.Style.TEXT)
        Yatzy.Style.Font(roll.sub, "display", s.sub, { 0.90, 0.80, 0.62 })
        if not roll:IsEnabled() then                 -- keep the greyed-out look of a disabled button
            roll.label:SetTextColor(0.55, 0.52, 0.48); roll.sub:SetTextColor(0.55, 0.52, 0.48)
        end
    end
    self.compact = compact
    local avail = w - 24 - BOTTOM_GAP
    local trayW = math.min(s.trayW, math.max(s.minTrayW, avail - s.rollW))
    self.tray:SetSize(trayW, s.trayH)
    self.rollButton:SetSize(math.max(s.minRollW, math.min(s.rollW, avail - trayW)), s.trayH)
    self:FitRollText()
end

-- "Roll dice" must stay inside its button: in a narrow button the font steps down
-- until the text fits (with some room at the sides).
function Board:FitRollText()
    local btn = self.rollButton
    if not btn then return end
    local s = self.size or SIZES.normal
    local room = (btn:GetWidth() or 0) - 20
    if room <= 0 then return end
    local Style = Yatzy.Style
    local text = btn.label:GetText() or ""
    local size = s.font
    while true do
        Style.Font(btn.label, "display", size, Style.TEXT)
        btn.label:SetText(text)
        if size <= 11 or (btn.label:GetStringWidth() or 0) <= room then break end
        size = size - 1
    end
    if not btn:IsEnabled() then btn.label:SetTextColor(0.55, 0.52, 0.48) end
end

-- When the table gets smaller, dice outside it move to free spots.
function Board:Relayout()
    self:LayoutBottom()
    self:FitDice()
    local g = self.game
    if not g or not self.frame:IsVisible() or self.animating then return end
    if g.rollsUsed > 0 then
        local pos = positionsFor(self, g)
        local x0, x1, y0, y1 = self:Area()
        local keep = {}
        for i = 1, Rules.NUM_DICE do
            local p = pos[i]
            if p and not g.held[i] and p.x >= x0 and p.x <= x1 and p.y >= y0 and p.y <= y1 then keep[#keep + 1] = p end
        end
        for i = 1, Rules.NUM_DICE do
            local p = pos[i]
            if not g.held[i] and (not p or p.x < x0 or p.x > x1 or p.y < y0 or p.y > y1) then
                local spot = self:FreeSpot(keep)
                spot.r = p and p.r or math.random(0, 359)
                pos[i] = spot
                keep[#keep + 1] = spot
            end
        end
        self:SeparateLanded(g)
    end
    self:Refresh(g)
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

function Board:SetGame(g)
    if self.game ~= g then
        self.overDismissed = false
        self:FinishAnimation(true)
    end
    self.game = g
    self.celebration:Hide()
end

-- After the 3rd roll all dice line up in the middle of the table, lowest value first.
local function lineSlot(g, i)
    local order = {}
    for k = 1, Rules.NUM_DICE do order[k] = k end
    table.sort(order, function(a, b)
        if g.dice[a] ~= g.dice[b] then return g.dice[a] < g.dice[b] end
        return a < b
    end)
    for slot, k in ipairs(order) do if k == i then return slot end end
end

function Board:LinedUp(g)
    return g.status == "active" and g.rollsUsed >= Rules.MAX_ROLLS
end

local function rowGap(self)
    return math.min(80, (self.frame:GetWidth() - 90) / 4)
end

-- Centre of die i in the row (from the board's bottom-left corner): vertically centred on the table.
function Board:LineTarget(g, i)
    local _, _, y0, y1 = self:Area()
    return self.frame:GetWidth() / 2 + (lineSlot(g, i) - 3) * rowGap(self), (y0 + y1) / 2
end

local function storedAngle(self, g, i)
    local p = positionsFor(self, g)[i]
    return p and p.r or 0
end

-- A saved die in the tray, in die order, lying straight
local function placeInTray(self, die, i, g)
    local slot = 0
    for k = 1, i do if g.held[k] then slot = slot + 1 end end
    die:ClearAllPoints()
    local s = self.size or SIZES.normal
    poseDie(die, s.die, straight(storedAngle(self, g, i)))
    die:SetPoint("CENTER", self.tray, "LEFT", s.first + (slot - 1) * s.step, 0)
end

local function placeDie(self, die, i, g)
    local f = self.frame
    die:ClearAllPoints()
    if self:LinedUp(g) then
        poseDie(die, DIE_SIZE, straight(storedAngle(self, g, i)))
        die:SetPoint("CENTER", f, "BOTTOMLEFT", self:LineTarget(g, i))
        return
    end
    if g.rollsUsed == 0 then
        -- Before the first roll: a neat, dimmed row in the middle
        local _, _, y0, y1 = self:Area()
        poseDie(die, DIE_SIZE, 0)
        die:SetPoint("CENTER", f, "BOTTOMLEFT", f:GetWidth() / 2 + (i - 3) * rowGap(self), (y0 + y1) / 2)
        return
    end
    if g.held[i] then
        placeInTray(self, die, i, g)
        return
    end
    local p = positionsFor(self, g)[i]
    if not p then
        -- No spot yet (e.g. after /reload mid-turn). Wait until the board has its real size.
        if f:GetWidth() < 200 then
            poseDie(die, DIE_SIZE, 0)
            die:SetPoint("CENTER", f, "CENTER", (i - 3) * 70, 0)
            return
        end
        local taken = {}
        for k, q in pairs(positionsFor(self, g)) do if k ~= i and not g.held[k] then taken[#taken + 1] = q end end
        p = self:FreeSpot(taken)
        p.r = math.random(0, 359)
        positionsFor(self, g)[i] = p
    else
        -- A die taken back out of the tray returns to where it lay before it was saved,
        -- but the other dice may have been rolled onto that spot since: then find a free one.
        local taken, clash = {}, false
        for k, q in pairs(positionsFor(self, g)) do
            if k ~= i and not g.held[k] then
                taken[#taken + 1] = q
                local dx, dy = q.x - p.x, q.y - p.y
                if dx * dx + dy * dy < (MIN_DIE_DISTANCE - 2) ^ 2 then clash = true end
            end
        end
        if clash and f:GetWidth() >= 200 then
            local r = p.r
            p = self:FreeSpot(taken)
            p.r = r
            positionsFor(self, g)[i] = p
        end
    end
    poseDie(die, DIE_SIZE, p.r)
    die:SetPoint("CENTER", f, "BOTTOMLEFT", p.x, p.y)
end

function Board:Refresh(g)
    g = g or self.game
    if not g or self.animating then return end
    local Games = Yatzy.Games
    local mine = Games:IsMyTurn(g)

    -- Status: big = whose turn, small = round and roll
    local big, small
    local round = ("Round %d/%d"):format(Rules.Round(g), Rules.NUM_TURNS)
    if g.status ~= "active" then
        big, small = "Game over", ""
    elseif mine then
        if g.rollsUsed == 0 then
            big, small = "Your turn", round
        elseif g.rollsUsed < Rules.MAX_ROLLS then
            big, small = "Your turn", ("%s  ·  Roll %d/3  ·  save dice or pick a field"):format(round, g.rollsUsed)
        else
            big, small = "Pick a field", round .. "  ·  fill in or strike out"
        end
    else
        local name = Games:PlayerName(g, Rules.CurrentPlayer(g))
        if g.rollsUsed == 0 then
            big, small = name .. "'s turn", round
        else
            big, small = name .. " is rolling", ("%s  ·  Roll %d/3"):format(round, g.rollsUsed)
        end
    end
    -- The active player's picture (hidden when the game is over)
    if g.status == "active" then
        Yatzy.Portrait:Set(self.portrait, g, Rules.CurrentPlayer(g))
        self.portrait:Show()
    else
        self.portrait:Hide()
    end
    -- Full names can be long: step the font down instead of cutting the name off
    -- (room is left for the picture on both sides, so the text stays centred)
    local room = (self.frame:GetWidth() or 400) - 40 - 2 * 62
    for _, size in ipairs({ 20, 17, 14 }) do
        Yatzy.Style.Font(self.statusText, "title", size, Yatzy.Style.TITLE)
        Yatzy.Style.SetText(self.statusText, big)
        if (self.statusText:GetStringWidth() or 0) <= room then break end
    end
    self.statusBase = small
    self:UpdateTimer(g)
    if mine then self.statusText:SetTextColor(1, 0.86, 0.45) else self.statusText:SetTextColor(0.85, 0.80, 0.70) end

    -- Roll button
    local left = Rules.MAX_ROLLS - g.rollsUsed
    local main, sub = "Roll dice", ""
    if mine and left <= 0 then
        main, sub = "No rolls", "pick a field"
    elseif mine then
        sub = ("%d left"):format(left)
    end
    local btn = self.rollButton
    btn:SetText(""); btn:SetText(main)
    Yatzy.Style.SetText(btn.sub, sub)
    local fs = btn.label
    fs:ClearAllPoints()
    fs:SetPoint("CENTER", 0, sub ~= "" and (self.size or SIZES.normal).textUp or 0)   -- room for the small line
    local allHeld = g.rollsUsed > 0
    for i = 1, Rules.NUM_DICE do if not g.held[i] then allHeld = false end end
    self.rollButton:SetEnabled(mine and left > 0 and not allHeld)
    self:FitRollText()

    -- Dice
    local canHold = mine and g.rollsUsed > 0 and g.rollsUsed < Rules.MAX_ROLLS
    for i, die in ipairs(self.dice) do
        placeDie(self, die, i, g)
        setFace(die, g.rollsUsed == 0 and (((i * 2) % 6) + 1) or g.dice[i])
        die:SetAlpha((g.rollsUsed == 0 or g.status ~= "active") and 0.55 or 1)
        local glow = g.held[i] and g.rollsUsed > 0 and not self:LinedUp(g)
        die.glow:SetSize(die:GetWidth() * 2, die:GetWidth() * 2)
        die.glow:SetShown(glow)
        die:EnableMouse(canHold)
    end

    -- Game over panel
    if g.status ~= "active" and not self.overDismissed then
        local over, Style = self.overPanel, Yatzy.Style
        local winners = {}
        for _, seat in ipairs(Rules.Winners(g)) do winners[seat] = true end
        local standings = Rules.Standings(g)
        local anchor, gap = over.title, -16
        local height = 16 + 30 + 16 + 56       -- top, title, gaps, buttons; lines added below
        for i, line in ipairs(over.lines) do
            local entry = standings[i]
            local glow = over.glows[i]
            line:ClearAllPoints()
            if entry then
                local won = winners[entry.seat]
                if won then
                    Style.Font(line, "title", 22, { 1, 0.86, 0.40 })
                    line:SetShadowColor(0.35, 0.20, 0.02, 1)
                    line:SetShadowOffset(1, -2)
                else
                    Style.Font(line, "display", 13, Style.TEXT)
                    line:SetShadowColor(0, 0, 0, 0.8)
                    line:SetShadowOffset(0, -1)
                end
                line:SetPoint("TOP", anchor, "BOTTOM", 0, gap)
                Style.SetText(line, ("%d.  %s  —  %d"):format(i, Games:PlayerName(g, entry.seat), entry.total))
                line:Show()
                -- the winner's gold frame: around the line, never wider than the panel
                glow:ClearAllPoints()
                glow:SetPoint("CENTER", line, "CENTER", 0, -1)
                glow:SetSize(math.min(over:GetWidth() - 36, (line:GetStringWidth() or 120) + 34), 32)
                glow:SetShown(won and true or false)
                anchor, gap = line, won and -14 or -5
                height = height + (won and 36 or 18)
            else
                line:Hide()
                glow:Hide()
            end
        end
        over:SetHeight(math.max(190, height))
        over.title:SetText("Game over")
        over.replay:SetText(Games:ReplayTarget(g) and "Go to replay" or "Replay")
        over:Show()
    else
        self.overPanel:Hide()
    end
end

---------------------------------------------------------------------------
-- Rolling, like a person throws: every die gets its own delay, speed, spin and
-- number of bounces, chosen anew each throw. Some fly together, some land early,
-- a hard throw spins a lot, a soft one just hops once. The whole throw still takes
-- about ROLL_TIME.
---------------------------------------------------------------------------

local function planThrow(rolled)
    -- Order in which the dice leave the hand; sometimes two go together.
    local order = {}
    for _, i in ipairs(rolled) do order[#order + 1] = i end
    for k = #order, 2, -1 do local j = math.random(k); order[k], order[j] = order[j], order[k] end

    local plans, delay = {}, 0
    for k, i in ipairs(order) do
        if k > 1 and math.random() > 0.35 then delay = delay + rnd(0.03, 0.10) end
        delay = math.min(delay, 0.28)
        local hard = math.random() ^ 1.3                           -- 0 = gentle, 1 = hard throw
        local duration = math.max(0.35, ROLL_TIME - delay - rnd(0, 0.18))
        local spin = (math.random() < 0.5 and -1 or 1) * (60 + hard * rnd(500, 1000))
        plans[i] = {
            delay = delay,
            duration = duration,
            spin = spin,
            bounces = hard > 0.65 and math.random(2, 3) or (hard > 0.3 and 2 or 1),
            peak = 0.35 + 0.65 * hard,                             -- how high it flies
            drift = rnd(0.5, 1.0),                                 -- how much it curves
            ox = 0, oy = 0, kick = 0, lt = 0,                      -- pushes and extra spin from collisions
        }
    end
    return plans
end

-- Rolls the game's free dice through Rules.Roll and animates it if the board is showing.
-- `onDone` runs after the dice have landed (immediately if nobody is watching).
-- `preset` = { dice, held, roll }: show another player's roll instead of rolling ourselves.
function Board:RollAnimated(g, onDone, preset)
    local firstRoll = preset and preset.roll == 1 or (not preset and g.rollsUsed == 0)
    if preset then g.held = preset.held end
    local rolled = {}
    for i = 1, Rules.NUM_DICE do
        if firstRoll or not g.held[i] then rolled[#rolled + 1] = i end
    end
    local visible = self.game == g and self.frame:IsVisible()

    -- Where the dice start (their current spots and angles on screen)
    local starts = {}
    if visible then
        local fx, fy = self.frame:GetLeft() or 0, self.frame:GetBottom() or 0
        for _, i in ipairs(rolled) do
            local cx, cy = self.dice[i]:GetCenter()
            starts[i] = { x = (cx or fx) - fx, y = (cy or fy) - fy, r = self.dice[i].angle or 0 }
        end
    end

    local ok
    if preset then
        g.dice, g.rollsUsed = preset.dice, preset.roll
        ok = true
    else
        ok = Rules.Roll(g)
    end
    if not ok then if onDone then onDone(nil) end return end

    -- What was rolled, frozen now: the turn may move on (and the dice reset to 1-1-1-1-1)
    -- before the animation ends, e.g. when another player scores right after their roll.
    -- Checking a Yatzy on the live state then gave false "YATZY!" popups.
    local roll = { dice = { unpack(g.dice) }, turn = g.turn, seat = Rules.CurrentPlayer(g), rollNo = g.rollsUsed }
    local userDone = onDone
    onDone = userDone and function() userDone(roll) end

    -- New landing spots and angles
    local plans = planThrow(rolled)
    local pos = positionsFor(self, g)
    local taken = {}
    for _, i in ipairs(rolled) do
        local spot = self:FreeSpot(taken)
        local startR = starts[i] and starts[i].r or 0
        spot.r = startR + plans[i].spin
        pos[i] = spot
        taken[#taken + 1] = spot
    end

    if not visible then
        self:SeparateLanded(g)
        if onDone then onDone() end
        return
    end

    Yatzy.Sound:Play(#rolled == 1 and "rollOne" or "roll")
    -- Dice that stay put go to the tray now. Needed for other players' rolls: their saved
    -- dice can arrive together with the roll, and used to wait on the table until it ended.
    if not firstRoll then
        local isRolled = {}
        for _, i in ipairs(rolled) do isRolled[i] = true end
        for i, die in ipairs(self.dice) do
            if not isRolled[i] then
                -- (the tray, also on the 3rd roll: the row comes only after the dice have landed)
                placeInTray(self, die, i, g)
                setFace(die, g.dice[i])
                die:SetAlpha(1)
                die.glow:SetSize(die:GetWidth() * 2, die:GetWidth() * 2)
                die.glow:SetShown(g.held[i] and true or false)
            end
        end
    end
    local x0, x1, y0, y1 = self:Area()
    for _, i in ipairs(rolled) do
        local s, e, p = starts[i], pos[i], plans[i]
        -- A random point the die curves through on its way
        p.cx = (s.x + e.x) / 2 + rnd(-1, 1) * (x1 - x0) * 0.3 * p.drift
        p.cy = (s.y + e.y) / 2 + rnd(-1, 1) * (y1 - y0) * 0.3 * p.drift
        p.nextFace = p.delay
        self.dice[i]:SetAlpha(1)
        self.dice[i].glow:Hide()
    end
    self.animating = { game = g, rolled = rolled, starts = starts, plans = plans, elapsed = 0, onDone = onDone }
    self.frame:SetScript("OnUpdate", function(_, elapsed) self:AnimationStep(elapsed) end)
end

-- Current centre of each die, measured from the board's bottom-left corner.
local function currentCentres(self)
    local fx, fy = self.frame:GetLeft() or 0, self.frame:GetBottom() or 0
    local list = {}
    for i, die in ipairs(self.dice) do
        local cx, cy = die:GetCenter()
        list[i] = { x = (cx or fx) - fx, y = (cy or fy) - fy, r = die.angle or 0 }
    end
    return list
end

function Board:AnimationStep(elapsed)
    local a = self.animating
    if not a then return end
    a.elapsed = a.elapsed + elapsed

    -- Between the phases: the dice lie still so you can see what was rolled
    if a.phase == "rest" then
        if a.elapsed >= LINE_UP_DELAY then
            a.rested = true
            self:FinishAnimation(false)
        end
        return
    end

    -- Phase 2: glide all five dice into the sorted row
    if a.phase == "lineup" then
        local t = math.min(1, a.elapsed / LINE_UP_TIME)
        local ease = 1 - (1 - t) * (1 - t)
        for i, die in ipairs(self.dice) do
            local s = a.lineStarts[i]
            local ex, ey = self:LineTarget(a.game, i)
            local er = straight(s.r)
            poseDie(die, DIE_SIZE, s.r + (er - s.r) * ease, 0)
            die:ClearAllPoints()
            die:SetPoint("CENTER", self.frame, "BOTTOMLEFT", s.x + (ex - s.x) * ease, s.y + (ey - s.y) * ease)
        end
        if t >= 1 then self:FinishAnimation(true) end
        return
    end

    -- Phase 1: the throw
    local pos = positionsFor(self, a.game)
    local allDone = true
    local now = {}           -- where each rolled die is this frame (before collisions)
    for _, i in ipairs(a.rolled) do
        local p, s, e = a.plans[i], a.starts[i], pos[i]
        local lt = (a.elapsed - p.delay) / p.duration
        if lt < 1 then allDone = false end
        p.lt = lt
        if lt <= 0 then
            now[i] = { x = s.x, y = s.y }                           -- still in the hand / where it lay
        else
            lt = math.min(1, lt)
            local move = 1 - (1 - lt) ^ 2.2                        -- fast first, slowing down
            local u = 1 - move
            now[i] = {
                x = u * u * s.x + 2 * u * move * p.cx + move * move * e.x + p.ox,
                y = u * u * s.y + 2 * u * move * p.cy + move * move * e.y + p.oy,
            }
        end
    end

    self:Collide(a, now)

    for _, i in ipairs(a.rolled) do
        local die, p, s = self.dice[i], a.plans[i], a.starts[i]
        local lt = p.lt
        if lt > 0 then
            lt = math.min(1, lt)
            local spinT = 1 - (1 - lt) ^ 3                          -- spin dies out at the end
            local height = p.peak * (1 - lt) ^ 1.3 * math.abs(math.sin(math.pi * p.bounces * lt))
            poseDie(die, DIE_SIZE, s.r + p.spin * spinT + p.kick, height)
            die:ClearAllPoints()
            die:SetPoint("CENTER", self.frame, "BOTTOMLEFT", now[i].x, now[i].y)
            -- Faces flicker while it tumbles, slower as it settles; the real value shows as it lands
            if lt < 0.82 then
                if a.elapsed >= p.nextFace then
                    setFace(die, math.random(1, 6))
                    p.nextFace = a.elapsed + 0.04 + lt * 0.12
                end
            else
                setFace(die, a.game.dice[i])
            end
        end
    end
    if allDone then self:FinishAnimation() end
end

-- Dice bump into each other instead of passing through: overlapping dice are pushed
-- apart (a die in flight takes the push, a resting one stays put), get a little extra
-- spin, and the push stays with them so they land somewhere else. Two landed dice
-- that overlap (small windows) are nudged apart until they don't.
local COLLIDE_DIST = DIE_SIZE * 1.15     -- in the air: a bump
local LANDED_DIST = MIN_DIE_DISTANCE    -- lying still: never overlapping

-- Small table: the five dice are placed in a zigzag (one high, one low, ...), which is the
-- roomiest way to fit them on a short table. Only if even that is too tight do the dice
-- get smaller (never below 44 px).
function Board:FitDice()
    local x0, x1, y0, y1 = self:Area()
    local dx, h = math.max(0, x1 - x0) / 4, math.max(0, y1 - y0)
    local roomiest = math.min(2 * dx, math.sqrt(dx * dx + h * h))   -- centre distance in a zigzag
    local size = math.max(44, math.min(FULL_DIE_SIZE, roomiest / SPACING))
    DIE_SIZE = size
    self.dieSize = size
    MIN_DIE_DISTANCE = size * SPACING
    COLLIDE_DIST = size * 1.15
    LANDED_DIST = MIN_DIE_DISTANCE
    self.zigzag = h < MIN_DIE_DISTANCE * 1.6      -- too short for random spots to work well
end

-- The five zigzag spots for a small table
function Board:ZigzagSpots()
    local x0, x1, y0, y1 = self:Area()
    local spots = {}
    for k = 0, 4 do
        spots[#spots + 1] = { x = x0 + k * (x1 - x0) / 4, y = (k % 2 == 0) and y0 or y1 }
    end
    return spots
end
function Board:Collide(a, now)
    local x0, x1, y0, y1 = self:Area()
    local list = a.rolled
    for _ = 1, 3 do
        for m = 1, #list do
            for n = m + 1, #list do
                local i, j = list[m], list[n]
                local pi_, pj = a.plans[i], a.plans[j]
                local dx, dy = now[j].x - now[i].x, now[j].y - now[i].y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist < COLLIDE_DIST then
                    if dist < 0.01 then dx, dy, dist = rnd(-1, 1), rnd(-1, 1), 1 end
                    local push = COLLIDE_DIST - dist
                    local nx, ny = dx / dist, dy / dist
                    local moveI = pi_.lt > 0               -- dice still in the hand don't move
                    local moveJ = pj.lt > 0
                    local shareI, shareJ = 0.5, 0.5
                    if moveI and not moveJ then shareI, shareJ = 1, 0
                    elseif moveJ and not moveI then shareI, shareJ = 0, 1
                    elseif not moveI and not moveJ then shareI, shareJ = 0, 0 end
                    now[i].x, now[i].y = now[i].x - nx * push * shareI, now[i].y - ny * push * shareI
                    now[j].x, now[j].y = now[j].x + nx * push * shareJ, now[j].y + ny * push * shareJ
                    pi_.ox, pi_.oy = pi_.ox - nx * push * shareI, pi_.oy - ny * push * shareI
                    pj.ox, pj.oy = pj.ox + nx * push * shareJ, pj.oy + ny * push * shareJ
                    -- A knock makes them spin a bit more
                    pi_.kick = pi_.kick + push * 2 * (pi_.spin > 0 and 1 or -1) * shareI
                    pj.kick = pj.kick + push * 2 * (pj.spin > 0 and 1 or -1) * shareJ
                end
            end
        end
        -- Keep everything that's moving on the table
        for _, i in ipairs(list) do
            local p = a.plans[i]
            if p.lt > 0 then
                local cx = math.max(x0, math.min(x1, now[i].x))
                local cy = math.max(y0, math.min(y1, now[i].y))
                p.ox, p.oy = p.ox + (cx - now[i].x), p.oy + (cy - now[i].y)
                now[i].x, now[i].y = cx, cy
            end
        end
    end
end

-- After landing: make sure no two dice lie on top of each other (small windows).
function Board:SeparateLanded(g)
    local pos = positionsFor(self, g)
    local x0, x1, y0, y1 = self:Area()
    local onTable = {}
    for i = 1, Rules.NUM_DICE do if not g.held[i] and pos[i] then onTable[#onTable + 1] = i end end
    for _ = 1, 80 do
        local moved = false
        for m = 1, #onTable do
            for n = m + 1, #onTable do
                local p, q = pos[onTable[m]], pos[onTable[n]]
                local dx, dy = q.x - p.x, q.y - p.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist < LANDED_DIST - 0.5 then
                    if dist < 0.01 then dx, dy, dist = 1, 0, 1 end
                    local push = (LANDED_DIST - dist) / 2 + 0.5
                    p.x, p.y = p.x - dx / dist * push, p.y - dy / dist * push
                    q.x, q.y = q.x + dx / dist * push, q.y + dy / dist * push
                    moved = true
                end
            end
        end
        for _, i in ipairs(onTable) do
            local p = pos[i]
            p.x = math.max(x0, math.min(x1, p.x))
            p.y = math.max(y0, math.min(y1, p.y))
        end
        if not moved then break end
    end
end

-- `final` = skip the line-up glide (used when it has run, or when the board is hidden).
function Board:FinishAnimation(final)
    local a = self.animating
    if not a then return end
    -- Where the dice really ended up: planned spot + collision pushes, never on top of each other
    if a.plans and not a.settled then
        a.settled = true
        local pos = positionsFor(self, a.game)
        for _, i in ipairs(a.rolled) do
            local p = a.plans[i]
            pos[i].x, pos[i].y = pos[i].x + p.ox, pos[i].y + p.oy
            pos[i].r = pos[i].r + p.kick
        end
        self:SeparateLanded(a.game)
    end
    -- After the 3rd roll: glide every die (also saved ones from the tray) into the row
    if not final and a.phase ~= "lineup" and self:LinedUp(a.game) and self.frame:IsVisible() then
        if not a.rested then
            -- first a short pause with the dice where they landed (saved ones still in the tray)
            a.phase = "rest"
            a.elapsed = 0
            return
        end
        a.phase = "lineup"
        a.elapsed = 0
        a.lineStarts = currentCentres(self)
        for i, die in ipairs(self.dice) do
            poseDie(die, DIE_SIZE, die.angle, 0)
            die.glow:Hide()
            setFace(die, a.game.dice[i])
        end
        return
    end
    self.animating = nil
    self.frame:SetScript("OnUpdate", nil)
    self:Refresh(a.game)
    if a.onDone then a.onDone() end
end

---------------------------------------------------------------------------
-- YATZY!
---------------------------------------------------------------------------

local CELEBRATE_TIME = 3.0

-- Shared animation: title pops in (overshoots, settles), rays spin and grow behind it,
-- everything fades out together at the end. `each(t)` runs every frame, `done()` at the end.
local function playCelebration(frame, subtitle, each, done)
    frame.sub:SetText(subtitle or "")
    frame.t = 0
    frame:SetAlpha(0)
    frame:Show()
    Yatzy.Sound:Play("yatzy")
    frame:SetScript("OnUpdate", function(f, elapsed)
        f.t = f.t + elapsed
        local t = f.t
        -- fade in fast, hold, fade out
        local alpha = math.min(1, t / 0.15)
        if t > CELEBRATE_TIME - 0.6 then alpha = math.max(0, (CELEBRATE_TIME - t) / 0.6) end
        f:SetAlpha(alpha)
        -- pop: 0.2 -> 1.2 -> 1.0
        local scale
        if t < 0.3 then scale = 0.2 + (1.2 - 0.2) * (1 - (1 - t / 0.3) ^ 2)
        elseif t < 0.5 then scale = 1.2 - 0.2 * ((t - 0.3) / 0.2)
        else scale = 1 + 0.03 * math.sin((t - 0.5) * 4) end
        f.text:SetScale(math.max(0.05, scale))
        -- rays: grow and keep turning
        local size = f.raySize * (0.55 + 0.45 * math.min(1, t / 0.6))
        f.rays:SetSize(size, size)
        f.rays:SetRotation(t * 0.5)
        if each then each(t) end
        if t >= CELEBRATE_TIME then
            f:SetScript("OnUpdate", nil)
            f:Hide()
            if done then done() end
        end
    end)
end

-- In the game window: also makes every die glow in a pulse.
function Board:Celebrate(subtitle)
    self.celebration.raySize = 480
    playCelebration(self.celebration, subtitle, function(t)
        for _, die in ipairs(self.dice) do
            die.glow:SetSize(die:GetWidth() * 2, die:GetWidth() * 2)
            die.glow:Show()
            die.glow:SetAlpha(0.45 + 0.55 * math.abs(math.sin(t * 5)))
        end
    end, function()
        for _, die in ipairs(self.dice) do die.glow:SetAlpha(1) end
        self:Refresh()
    end)
end

-- On the whole screen, for when the game isn't being watched (window closed or faded,
-- or another game open): a big YATZY! in the title font, above the game world.
function Board:CelebrateScreen(subtitle)
    local cel = self.screenCelebration
    if not cel then
        local Style = Yatzy.Style
        cel = CreateFrame("Frame", nil, UIParent)
        cel:SetSize(600, 300)
        cel:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
        cel:SetFrameStrata("FULLSCREEN_DIALOG")
        cel:EnableMouse(false)
        cel.rays = cel:CreateTexture(nil, "BACKGROUND")
        cel.rays:SetTexture(Style.TEX.ui.rays)
        cel.rays:SetBlendMode("ADD")
        cel.rays:SetPoint("CENTER")
        cel.text = CreateFrame("Frame", nil, cel)
        cel.text:SetSize(600, 200)
        cel.text:SetPoint("CENTER")
        cel.big = cel.text:CreateFontString(nil, "OVERLAY")
        Style.Font(cel.big, "title", 96, { 1, 0.86, 0.35 }, "THICKOUTLINE")
        cel.big:SetShadowColor(0.35, 0.22, 0.03, 1)
        cel.big:SetShadowOffset(3, -5)
        cel.big:SetPoint("CENTER", 0, 16)
        cel.big:SetText("YATZY!")
        cel.sub = cel.text:CreateFontString(nil, "OVERLAY")
        Style.Font(cel.sub, "title", 22, Style.TEXT, "OUTLINE")
        cel.sub:SetPoint("TOP", cel.big, "BOTTOM", 0, -2)
        cel.raySize = 560
        cel:Hide()
        self.screenCelebration = cel
    end
    playCelebration(cel, subtitle)
end

-- Pulse the yellow border around the Roll button (about twice a second) for 3 seconds.
local FLASH_TIME = 3
function Board:FlashRoll()
    local flash = self.rollButton and self.rollButton.flash
    if not flash then return end
    flash.t = 0
    flash:SetAlpha(0)
    flash:Show()
    flash:SetScript("OnUpdate", function(fr, elapsed)
        fr.t = fr.t + elapsed
        if fr.t < FLASH_TIME then
            fr:SetAlpha(0.5 - 0.5 * math.cos(fr.t * 2 * math.pi * 2))     -- 3 s of bright flashing
            return
        end
        -- then a calm glow until you roll, so a turn that started while you looked away
        -- is still easy to see
        local g = Yatzy.Play.game
        if not g or not Yatzy.Games:IsMyTurn(g) or g.rollsUsed > 0 then Board:StopFlash(); return end
        fr:SetAlpha(0.30 + 0.25 * math.sin(fr.t * 2.4))
    end)
end

function Board:StopFlash()
    local flash = self.rollButton and self.rollButton.flash
    if not flash then return end
    flash:SetScript("OnUpdate", nil)
    flash:Hide()
end

-- "Your turn!" in the middle of the screen, in the title font: rises in gently, holds, fades.
local TURN_POPUP_TIME = 3.2
-- The small status line, the time left in a fast game (white, top-right corner of the
-- box) and the Poke button. Called by Refresh and every second by Fast:Tick.
function Board:UpdateTimer(g)
    local Fast = Yatzy.Fast
    Yatzy.Style.SetText(self.statusSub, self.statusBase or "")
    local left = Fast:TimeLeft(g)
    if left then
        Yatzy.Style.SetText(self.timerText, left > 0 and ("Fast  " .. Fast:Format(left)) or "Time's up")
    else
        self.timerText:SetText("")
    end
    local showPoke = left ~= nil and not Yatzy.Games:IsMyTurn(g)
    self.pokeButton:SetShown(showPoke)
    if showPoke then self.pokeButton:SetEnabled(Fast:CanPoke(g)) end
end

function Board:TurnPopup(subtitle)
    local pop = self.turnPopup
    if not pop then
        local Style = Yatzy.Style
        pop = CreateFrame("Frame", nil, UIParent)
        pop:SetSize(600, 120)
        pop:SetFrameStrata("FULLSCREEN_DIALOG")
        pop:EnableMouse(false)
        pop.big = pop:CreateFontString(nil, "OVERLAY")
        Style.Font(pop.big, "title", 56, { 1, 0.86, 0.45 }, "OUTLINE")
        pop.big:SetShadowColor(0.30, 0.18, 0.03, 1)
        pop.big:SetShadowOffset(2, -3)
        pop.big:SetPoint("CENTER", 0, 10)
        pop.sub = pop:CreateFontString(nil, "OVERLAY")
        Style.Font(pop.sub, "title", 20, Style.TEXT, "OUTLINE")
        pop.sub:SetPoint("TOP", pop.big, "BOTTOM", 0, -2)
        pop:Hide()
        self.turnPopup = pop
    end
    Yatzy.Style.SetText(pop.big, "Your turn!")
    Yatzy.Style.SetText(pop.sub, subtitle or "")
    pop.t = 0
    pop:SetAlpha(0)
    pop:Show()
    Yatzy.Sound:Play("chime")
    pop:SetScript("OnUpdate", function(f, elapsed)
        f.t = f.t + elapsed
        local t = f.t
        local alpha = math.min(1, t / 0.35)
        if t > TURN_POPUP_TIME - 0.8 then alpha = math.max(0, (TURN_POPUP_TIME - t) / 0.8) end
        f:SetAlpha(alpha)
        local rise = 14 * (1 - math.min(1, t / 0.5)) ^ 2          -- glides up 14 px into place
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 150 - rise)
        if t >= TURN_POPUP_TIME then
            f:SetScript("OnUpdate", nil)
            f:Hide()
        end
    end)
end
