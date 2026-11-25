-- Style.lua
-- The look from the prototype: textures, fonts, colours, and helpers that build
-- metal borders, leather panels, stitching and the red / leather buttons.
-- Textures are in Media\Textures (CC0 photos from Poly Haven + generated details),
-- fonts in Media\Fonts (Cinzel and Patrick Hand, both OFL).

local _, Yatzy = ...
local Style = {}
Yatzy.Style = Style

local MEDIA = "Interface\\AddOns\\Yatzy\\Media\\"
Style.TEX = {
    tableWood = MEDIA .. "Textures\\TableWood.tga",
    diceWood  = MEDIA .. "Textures\\DiceWood.tga",
    leather   = MEDIA .. "Textures\\Leather.tga",
    felt      = MEDIA .. "Textures\\Felt.tga",
    metal     = MEDIA .. "Textures\\Metal.tga",
    paper     = MEDIA .. "Textures\\Paper.tga",
    pip       = MEDIA .. "Textures\\Pip.tga",
    shadow    = MEDIA .. "Textures\\Shadow.tga",
    dieMask   = MEDIA .. "Textures\\DieMask.tga",
    stitchH   = MEDIA .. "Textures\\StitchH.tga",
    stitchV   = MEDIA .. "Textures\\StitchV.tga",
    rivet     = MEDIA .. "Textures\\Rivet.tga",
}
-- Pieces rendered from the browser prototype (tools/render-assets.ps1).
-- Each is drawn in the top-left corner of a power-of-two canvas: w/h = piece size,
-- cw/ch = canvas size (same units), so SetTexCoord can crop it.
local UI_DIR = MEDIA .. "Textures\\UI\\"
local function asset(file, w, h, cw, ch)
    return { file = UI_DIR .. file .. ".tga", w = w, h = h, cw = cw or w, ch = ch or h }
end
Style.TEX.ui = {
    dice    = { UI_DIR .. "Die1.tga", UI_DIR .. "Die2.tga", UI_DIR .. "Die3.tga", UI_DIR .. "Die4.tga", UI_DIR .. "Die5.tga" },
    pip     = UI_DIR .. "Pip.tga",
    dieGlow = UI_DIR .. "DieGlow.tga",
    softGlow = UI_DIR .. "SoftGlow.tga",
    cornerRound = UI_DIR .. "FrameCornerRound.tga",   -- 6x6 (in an 8x8 file): rounded frame corner
    -- softGlow: light from the middle; drawn at 2x, it fills its whole 512x128 file (texcoords 0-1)
    strike  = UI_DIR .. "Strike.tga",
    trash   = UI_DIR .. "Trash.tga",
    home    = UI_DIR .. "Home.tga",
    undo    = UI_DIR .. "Undo.tga",
    check   = UI_DIR .. "Check.tga",
    gear    = UI_DIR .. "Gear.tga",                          -- Settings button (title bars)
    speaker = { [0] = UI_DIR .. "SpeakerOff.tga", UI_DIR .. "Speaker1.tga",   -- Sound button: off,
                UI_DIR .. "Speaker2.tga", UI_DIR .. "Speaker3.tga" },        -- low, normal, high
    minimap = UI_DIR .. "MinimapIcon.tga",                   -- the minimap button: two dice
    rays    = UI_DIR .. "Rays.tga",
    -- game icons, 64x64 pieces drawn at 2x (start screen and the games list)
    gameIcon = { yatzy = UI_DIR .. "IconYatzy.tga", backgammon = UI_DIR .. "IconBackgammon.tga" },
    -- backgammon: checkers (52 of 64 px, centred a pixel high) and points (tip at the bottom)
    checkerRed = UI_DIR .. "CheckerRed.tga",
    checkerIvory = UI_DIR .. "CheckerIvory.tga",
    pointRed = UI_DIR .. "PointRed.tga",
    pointIvory = UI_DIR .. "PointIvory.tga",
    -- round player picture: gold ring + dark disc behind (Portrait.lua)
    portraitRing = UI_DIR .. "PortraitRing.tga",
    portraitBack = UI_DIR .. "PortraitBack.tga",
    tray    = asset("Tray", 262, 56, 512, 128),
    plaque  = asset("Plaque", 220, 26, 256, 32),
    tab     = asset("FoldTab", 24, 116, 32, 128),
    frameH  = asset("FrameH", 256, 6, 256, 8),
    frameV  = asset("FrameV", 6, 256, 8, 256),
    corner  = asset("FrameCorner", 32, 32),
    buttons = {
        primary170x44   = asset("BtnPrimary170x44", 170, 44, 256, 64),
        primary200x32   = asset("BtnPrimary200x32", 200, 32, 256, 32),
        primary130x26   = asset("BtnPrimary130x26", 130, 26, 256, 32),
        primary70x22    = asset("BtnPrimary70x22", 70, 22, 128, 32),
        primary220x44   = asset("BtnPrimary220x44", 220, 44, 256, 64),
        primary210x56   = asset("BtnPrimary210x56", 210, 56, 256, 64),
        secondary180x26 = asset("BtnSecondary180x26", 180, 26, 256, 32),
        secondary28x22  = asset("BtnSecondary28x22", 28, 22, 32, 32),
        secondary200x32 = asset("BtnSecondary200x32", 200, 32, 256, 32),
        secondary100x26 = asset("BtnSecondary100x26", 100, 26, 128, 32),
        secondary92x22  = asset("BtnSecondary92x22", 92, 22, 128, 32),
        secondary112x22 = asset("BtnSecondary112x22", 112, 22, 128, 32),
        secondary70x22  = asset("BtnSecondary70x22", 70, 22, 128, 32),
        secondary22x22  = asset("BtnSecondary22x22", 22, 22, 32, 32),
        secondary236x52 = asset("BtnSecondary236x52", 236, 52, 256, 64),   -- game cards (start screen)
    },
}

Style.FONT = {
    display = MEDIA .. "Fonts\\Cinzel.ttf",       -- small caps for titles, buttons, labels
    hand    = MEDIA .. "Fonts\\PatrickHand.ttf",  -- handwriting on the score sheet
    title   = "Fonts\\MORPHEUS.TTF",              -- WoW's own fantasy font: the game title
}

-- Colour tints (texture colour is multiplied by these)
Style.BRONZE  = { 0.95, 0.76, 0.48 }    -- metal texture -> aged bronze
Style.GOLD    = { 1.00, 0.84, 0.42 }    -- metal texture -> worn gold (dice rims)
Style.LEATHER = { 0.50, 0.42, 0.36 }    -- leather texture, darkened
Style.LEATHER_DARK = { 0.34, 0.28, 0.24 }
Style.RED     = { 0.78, 0.20, 0.13 }    -- leather texture -> red lacquer
Style.TEXT    = { 0.96, 0.89, 0.71 }    -- light parchment text
Style.TITLE   = { 1.00, 0.86, 0.52 }    -- gold headings

---------------------------------------------------------------------------
-- Textures and fonts
---------------------------------------------------------------------------

-- A texture that repeats (tiles) instead of stretching.
function Style.Tile(tex, file, color, alpha)
    tex:SetTexture(file, "REPEAT", "REPEAT")
    tex:SetHorizTile(true)
    tex:SetVertTile(true)
    if color then tex:SetVertexColor(color[1], color[2], color[3], alpha or 1) end
    return tex
end

function Style.Fill(frame, file, color, layer, sublevel)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
    t:SetAllPoints()
    Style.Tile(t, file, color)
    return t
end

function Style.Font(fs, kind, size, color, outline)
    fs:SetFont(Style.FONT[kind] or kind, size, outline or "")
    if not fs:GetFont() then
        fs:SetFont(STANDARD_TEXT_FONT, size, outline or "")   -- fallback if the font file can't load
    end
    if color then fs:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
    return fs
end

-- Custom font files load in the background the first time they're used; text set
-- before that can stay invisible. Using every font once at startup (hidden) makes
-- sure they're ready before any window is shown.
function Style.PreloadFonts()
    if Style.preloaded then return end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(1, 1)
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 100, -100)   -- off screen
    f:SetAlpha(0)
    for _, file in pairs(Style.FONT) do
        local fs = f:CreateFontString(nil, "OVERLAY")
        fs:SetFont(file, 12, "")
        fs:SetText("Yatzy 0123456789")
    end
    Style.preloaded = f
end

-- Set text so that it shows even if the font finished loading after the last call.
function Style.SetText(fs, text)
    fs:SetText("")
    fs:SetText(text or "")
end

-- Soft dark fade along an edge (vignette). Uses SetGradient if this client has it.
function Style.EdgeShade(frame, side, size, alpha)
    local t = frame:CreateTexture(nil, "BORDER", nil, 1)
    t:SetColorTexture(1, 1, 1, 1)
    if side == "TOP" then t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); t:SetHeight(size)
    elseif side == "BOTTOM" then t:SetPoint("BOTTOMLEFT"); t:SetPoint("BOTTOMRIGHT"); t:SetHeight(size)
    elseif side == "LEFT" then t:SetPoint("TOPLEFT"); t:SetPoint("BOTTOMLEFT"); t:SetWidth(size)
    else t:SetPoint("TOPRIGHT"); t:SetPoint("BOTTOMRIGHT"); t:SetWidth(size) end
    local ok = false
    if t.SetGradient and CreateColor then
        local dark, clear = CreateColor(0, 0, 0, alpha), CreateColor(0, 0, 0, 0)
        local orient = (side == "TOP" or side == "BOTTOM") and "VERTICAL" or "HORIZONTAL"
        -- VERTICAL goes bottom -> top, HORIZONTAL left -> right
        local fromC, toC = clear, dark
        if side == "BOTTOM" or side == "LEFT" then fromC, toC = dark, clear end
        ok = pcall(t.SetGradient, t, orient, fromC, toC)
    end
    if not ok then t:SetColorTexture(0, 0, 0, alpha * 0.4) end
    return t
end

---------------------------------------------------------------------------
-- Rendered pieces
---------------------------------------------------------------------------

-- Show a rendered piece (cropped from its canvas), stretched over the frame or `points`.
function Style.Image(frame, a, layer, sublevel)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
    t:SetAllPoints()
    t:SetTexture(a.file)
    t:SetTexCoord(0, a.w / a.cw, 0, a.h / a.ch)
    return t
end

-- The window's bevelled bronze frame from the prototype (top/bottom and sides mirrored).
function Style.WindowFrame(frame, size)
    local h, v = Style.TEX.ui.frameH, Style.TEX.ui.frameV
    local hy, vx = h.h / h.ch, v.w / v.cw
    local function band(a, points, l, r, t, b)
        local tex = frame:CreateTexture(nil, "BORDER", nil, 2)
        tex:SetTexture(a.file)
        tex:SetTexCoord(l, r, t, b)
        points(tex)
    end
    band(h, function(t) t:SetPoint("TOPLEFT", size, 0); t:SetPoint("TOPRIGHT", -size, 0); t:SetHeight(size) end, 0, 1, 0, hy)
    band(h, function(t) t:SetPoint("BOTTOMLEFT", size, 0); t:SetPoint("BOTTOMRIGHT", -size, 0); t:SetHeight(size) end, 0, 1, hy, 0)
    band(v, function(t) t:SetPoint("TOPLEFT", 0, -size); t:SetPoint("BOTTOMLEFT", 0, size); t:SetWidth(size) end, 0, vx, 0, 1)
    band(v, function(t) t:SetPoint("TOPRIGHT", 0, -size); t:SetPoint("BOTTOMRIGHT", 0, size); t:SetWidth(size) end, vx, 0, 0, 1)
    -- Slightly rounded corners (the same metal, mirrored for each corner)
    local c, e = Style.TEX.ui.cornerRound, 6 / 8
    for _, k in ipairs({ { "TOPLEFT", 0, e, 0, e }, { "TOPRIGHT", e, 0, 0, e },
                         { "BOTTOMLEFT", 0, e, e, 0 }, { "BOTTOMRIGHT", e, 0, e, 0 } }) do
        local tex = frame:CreateTexture(nil, "BORDER", nil, 2)
        tex:SetTexture(c)
        tex:SetTexCoord(k[2], k[3], k[4], k[5])
        tex:SetSize(size, size)
        tex:SetPoint(k[1])
    end
end

-- L-shaped metal corner plates with a rivet; `offset` < 0 sticks out past the edge.
function Style.FrameCorners(frame, size, offset)
    local c = Style.TEX.ui.corner
    local corners = {
        { "TOPLEFT", 0, 1, 0, 1, -1, 1 },
        { "TOPRIGHT", 1, 0, 0, 1, 1, 1 },
        { "BOTTOMLEFT", 0, 1, 1, 0, -1, -1 },
        { "BOTTOMRIGHT", 1, 0, 1, 0, 1, -1 },
    }
    for _, k in ipairs(corners) do
        local t = frame:CreateTexture(nil, "OVERLAY", nil, 5)
        t:SetTexture(c.file)
        t:SetTexCoord(k[2], k[3], k[4], k[5])
        t:SetSize(size, size)
        t:SetPoint(k[1], frame, k[1], -offset * k[6], -offset * k[7])
    end
end

---------------------------------------------------------------------------
-- Thin lines that never disappear
-- On a small screen or with a small UI/window scale, a 1-unit line is less than one
-- screen pixel, and WoW can round it away to nothing. Thin lines are therefore sized in
-- whole SCREEN pixels (at least 1), and sized again when the scale changes.
---------------------------------------------------------------------------

Style.thinLines = setmetatable({}, { __mode = "k" })    -- [texture] = { units, horizontal }

-- How many of this region's units one screen pixel is
function Style.Pixel(region)
    local ph = GetPhysicalScreenSize and select(2, GetPhysicalScreenSize())
    local es = region and region.GetEffectiveScale and region:GetEffectiveScale()
    if not ph or ph <= 0 or not es or es <= 0 then return 1 end
    return 768 / ph / es
end

local function applyThin(tex, units, horizontal)
    local px = Style.Pixel(tex)
    local size = math.max(1, math.floor(units / px + 0.5)) * px
    if horizontal then tex:SetHeight(size) else tex:SetWidth(size) end
end

-- `units` thick (1 = a hairline), horizontal = a line across (sets the height)
function Style.ThinLine(tex, units, horizontal)
    Style.thinLines[tex] = { units or 1, horizontal and true or false }
    applyThin(tex, units or 1, horizontal)
end

-- After the window/UI scale or the screen size changed
function Style.UpdateThinLines()
    for tex, spec in pairs(Style.thinLines) do applyThin(tex, spec[1], spec[2]) end
end

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("UI_SCALE_CHANGED")
    f:RegisterEvent("DISPLAY_SIZE_CHANGED")
    f:SetScript("OnEvent", function() Style.UpdateThinLines() end)
end

---------------------------------------------------------------------------
-- Metal border band (4 edges of tinted metal, light top edge, dark bottom edge)
---------------------------------------------------------------------------

function Style.MetalBorder(frame, size, color, layer)
    color = color or Style.BRONZE
    layer = layer or "BORDER"
    local parts = {}
    local function edge(points)
        local t = frame:CreateTexture(nil, layer, nil, 2)
        Style.Tile(t, Style.TEX.metal, color)
        points(t)
        parts[#parts + 1] = t
        return t
    end
    edge(function(t) t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); t:SetHeight(size) end)
    edge(function(t) t:SetPoint("BOTTOMLEFT"); t:SetPoint("BOTTOMRIGHT"); t:SetHeight(size) end)
    edge(function(t) t:SetPoint("TOPLEFT", 0, -size); t:SetPoint("BOTTOMLEFT", 0, size); t:SetWidth(size) end)
    edge(function(t) t:SetPoint("TOPRIGHT", 0, -size); t:SetPoint("BOTTOMRIGHT", 0, size); t:SetWidth(size) end)

    -- Bevel: a light line on top/left, a dark line on bottom/right, and a dark inner line
    local function line(r, g, b, a, points)
        local t = frame:CreateTexture(nil, layer, nil, 3)
        t:SetColorTexture(r, g, b, a)
        points(t)
        parts[#parts + 1] = t
    end
    line(1, 0.92, 0.75, 0.45, function(t) t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); Style.ThinLine(t, 1, true) end)
    line(1, 0.92, 0.75, 0.30, function(t) t:SetPoint("TOPLEFT"); t:SetPoint("BOTTOMLEFT"); Style.ThinLine(t, 1, false) end)
    line(0, 0, 0, 0.75, function(t) t:SetPoint("BOTTOMLEFT"); t:SetPoint("BOTTOMRIGHT"); Style.ThinLine(t, 1, true) end)
    line(0, 0, 0, 0.75, function(t) t:SetPoint("TOPRIGHT"); t:SetPoint("BOTTOMRIGHT"); Style.ThinLine(t, 1, false) end)
    if size >= 3 then
        line(0.04, 0.02, 0.01, 0.9, function(t) t:SetPoint("TOPLEFT", size, -size); t:SetPoint("TOPRIGHT", -size, -size); Style.ThinLine(t, 1, true) end)
        line(0.04, 0.02, 0.01, 0.9, function(t) t:SetPoint("BOTTOMLEFT", size, size); t:SetPoint("BOTTOMRIGHT", -size, size); Style.ThinLine(t, 1, true) end)
        line(0.04, 0.02, 0.01, 0.9, function(t) t:SetPoint("TOPLEFT", size, -size); t:SetPoint("BOTTOMLEFT", size, size); Style.ThinLine(t, 1, false) end)
        line(0.04, 0.02, 0.01, 0.9, function(t) t:SetPoint("TOPRIGHT", -size, -size); t:SetPoint("BOTTOMRIGHT", -size, size); Style.ThinLine(t, 1, false) end)
    end
    return parts
end

-- Rivets in the four corners
function Style.Rivets(frame, inset, size)
    for _, corner in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local t = frame:CreateTexture(nil, "OVERLAY", nil, 4)
        t:SetTexture(Style.TEX.rivet)
        t:SetSize(size or 10, size or 10)
        local x = corner:find("LEFT") and inset or -inset
        local y = corner:find("TOP") and -inset or inset
        t:SetPoint("CENTER", frame, corner, x, y)
    end
end

-- Stitched seam: dashed light line around a frame, `inset` pixels inside
function Style.Stitching(frame, inset, layer)
    local function seam(file, points)
        local t = frame:CreateTexture(nil, layer or "ARTWORK", nil, 1)
        t:SetTexture(file, "REPEAT", "REPEAT")
        t:SetHorizTile(true); t:SetVertTile(true)
        points(t)
    end
    seam(Style.TEX.stitchH, function(t) t:SetPoint("TOPLEFT", inset, -inset); t:SetPoint("TOPRIGHT", -inset, -inset); t:SetHeight(2) end)
    seam(Style.TEX.stitchH, function(t) t:SetPoint("BOTTOMLEFT", inset, inset); t:SetPoint("BOTTOMRIGHT", -inset, inset); t:SetHeight(2) end)
    seam(Style.TEX.stitchV, function(t) t:SetPoint("TOPLEFT", inset, -inset - 2); t:SetPoint("BOTTOMLEFT", inset, inset + 2); t:SetWidth(2) end)
    seam(Style.TEX.stitchV, function(t) t:SetPoint("TOPRIGHT", -inset, -inset - 2); t:SetPoint("BOTTOMRIGHT", -inset, inset + 2); t:SetWidth(2) end)
end

-- Dark leather panel with a thin bronze border and stitching
function Style.LeatherPanel(frame, opts)
    opts = opts or {}
    local bg = Style.Fill(frame, Style.TEX.leather, opts.color or Style.LEATHER_DARK)
    if opts.border ~= false then Style.MetalBorder(frame, opts.border or 2) end
    if opts.stitch then Style.Stitching(frame, opts.stitch) end
    return bg
end

---------------------------------------------------------------------------
-- Buttons: "primary" = red lacquer, "secondary" = dark leather; both with a metal rim
---------------------------------------------------------------------------

function Style.Button(parent, text, width, height, kind)
    kind = kind or "primary"
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height)
    local rim = 2
    local face

    local rendered = Style.TEX.ui.buttons[kind .. width .. "x" .. height]
    if rendered then
        -- The exact button from the browser prototype
        face = Style.Image(b, rendered)
    else
        -- Fallback for sizes without a rendered image
        face = b:CreateTexture(nil, "BACKGROUND")
        face:SetPoint("TOPLEFT", rim, -rim)
        face:SetPoint("BOTTOMRIGHT", -rim, rim)
        Style.Tile(face, Style.TEX.leather, kind == "secondary" and Style.LEATHER or Style.RED)
        local gloss = b:CreateTexture(nil, "ARTWORK", nil, -1)
        gloss:SetPoint("TOPLEFT", rim, -rim)
        gloss:SetPoint("BOTTOMRIGHT", b, "RIGHT", -rim, 0)
        gloss:SetColorTexture(1, 0.9, 0.85, kind == "secondary" and 0.05 or 0.10)
        Style.MetalBorder(b, rim)
    end
    b.face = face

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 3, -3)
    hl:SetPoint("BOTTOMRIGHT", -3, 3)
    hl:SetColorTexture(1, 0.85, 0.6, 0.10)

    local fs = b:CreateFontString(nil, "OVERLAY")
    Style.Font(fs, "display", height >= 40 and 15 or (height >= 30 and 13 or 11), Style.TEXT)
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetShadowOffset(0, -1)
    fs:SetPoint("CENTER")
    b:SetFontString(fs)
    b.label = fs
    b:SetPushedTextOffset(1, -1)
    b:SetText(text)

    b:SetScript("OnDisable", function()
        face:SetDesaturated(true)
        fs:SetTextColor(0.55, 0.52, 0.48)
    end)
    b:SetScript("OnEnable", function()
        face:SetDesaturated(false)
        fs:SetTextColor(Style.TEXT[1], Style.TEXT[2], Style.TEXT[3])
    end)
    -- A custom font file may not be loaded yet when the text is first set, which leaves
    -- the label blank. Setting the text again when the button appears fixes that.
    b:HookScript("OnShow", function(self)
        local t = self:GetText()
        if t and t ~= "" then self:SetText(""); self:SetText(t) end
    end)
    return b
end
