-- preview/wow.lua
-- A small fake World of Warcraft UI for the browser preview. It runs the addon's real
-- Lua files: frames, textures, text, anchors, mouse/keyboard, timers, events, guild roster
-- and addon messages between several fake players ("clients"). Drawing is done by the
-- page (host.js): every frame this file hands it a list of rectangles, images and texts.
--
-- Coordinates: "abs" units with the origin bottom-left, y up, screen height = 768 (like
-- WoW at scale 1). Pixels = abs * (screen pixel height / 768).

local W = {}
local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs

local S = {}          -- private key: obj[S] = internal state (the addon can't clash with it)
W.S = S

W.screen = { pxW = 1366, pxH = 768, uiScale = 1 }
W.clients = {}        -- [short name] = client
W.order = {}          -- client names in creation order
W.view = nil          -- the client drawn on screen and getting the mouse/keyboard
W.now = 0             -- seconds since start (GetTime)
W.layoutVersion = 0   -- bumps on every change that can move something
W.errors = {}
W.player = { combat = false, moving = false, taxi = false }
W.host = nil          -- set by main.lua: functions of the page (measure text, draw, sounds...)

local function bump() W.layoutVersion = W.layoutVersion + 1 end
W.bump = bump

function W.VirtualWidth() return 768 * W.screen.pxW / W.screen.pxH end
function W.PixelsPerUnit() return W.screen.pxH / 768 end

---------------------------------------------------------------------------
-- Errors (like WoW's Lua error popup, shown in the page)
---------------------------------------------------------------------------

function W.ReportError(msg)
    local text = tostring(msg)
    for _, e in ipairs(W.errors) do
        if e.text == text then e.count = e.count + 1; if W.host then W.host.error(text, e.count) end; return end
    end
    W.errors[#W.errors + 1] = { text = text, count = 1 }
    if W.host then W.host.error(text, 1) end
end

local function traceback(e) return debug.traceback(tostring(e), 2) end

-- Run a script handler; an error is reported but doesn't break the preview
local function safecall(fn, ...)
    local ok, err = xpcall(fn, traceback, ...)
    if not ok then W.ReportError(err) end
    return ok
end
W.safecall = safecall

---------------------------------------------------------------------------
-- Object model
---------------------------------------------------------------------------

local Region, Frame, Button, CheckButton, ScrollFrame, Texture, FontString, FontObject =
    {}, {}, {}, {}, {}, {}, {}, {}
setmetatable(Frame, { __index = Region })
setmetatable(Button, { __index = Frame })
setmetatable(CheckButton, { __index = Button })
setmetatable(ScrollFrame, { __index = Frame })
setmetatable(Texture, { __index = Region })
setmetatable(FontString, { __index = Region })
local META = {
    Frame = { __index = Frame }, Button = { __index = Button }, CheckButton = { __index = CheckButton },
    ScrollFrame = { __index = ScrollFrame }, Texture = { __index = Texture }, FontString = { __index = FontString },
    FontObject = { __index = FontObject },
}
local IS_A = {
    Frame = { Frame = true, Region = true, ScriptObject = true },
    Button = { Button = true, Frame = true, Region = true },
    CheckButton = { CheckButton = true, Button = true, Frame = true, Region = true },
    ScrollFrame = { ScrollFrame = true, Frame = true, Region = true },
    Texture = { Texture = true, Region = true, LayeredRegion = true },
    FontString = { FontString = true, Region = true, LayeredRegion = true },
}

local STRATA = { WORLD = 0, BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
                 FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local LAYER = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
local nextId = 0

local function newObject(client, kind, parent, isFrame)
    nextId = nextId + 1
    local o = setmetatable({}, META[kind])
    o[S] = { kind = kind, client = client, id = nextId, parent = parent, points = {}, shown = true,
             alpha = 1, scale = 1, isFrame = isFrame }
    return o
end

local function st(o) return o[S] end

---------------------------------------------------------------------------
-- Visibility, scale, alpha
---------------------------------------------------------------------------

-- (results are remembered until the next change anywhere: W.layoutVersion)
local function isVisible(o)
    local s = st(o)
    if s.visV == W.layoutVersion then return s.vis end
    local v
    if not s.shown then v = false
    elseif s.isRoot then v = true
    elseif not s.parent then v = false
    else v = isVisible(s.parent) end
    s.visV, s.vis = W.layoutVersion, v
    return v
end

local function effScale(o)
    local s = st(o)
    if s.esV == W.layoutVersion then return s.es end
    local v
    if s.isRoot then v = W.screen.uiScale * s.scale
    else
        local p = s.parent and effScale(s.parent) or W.screen.uiScale
        v = s.isFrame and p * s.scale or p
    end
    s.esV, s.es = W.layoutVersion, v
    return v
end

-- Like the game: a scroll frame draws its scroll child into a picture of its own and then
-- lays that picture on screen with the scroll frame's opacity. So the child's contents
-- get the window's fading twice, unless the child ignores its parents' opacity.
local function effAlpha(o)
    local s = st(o)
    local a = s.alpha
    if s.isRoot or not s.parent then return a end
    if s.scrollOwner then
        local owner = effAlpha(s.scrollOwner)
        return a * (s.ignoreParentAlpha and 1 or owner) * owner
    end
    if s.ignoreParentAlpha then return a end
    return a * effAlpha(s.parent)
end

---------------------------------------------------------------------------
-- Text measuring (by the page; cached)
---------------------------------------------------------------------------

local FONT_KEYS = {
    ["cinzel.ttf"] = "Cinzel", ["patrickhand.ttf"] = "PatrickHand", ["morpheus.ttf"] = "Morpheus",
    ["frizqt__.ttf"] = "Friz", ["arialn.ttf"] = "ArialN", ["skurri.ttf"] = "Skurri",
}
local function fontKey(path)
    if not path then return "Friz" end
    local file = tostring(path):lower():match("([^\\/]+)$") or ""
    return FONT_KEYS[file] or "Friz"
end
W.FontKey = fontKey

local widthCache = {}
local function textWidth(key, text)    -- width in "em" (multiply by the font size)
    local k = key .. "\0" .. text
    local w = widthCache[k]
    if not w then
        w = tonumber(W.host.textWidth(key, text)) or 0
        widthCache[k] = w
    end
    return w
end

local wrapCache = {}
local function wrapLines(key, size, text, width)
    local k = key .. "\0" .. size .. "\0" .. floor(width * 10) .. "\0" .. text
    local n = wrapCache[k]
    if not n then
        n = tonumber(W.host.wrapLines(key, size, text, width)) or 1
        wrapCache[k] = n
    end
    return n
end

local function plainText(text)
    return (tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "  "):gsub("||", "|"))
end

local function fsNaturalWidth(o)       -- own units
    local s = st(o)
    local text = s.text or ""
    if text == "" then return 0 end
    if s.nwText == text and s.nwFont == s.font and s.nwSize == s.fontSize then return s.nw end
    local best = 0
    for line in (plainText(text) .. "\n"):gmatch("(.-)\n") do
        best = max(best, textWidth(fontKey(s.font), line) * (s.fontSize or 12))
    end
    s.nwText, s.nwFont, s.nwSize, s.nw = text, s.font, s.fontSize, best
    return best
end

local function lineHeight(s) return (s.fontSize or 12) + (s.spacing or 0) end

local function fsLines(o, width)
    local s = st(o)
    local text = s.text or ""
    if text == "" then return 0 end
    if s.lnText == text and s.lnFont == s.font and s.lnSize == s.fontSize and s.lnWidth == width
        and s.lnWrap == s.wordWrap and s.lnMax == s.maxLines then
        return s.ln
    end
    local plain = plainText(text)
    local n
    if width and width > 0 and s.wordWrap ~= false then
        n = wrapLines(fontKey(s.font), s.fontSize or 12, plain, width)
        if s.maxLines and s.maxLines > 0 then n = min(n, s.maxLines) end
    else
        n = 1
        for _ in plain:gmatch("\n") do n = n + 1 end
    end
    s.lnText, s.lnFont, s.lnSize, s.lnWidth, s.lnWrap, s.lnMax, s.ln = text, s.font, s.fontSize, width, s.wordWrap, s.maxLines, n
    return n
end

---------------------------------------------------------------------------
-- Layout: resolve anchors to rectangles (abs units)
---------------------------------------------------------------------------

local PX = { TOPLEFT = 0, LEFT = 0, BOTTOMLEFT = 0, TOP = 0.5, CENTER = 0.5, BOTTOM = 0.5,
             TOPRIGHT = 1, RIGHT = 1, BOTTOMRIGHT = 1 }
local PY = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5,
             BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0 }

local resolving = {}

local rect   -- forward

-- Explicit or natural size in abs units (nil = not set)
local function ownWidth(o, es)
    local s = st(o)
    if s.w then return s.w * es end
    if s.kind == "FontString" then return fsNaturalWidth(o) * es end
    return nil
end

local function ownHeight(o, es, widthAbs)
    local s = st(o)
    if s.h then return s.h * es end
    if s.kind == "FontString" then
        local wUnits = widthAbs and (widthAbs / es) or nil
        if not s.w and not s.twoX then wUnits = nil end
        return fsLines(o, wUnits) * lineHeight(s) * es
    end
    return nil
end

-- Returns left, bottom, width, height (abs) or nil when it can't be placed.
rect = function(o)
    local s = st(o)
    if s.rcV == W.layoutVersion then
        if s.rcOk then return s.rl, s.rb, s.rw, s.rh end
        return nil
    end
    if s.isRoot then
        local vw = W.VirtualWidth()
        s.rcV, s.rcOk, s.rl, s.rb, s.rw, s.rh = W.layoutVersion, true, 0, 0, vw, 768
        return 0, 0, vw, 768
    end
    if resolving[o] then return nil end   -- anchor loop
    resolving[o] = true

    local es = effScale(o)
    local L, R, CX, T, B, CY
    local ok = true

    -- the scroll child sits at the scroll frame's top-left, moved by the scroll offset
    if s.scrollOwner then
        local sl, sb, sw, sh = rect(s.scrollOwner)
        if sl then
            local os = st(s.scrollOwner)
            L = sl - (os.hscroll or 0) * effScale(s.scrollOwner)
            T = sb + sh + (os.vscroll or 0) * effScale(s.scrollOwner)
        else ok = false end
    else
        if #s.points == 0 then ok = false end
        for _, p in ipairs(s.points) do
            local rel = p.rel
            if rel == nil then rel = s.parent end
            if rel then
                local rl, rb, rw, rh = rect(rel)
                if rl then
                    local ax = rl + rw * PX[p.relPoint] + p.x * es
                    local ay = rb + rh * PY[p.relPoint] + p.y * es
                    local hx, vy = PX[p.point], PY[p.point]
                    -- when two anchors give the same edge, the first one counts (like the game)
                    if hx == 0 then L = L or ax elseif hx == 1 then R = R or ax else CX = CX or ax end
                    if vy == 1 then T = T or ay elseif vy == 0 then B = B or ay else CY = CY or ay end
                else ok = false end
            else ok = false end
        end
    end

    local l, b, w, h
    if ok then
        s.twoX = (L ~= nil and R ~= nil)
        if L and R then l, w = L, R - L
        else
            w = ownWidth(o, es) or 0
            if L then l = L elseif R then l = R - w elseif CX then l = CX - w / 2 else ok = false end
        end
        if ok then
            if T and B then b, h = B, T - B
            else
                h = ownHeight(o, es, w) or 0
                if T then b = T - h elseif B then b = B elseif CY then b = CY - h / 2 else ok = false end
            end
        end
    end
    resolving[o] = nil
    if ok then
        if w < 0 then w = 0 end
        if h < 0 then h = 0 end
        s.rcV, s.rcOk, s.rl, s.rb, s.rw, s.rh = W.layoutVersion, true, l, b, w, h
        return l, b, w, h
    end
    s.rcV, s.rcOk = W.layoutVersion, false
    return nil
end
W.Rect = rect

---------------------------------------------------------------------------
-- Region methods (frames, textures and font strings)
---------------------------------------------------------------------------

local function toObj(client, rel)
    if type(rel) == "string" then return client.env[rel] end
    return rel
end

function Region:SetPoint(point, a, b, c, d)
    local s = st(self)
    point = (point or "CENTER"):upper()
    local rel, relPoint, x, y
    if type(a) == "number" or a == nil and b == nil then
        rel, relPoint, x, y = nil, point, a or 0, b or 0
    elseif type(b) == "number" then        -- SetPoint(point, rel, x, y)  (rare form)
        rel, relPoint, x, y = a, point, b, c or 0
    else
        rel, relPoint, x, y = a, (b or point):upper(), c or 0, d or 0
    end
    rel = toObj(s.client, rel)
    if rel == nil and a ~= nil and type(a) ~= "number" then rel = s.parent end
    if rel == self then error("SetPoint: a region can't be anchored to itself", 2) end
    for i, p in ipairs(s.points) do
        if p.point == point then
            if p.rel == rel and p.relPoint == relPoint and p.x == x and p.y == y then return end  -- no change
            table.remove(s.points, i); break
        end
    end
    s.points[#s.points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
    bump()
end

function Region:SetAllPoints(rel)
    local s = st(self)
    rel = toObj(s.client, rel) or s.parent
    s.points = {
        { point = "TOPLEFT", rel = rel, relPoint = "TOPLEFT", x = 0, y = 0 },
        { point = "BOTTOMRIGHT", rel = rel, relPoint = "BOTTOMRIGHT", x = 0, y = 0 },
    }
    bump()
end

function Region:ClearAllPoints() st(self).points = {}; bump() end
function Region:ClearPoint(point)
    local s = st(self)
    for i, p in ipairs(s.points) do if p.point == point then table.remove(s.points, i); break end end
    bump()
end
function Region:GetNumPoints() return #st(self).points end
function Region:GetPoint(i)
    local p = st(self).points[i or 1]
    if not p then return nil end
    return p.point, p.rel, p.relPoint, p.x, p.y
end

function Region:SetSize(w, h) local s = st(self); if s.w ~= w or s.h ~= h then s.w, s.h = w, h; bump() end end
function Region:SetWidth(w) local s = st(self); if s.w ~= w then s.w = w; bump() end end
function Region:SetHeight(h) local s = st(self); if s.h ~= h then s.h = h; bump() end end
function Region:GetWidth()
    local s = st(self)
    local l, _, w = rect(self)
    if l then return w / effScale(self) end
    return s.w or (s.kind == "FontString" and fsNaturalWidth(self)) or 0
end
function Region:GetHeight()
    local s = st(self)
    local l, _, _, h = rect(self)
    if l then return h / effScale(self) end
    return s.h or 0
end
function Region:GetSize() return self:GetWidth(), self:GetHeight() end
function Region:GetRect()
    local l, b, w, h = rect(self)
    if not l then return nil end
    local es = effScale(self)
    return l / es, b / es, w / es, h / es
end
function Region:GetLeft() local l = rect(self); if l then return l / effScale(self) end end
function Region:GetRight() local l, _, w = rect(self); if l then return (l + w) / effScale(self) end end
function Region:GetBottom() local l, b = rect(self); if l then return b / effScale(self) end end
function Region:GetTop() local l, b, _, h = rect(self); if l then return (b + h) / effScale(self) end end
function Region:GetCenter()
    local l, b, w, h = rect(self)
    if not l then return nil end
    local es = effScale(self)
    return (l + w / 2) / es, (b + h / 2) / es
end

local fireShowHide  -- forward

function Region:Show()
    local s = st(self)
    if s.shown then return end
    local wasVisible = s.parent and isVisible(s.parent) and false
    s.shown = true
    bump()
    if s.isFrame and isVisible(self) then fireShowHide(self, "OnShow") end
end
function Region:Hide()
    local s = st(self)
    if not s.shown then return end
    local was = isVisible(self)
    s.shown = false
    bump()
    if s.isFrame and was then fireShowHide(self, "OnHide") end
end
function Region:SetShown(v) if v then self:Show() else self:Hide() end end
function Region:IsShown() return st(self).shown end
function Region:IsVisible() return isVisible(self) end

function Region:SetAlpha(a)
    local s = st(self)
    a = max(0, min(1, a or 1))
    if s.alpha ~= a then s.alpha = a; W.visualVersion = W.visualVersion + 1 end
end
function Region:GetAlpha() return st(self).alpha end
function Region:GetEffectiveAlpha() return effAlpha(self) end
function Region:SetIgnoreParentAlpha(v) st(self).ignoreParentAlpha = v and true or false end
function Region:IsIgnoringParentAlpha() return st(self).ignoreParentAlpha or false end
function Region:GetEffectiveScale() return effScale(self) end
function Region:GetParent() return st(self).parent end
function Region:GetName() return st(self).name end
function Region:GetDebugName() return st(self).name or tostring(st(self).kind) end
function Region:GetObjectType() return st(self).kind end
function Region:IsObjectType(t) return IS_A[st(self).kind][t] or false end
function Region:IsForbidden() return false end
function Region:IsProtected() return false end
function Region:IsAnchoringRestricted() return false end

function Region:IsMouseOver(top, bottom, left, right)
    local s = st(self)
    if not isVisible(self) then return false end
    local l, b, w, h = rect(self)
    if not l then return false end
    local m = s.client.mouse
    local es = effScale(self)
    return m.x >= l - (left or 0) * es and m.x <= l + w + (right or 0) * es
       and m.y >= b - (bottom or 0) * es and m.y <= b + h + (top or 0) * es
end

---------------------------------------------------------------------------
-- Layered regions (textures, font strings)
---------------------------------------------------------------------------

local function setLayer(o, layer, sub)
    local s = st(o)
    s.layer = LAYER[(layer or "ARTWORK"):upper()] and (layer or "ARTWORK"):upper() or "ARTWORK"
    s.sublevel = sub or 0
    if s.parent then st(s.parent).sortedRegions = nil end
end
function Texture:SetDrawLayer(layer, sub) setLayer(self, layer, sub) end
function FontString:SetDrawLayer(layer, sub) setLayer(self, layer, sub) end
function Texture:GetDrawLayer() local s = st(self); return s.layer, s.sublevel end
function FontString:GetDrawLayer() local s = st(self); return s.layer, s.sublevel end

function Region:SetParent(p)
    local s = st(self)
    local old = s.parent
    if old == p then return end
    local wasVisible = s.isFrame and isVisible(self)
    if old then st(old).sortedRegions = nil end
    if p then st(p).sortedRegions = nil end
    if old then
        local list = s.isFrame and st(old).children or st(old).regions
        for i, x in ipairs(list) do if x == self then table.remove(list, i); break end end
    end
    s.parent = p
    if p then
        local ps = st(p)
        if s.isFrame then ps.children[#ps.children + 1] = self else ps.regions[#ps.regions + 1] = self end
    end
    bump()
    if s.isFrame then
        local nowVisible = isVisible(self)
        if wasVisible and not nowVisible then fireShowHide(self, "OnHide")
        elseif nowVisible and not wasVisible then fireShowHide(self, "OnShow") end
    end
end

-- Textures -----------------------------------------------------------------

function Texture:SetTexture(file, wrapH, wrapV)
    local s = st(self)
    s.color, s.gradient = nil, nil
    if type(file) == "number" then file = "fileid:" .. file end
    s.file = file
    s.wrapH, s.wrapV = wrapH, wrapV
    return file ~= nil
end
function Texture:GetTexture() local s = st(self); return s.file or (s.color and "color") end
function Texture:SetColorTexture(r, g, b, a)
    local s = st(self)
    s.file, s.gradient = nil, nil
    s.color = { r or 1, g or 1, b or 1, a or 1 }
end
function Texture:SetGradient(orient, c1, c2, ...)
    local s = st(self)
    if type(c1) == "number" then   -- old form: orient, r1,g1,b1, r2,g2,b2
        local r1, g1, b1, r2, g2, b2 = c1, c2, ...
        c1 = { r = r1, g = g1, b = b1, a = 1 }; c2 = { r = r2, g = g2, b = b2, a = 1 }
    end
    local function rgba(c)
        if c.GetRGBA then return { c:GetRGBA() } end
        return { c.r or 1, c.g or 1, c.b or 1, c.a or 1 }
    end
    s.gradient = { orient = (orient or "HORIZONTAL"):upper(), from = rgba(c1), to = rgba(c2) }
end
function Texture:SetTexCoord(a, b, c, d, e, f, g, h)
    local s = st(self)
    if e then          -- 8 values: corners UL, LL, UR, LR (use UL and LR)
        s.tc = { a, g, b, h }
    else
        s.tc = { a or 0, b or 1, c or 0, d or 1 }
    end
end
function Texture:GetTexCoord()
    local t = st(self).tc or { 0, 1, 0, 1 }
    return t[1], t[3], t[1], t[4], t[2], t[3], t[2], t[4]
end
function Texture:SetVertexColor(r, g, b, a) st(self).vc = { r or 1, g or 1, b or 1, a or 1 } end
function Texture:GetVertexColor() local v = st(self).vc or { 1, 1, 1, 1 }; return v[1], v[2], v[3], v[4] end
function Texture:SetDesaturated(v) st(self).desat = v and true or false end
function Texture:IsDesaturated() return st(self).desat or false end
function Texture:SetDesaturation(v) st(self).desat = (v or 0) > 0.5 end
function Texture:SetBlendMode(m) st(self).blend = m end
function Texture:GetBlendMode() return st(self).blend or "BLEND" end
function Texture:SetRotation(r) st(self).rot = r or 0 end
function Texture:GetRotation() return st(self).rot or 0 end
function Texture:SetHorizTile(v) st(self).tileH = v and true or false end
function Texture:SetVertTile(v) st(self).tileV = v and true or false end
function Texture:GetHorizTile() return st(self).tileH or false end
function Texture:GetVertTile() return st(self).tileV or false end
function Texture:SetSnapToPixelGrid() end
function Texture:SetTexelSnappingBias() end
function Texture:SetAtlas(name) st(self).file = "atlas:" .. tostring(name) end

-- Font strings ---------------------------------------------------------------

local function applyFontObject(fs, fo)
    local s, f = st(fs), st(fo)
    s.font, s.fontSize, s.fontFlags = f.font, f.fontSize, f.fontFlags
    if f.color then s.textColor = { f.color[1], f.color[2], f.color[3], f.color[4] } end
    if f.shadow then s.shadowColor = { unpack(f.shadow) }; s.shadowOffset = { unpack(f.shadowOffset) } end
    if f.justifyH then s.justifyH = f.justifyH end
    s.fontObject = fo
end

function FontString:SetFont(path, size, flags)
    local s = st(self)
    s.font, s.fontSize, s.fontFlags = path, size or 12, flags or ""
    bump()
    return true
end
function FontString:GetFont()
    local s = st(self)
    if not s.font then return nil end
    return s.font, s.fontSize, s.fontFlags
end
function FontString:SetFontObject(fo)
    if type(fo) == "string" then fo = st(self).client.env[fo] end
    if fo then applyFontObject(self, fo); bump() end
end
function FontString:GetFontObject() return st(self).fontObject end
function FontString:SetText(t)
    local s = st(self)
    if t ~= nil then t = tostring(t) end
    if s.text ~= t then s.text = t; bump() end
end
function FontString:SetFormattedText(fmt, ...) self:SetText(fmt:format(...)) end
function FontString:GetText() return st(self).text end
function FontString:SetTextColor(r, g, b, a) st(self).textColor = { r or 1, g or 1, b or 1, a or 1 } end
function FontString:GetTextColor() local c = st(self).textColor or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function FontString:SetShadowColor(r, g, b, a) st(self).shadowColor = { r or 0, g or 0, b or 0, a or 1 } end
function FontString:GetShadowColor() local c = st(self).shadowColor or { 0, 0, 0, 0 }; return c[1], c[2], c[3], c[4] end
function FontString:SetShadowOffset(x, y) st(self).shadowOffset = { x or 0, y or 0 } end
function FontString:GetShadowOffset() local o = st(self).shadowOffset or { 0, 0 }; return o[1], o[2] end
function FontString:SetJustifyH(j) st(self).justifyH = (j or "CENTER"):upper() end
function FontString:SetJustifyV(j) st(self).justifyV = (j or "MIDDLE"):upper() end
function FontString:GetJustifyH() return st(self).justifyH or "CENTER" end
function FontString:GetJustifyV() return st(self).justifyV or "MIDDLE" end
function FontString:SetWordWrap(v) st(self).wordWrap = v and true or false; bump() end
function FontString:GetWordWrap() return st(self).wordWrap ~= false end
function FontString:SetNonSpaceWrap() end
function FontString:SetIndentedWordWrap() end
function FontString:SetMaxLines(n) st(self).maxLines = n; bump() end
function FontString:SetSpacing(n) st(self).spacing = n; bump() end
function FontString:GetSpacing() return st(self).spacing or 0 end
function FontString:GetStringWidth() return fsNaturalWidth(self) end
function FontString:GetUnboundedStringWidth() return fsNaturalWidth(self) end
function FontString:GetStringHeight()
    local s = st(self)
    local l, _, w = rect(self)
    local width = (l and (s.w or s.twoX)) and (w / effScale(self)) or nil
    return fsLines(self, width) * lineHeight(s)
end
function FontString:GetNumLines()
    local s = st(self)
    local l, _, w = rect(self)
    local width = (l and (s.w or s.twoX)) and (w / effScale(self)) or nil
    return fsLines(self, width)
end
function FontString:IsTruncated() return false end
function FontString:SetTextScale() end

-- Font objects (GameFontNormal & co, CreateFont) ----------------------------

function FontObject:SetFont(path, size, flags) local s = st(self); s.font, s.fontSize, s.fontFlags = path, size, flags or "" end
function FontObject:GetFont() local s = st(self); return s.font, s.fontSize, s.fontFlags end
function FontObject:SetTextColor(r, g, b, a) st(self).color = { r, g, b, a or 1 } end
function FontObject:GetTextColor() local c = st(self).color or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function FontObject:SetShadowColor(r, g, b, a) st(self).shadow = { r, g, b, a or 1 } end
function FontObject:SetShadowOffset(x, y) st(self).shadowOffset = { x, y } end
function FontObject:SetJustifyH(j) st(self).justifyH = j end
function FontObject:CopyFontObject(o)
    local s, f = st(self), st(type(o) == "string" and s.client.env[o] or o)
    s.font, s.fontSize, s.fontFlags, s.color = f.font, f.fontSize, f.fontFlags, f.color
end
function FontObject:GetName() return st(self).name end
function FontObject:IsObjectType(t) return t == "Font" end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local SCRIPT_NAMES_MOUSE = {}

function Frame:CreateTexture(name, layer, template, sub)
    local s = st(self)
    local t = newObject(s.client, "Texture", self, false)
    setLayer(t, layer, sub)
    s.regions[#s.regions + 1] = t
    if name then st(t).name = name; s.client.env[name] = t end
    return t
end
function Frame:CreateMaskTexture(name, layer)
    return self:CreateTexture(name, layer or "ARTWORK")
end
function Frame:CreateLine(name, layer) return self:CreateTexture(name, layer) end
function Frame:CreateFontString(name, layer, template)
    local s = st(self)
    local fs = newObject(s.client, "FontString", self, false)
    setLayer(fs, layer or "ARTWORK", 0)
    local fsS = st(fs)
    fsS.justifyH, fsS.justifyV = "CENTER", "MIDDLE"
    if template then
        local fo = s.client.env[template]
        if fo then applyFontObject(fs, fo) end
    end
    s.regions[#s.regions + 1] = fs
    if name then fsS.name = name; s.client.env[name] = fs end
    return fs
end
function Frame:CreateAnimationGroup()
    -- Not used by the addon; a harmless stand-in so a call doesn't break the preview.
    local ag = { Play = function() end, Stop = function() end, IsPlaying = function() return false end,
                 SetLooping = function() end, SetScript = function() end }
    ag.CreateAnimation = function()
        return setmetatable({}, { __index = function() return function() end end })
    end
    return ag
end

function Frame:GetChildren() return unpack(st(self).children) end
function Frame:GetNumChildren() return #st(self).children end
function Frame:GetRegions() return unpack(st(self).regions) end

function Frame:SetScale(v) st(self).scale = v or 1; bump() end
function Frame:GetScale() return st(self).scale end

function Frame:SetFrameStrata(strata) st(self).strata = STRATA[strata] and strata or "MEDIUM"; bump() end
local function effStrata(o)
    local s = st(o)
    while s do
        if s.strata then return s.strata end
        if not s.parent then return "MEDIUM" end
        s = st(s.parent)
    end
    return "MEDIUM"
end
local function effLevel(o)
    local s = st(o)
    if s.level then return s.level end
    if s.parent then
        local ps = st(s.parent)
        if ps.isRoot then return 1 end
        -- a child in another strata starts again near the bottom
        if s.strata and s.strata ~= effStrata(s.parent) then return 1 end
        return effLevel(s.parent) + 1
    end
    return 0
end
function Frame:GetFrameStrata() return effStrata(self) end
function Frame:SetFrameLevel(n) local s = st(self); if s.level ~= n then s.level = n; bump() end end
function Frame:GetFrameLevel() return effLevel(self) end
function Frame:SetToplevel(v) st(self).toplevel = v end
-- Like WoW: above every other frame in the same strata; children that have their own
-- level move along with it.
local function isDescendant(f, root)
    local s = st(f)
    while s and s.parent do
        if s.parent == root then return true end
        s = st(s.parent)
    end
    return false
end
function Frame:Raise()
    local s = st(self)
    local strata, mine, top = effStrata(self), effLevel(self), 0
    for _, f in ipairs(s.client.frames) do
        if f ~= self and not st(f).isRoot and effStrata(f) == strata and not isDescendant(f, self) then
            top = math.max(top, effLevel(f))
        end
    end
    if top < mine then return end
    local delta = top + 1 - mine
    for _, f in ipairs(s.client.frames) do
        local fs = st(f)
        if fs.level and isDescendant(f, self) then fs.level = fs.level + delta end
    end
    s.level = mine + delta
    bump()
end
function Frame:Lower() end
function Frame:SetFixedFrameStrata() end
function Frame:SetFixedFrameLevel() end

function Frame:SetClipsChildren(v) st(self).clips = v and true or false end
function Frame:DoesClipChildren() return st(self).clips or false end

function Frame:EnableMouse(v) st(self).mouse = v and true or false end
function Frame:IsMouseEnabled() return st(self).mouse or false end
function Frame:EnableMouseWheel(v) st(self).wheel = v and true or false end
function Frame:IsMouseWheelEnabled() return st(self).wheel or false end
function Frame:EnableMouseMotion(v) st(self).mouse = v and true or false end
function Frame:SetMouseClickEnabled(v) st(self).mouse = v and true or false end
function Frame:SetMouseMotionEnabled(v) if v then st(self).mouse = true end end
function Frame:SetPassThroughButtons() end
function Frame:SetHitRectInsets(l, r, t, b) st(self).hitInsets = { l or 0, r or 0, t or 0, b or 0 } end
function Frame:EnableKeyboard(v) st(self).keyboard = v and true or false end
function Frame:IsKeyboardEnabled() return st(self).keyboard or false end
function Frame:SetPropagateKeyboardInput(v) st(self).propagate = v and true or false end
function Frame:GetPropagateKeyboardInput() return st(self).propagate or false end

function Frame:SetMovable(v) st(self).movable = v end
function Frame:IsMovable() return st(self).movable or false end
function Frame:SetResizable(v) st(self).resizable = v end
function Frame:IsResizable() return st(self).resizable or false end
function Frame:SetClampedToScreen(v) st(self).clamped = v end
function Frame:IsClampedToScreen() return st(self).clamped or false end
function Frame:SetClampRectInsets() end
function Frame:SetUserPlaced() end
function Frame:IsUserPlaced() return false end
function Frame:SetDontSavePosition() end
function Frame:SetResizeBounds(minW, minH, maxW, maxH)
    st(self).bounds = { minW or 0, minH or 0, maxW or 100000, maxH or 100000 }
end
function Frame:GetResizeBounds() local b = st(self).bounds or { 0, 0, 100000, 100000 }; return b[1], b[2], b[3], b[4] end
-- (SetMinResize/SetMaxResize were removed from the modern client: left out on purpose)
function Frame:RegisterForDrag(...) st(self).drag = { ... } end
function Frame:StartMoving()
    local s = st(self)
    local l, b, w, h = rect(self)
    if not l then return end
    local m = s.client.mouse
    s.client.moving = { frame = self, dx = m.x - l, dy = m.y - (b + h) }
end
function Frame:StartSizing(point)
    local s = st(self)
    local l, b, w, h = rect(self)
    if not l then return end
    local m = s.client.mouse
    s.client.sizing = { frame = self, point = (point or "BOTTOMRIGHT"):upper(), l = l, b = b, w = w, h = h, mx = m.x, my = m.y }
end
function Frame:StopMovingOrSizing()
    local c = st(self).client
    if c.moving and c.moving.frame == self then c.moving = nil end
    if c.sizing and c.sizing.frame == self then c.sizing = nil end
end

function Frame:RegisterEvent(e) local s = st(self); s.events[e] = true end
function Frame:UnregisterEvent(e) st(self).events[e] = nil end
function Frame:RegisterAllEvents() st(self).allEvents = true end
function Frame:UnregisterAllEvents() local s = st(self); s.events = {}; s.allEvents = nil end
function Frame:IsEventRegistered(e) return st(self).events[e] or false end
function Frame:RegisterUnitEvent(e) st(self).events[e] = true end

function Frame:SetScript(name, fn)
    local s = st(self)
    s.scripts[name] = fn
end
function Frame:GetScript(name) return st(self).scripts[name] end
function Frame:HasScript() return true end
function Frame:HookScript(name, fn)
    local s = st(self)
    s.hooks[name] = s.hooks[name] or {}
    table.insert(s.hooks[name], fn)
end

-- Run a frame's script (and its hooks). Returns true if anything ran.
local function runScript(o, name, ...)
    local s = st(o)
    local fn, hooks = s.scripts[name], s.hooks[name]
    if not fn and not hooks then return false end
    if fn then safecall(fn, o, ...) end
    if hooks then for _, h in ipairs(hooks) do safecall(h, o, ...) end end
    return true
end
W.RunScript = runScript

fireShowHide = function(o, name)
    runScript(o, name)
    for _, c in ipairs(st(o).children) do
        if st(c).shown then fireShowHide(c, name) end
    end
end

-- Buttons --------------------------------------------------------------------

function Button:SetText(t)
    local s = st(self)
    if not s.fontString then
        local fs = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("CENTER")
        s.fontString = fs
    end
    s.fontString:SetText(t)
end
function Button:GetText() local fs = st(self).fontString; return fs and fs:GetText() end
function Button:SetFormattedText(fmt, ...) self:SetText(fmt:format(...)) end
function Button:SetFontString(fs) st(self).fontString = fs end
function Button:GetFontString() return st(self).fontString end
function Button:SetNormalFontObject(fo) local fs = st(self).fontString; if fs then fs:SetFontObject(fo) end end
function Button:SetHighlightFontObject() end
function Button:SetDisabledFontObject() end
function Button:GetTextWidth() local fs = st(self).fontString; return fs and fs:GetStringWidth() or 0 end
function Button:Enable() self:SetEnabled(true) end
function Button:Disable() self:SetEnabled(false) end
function Button:SetEnabled(v)
    local s = st(self)
    v = v and true or false
    if s.enabled == v then return end
    s.enabled = v
    runScript(self, v and "OnEnable" or "OnDisable")
end
function Button:IsEnabled() return st(self).enabled end
function Button:RegisterForClicks(...) st(self).clicks = { ... } end
function Button:SetPushedTextOffset(x, y) st(self).pushedOffset = { x or 0, y or 0 } end
function Button:SetMotionScriptsWhileDisabled(v) st(self).motionDisabled = v end
function Button:LockHighlight() st(self).lockHL = true end
function Button:UnlockHighlight() st(self).lockHL = false end
function Button:SetButtonState(state) st(self).pushed = (state == "PUSHED") end
function Button:GetButtonState() return st(self).pushed and "PUSHED" or "NORMAL" end
function Button:Click(button)
    local s = st(self)
    if not s.enabled then return end
    if s.kind == "CheckButton" then s.checked = not s.checked end
    runScript(self, "OnClick", button or "LeftButton", false)
end

local function buttonTexture(self, key, tex, layer)
    local s = st(self)
    if type(tex) == "string" or type(tex) == "number" then
        local t = s[key] or self:CreateTexture(nil, layer)
        t:SetTexture(tex)
        t:ClearAllPoints(); t:SetAllPoints(self)
        tex = t
    end
    if tex then setLayer(tex, layer, st(tex).sublevel or 0) end
    s[key] = tex
    return tex
end
function Button:SetHighlightTexture(tex, blend)
    local t = buttonTexture(self, "hlTex", tex, "HIGHLIGHT")
    if t and blend then t:SetBlendMode(blend) elseif t and type(tex) == "string" then t:SetBlendMode("ADD") end
end
function Button:GetHighlightTexture() return st(self).hlTex end
function Button:SetNormalTexture(tex) buttonTexture(self, "normalTex", tex, "ARTWORK") end
function Button:GetNormalTexture() return st(self).normalTex end
function Button:SetPushedTexture(tex)
    local t = buttonTexture(self, "pushedTex", tex, "ARTWORK")
    if t then t:Hide() end
end
function Button:GetPushedTexture() return st(self).pushedTex end
function Button:SetDisabledTexture(tex)
    local t = buttonTexture(self, "disabledTex", tex, "ARTWORK")
    if t then t:Hide() end
end
function Button:GetDisabledTexture() return st(self).disabledTex end

function CheckButton:SetChecked(v) st(self).checked = v and true or false end
function CheckButton:GetChecked() return st(self).checked or false end
function CheckButton:SetCheckedTexture(tex) buttonTexture(self, "checkedTex", tex, "OVERLAY") end
function CheckButton:GetCheckedTexture() return st(self).checkedTex end
function CheckButton:SetDisabledCheckedTexture() end

-- Scroll frames --------------------------------------------------------------

function ScrollFrame:SetScrollChild(child)
    local s = st(self)
    if s.scrollChild then st(s.scrollChild).scrollOwner = nil end
    s.scrollChild = child
    if child then
        if st(child).parent ~= self then child:SetParent(self) end
        st(child).scrollOwner = self
    end
    bump()
end
function ScrollFrame:GetScrollChild() return st(self).scrollChild end
function ScrollFrame:SetVerticalScroll(v) st(self).vscroll = v or 0; bump(); runScript(self, "OnVerticalScroll", v or 0) end
function ScrollFrame:GetVerticalScroll() return st(self).vscroll or 0 end
function ScrollFrame:SetHorizontalScroll(v) st(self).hscroll = v or 0; bump() end
function ScrollFrame:GetHorizontalScroll() return st(self).hscroll or 0 end
function ScrollFrame:GetVerticalScrollRange()
    local s = st(self)
    if not s.scrollChild then return 0 end
    return max(0, s.scrollChild:GetHeight() - self:GetHeight())
end
function ScrollFrame:GetHorizontalScrollRange()
    local s = st(self)
    if not s.scrollChild then return 0 end
    return max(0, s.scrollChild:GetWidth() - self:GetWidth())
end
function ScrollFrame:UpdateScrollChildRect() end

---------------------------------------------------------------------------
-- Creating frames
---------------------------------------------------------------------------

local TEMPLATES = {}

-- A plain look for Blizzard's check box (we don't use Blizzard's art)
TEMPLATES.UICheckButtonTemplate = function(cb)
    cb:SetSize(26, 26)
    local box = cb:CreateTexture(nil, "BACKGROUND")
    box:SetPoint("TOPLEFT", 5, -5); box:SetPoint("BOTTOMRIGHT", -5, 5)
    box:SetColorTexture(0.05, 0.04, 0.03, 0.9)
    local edge = cb:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT", 4, -4); edge:SetPoint("BOTTOMRIGHT", -4, 4)
    edge:SetColorTexture(0.75, 0.6, 0.35, 0.9)
    setLayer(box, "BORDER", 1)
    local check = cb:CreateFontString(nil, "OVERLAY")
    check:SetFont("Fonts\\FRIZQT__.TTF", 16, "")
    check:SetTextColor(1, 0.82, 0)
    check:SetPoint("CENTER", 1, 1)
    check:SetText("\226\156\147")   -- check mark
    st(cb).checkMark = check
    st(check).checkFor = cb          -- only drawn while the box is checked
    local hl = cb:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 4, -4); hl:SetPoint("BOTTOMRIGHT", -4, 4)
    hl:SetColorTexture(1, 0.9, 0.6, 0.15)
    local text = cb:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    text:SetPoint("LEFT", cb, "RIGHT", 0, 1)
    cb.text, cb.Text = text, text
end
TEMPLATES.BackdropTemplate = function(f)
    f.SetBackdrop = function(self, bd)
        local s = st(self)
        if not bd then if s.backdrop then s.backdrop.bg:Hide() end; return end
        s.backdrop = s.backdrop or { bg = self:CreateTexture(nil, "BACKGROUND", nil, -8) }
        s.backdrop.bg:SetAllPoints(); s.backdrop.bg:SetColorTexture(0, 0, 0, 0.8); s.backdrop.bg:Show()
    end
    f.SetBackdropColor = function(self, r, g, b, a)
        local bd = st(self).backdrop
        if bd then bd.bg:SetColorTexture(r, g, b, a or 1) end
    end
    f.SetBackdropBorderColor = function() end
end

function W.CreateFrame(client, kind, name, parent, template)
    kind = kind or "Frame"
    local k = ({ Frame = "Frame", Button = "Button", CheckButton = "CheckButton", ScrollFrame = "ScrollFrame",
                 GameTooltip = "Frame", Slider = "Frame", EditBox = "Frame", StatusBar = "Frame",
                 Cooldown = "Frame", Model = "Frame", MessageFrame = "Frame" })[kind]
    if not k then error("CreateFrame: unknown frame type " .. tostring(kind), 3) end
    if parent == nil then parent = nil end
    local f = newObject(client, k, nil, true)
    local s = st(f)
    s.children, s.regions, s.scripts, s.hooks, s.events = {}, {}, {}, {}, {}
    if k == "Button" or k == "CheckButton" then
        s.mouse, s.enabled, s.clicks = true, true, { "LeftButtonUp" }
    end
    if parent then
        s.parent = parent
        local ps = st(parent)
        ps.children[#ps.children + 1] = f
    end
    client.frames[#client.frames + 1] = f
    if name then s.name = name; client.env[name] = f end
    for t in tostring(template or ""):gmatch("[^,%s]+") do
        if TEMPLATES[t] then TEMPLATES[t](f) end
    end
    bump()
    return f
end

---------------------------------------------------------------------------
-- Clients (one copy of the addon per fake player)
---------------------------------------------------------------------------

function W.NewRoot(client)
    local root = newObject(client, "Frame", nil, true)
    local s = st(root)
    s.children, s.regions, s.scripts, s.hooks, s.events = {}, {}, {}, {}, {}
    s.isRoot = true
    s.name = "UIParent"
    client.frames[#client.frames + 1] = root
    return root
end

function W.NewFontObject(client, name, font, size, flags, r, g, b, shadow)
    local fo = newObject(client, "FontObject", nil, false)
    local s = st(fo)
    s.name, s.font, s.fontSize, s.fontFlags = name, font, size, flags or ""
    s.color = { r or 1, g or 1, b or 1, 1 }
    if shadow then s.shadow = { 0, 0, 0, 1 }; s.shadowOffset = { 1, -1 } end
    if name then client.env[name] = fo end
    return fo
end

function W.FireEvent(client, event, ...)
    local list = {}
    for _, f in ipairs(client.frames) do
        local s = st(f)
        if s.events and (s.events[event] or s.allEvents) and s.scripts.OnEvent then list[#list + 1] = f end
    end
    for _, f in ipairs(list) do runScript(f, "OnEvent", event, ...) end
end

---------------------------------------------------------------------------
-- Ticking: OnUpdate, timers, OnSizeChanged
---------------------------------------------------------------------------

function W.TickClient(c, dt)
    -- timers
    if #c.timers > 0 then
        local due, keep = {}, {}
        for _, t in ipairs(c.timers) do
            if t.cancelled then -- drop
            elseif t.at <= W.now then due[#due + 1] = t
            else keep[#keep + 1] = t end
        end
        c.timers = keep
        table.sort(due, function(a, b) return a.at < b.at end)
        for _, t in ipairs(due) do
            safecall(t.fn, t.handle)
            if t.every and not t.cancelled then
                t.left = t.left and t.left - 1
                if not t.left or t.left > 0 then
                    t.at = W.now + t.every
                    c.timers[#c.timers + 1] = t
                end
            end
        end
    end
    -- OnUpdate for visible frames
    local list = {}
    for _, f in ipairs(c.frames) do
        local s = st(f)
        if (s.scripts.OnUpdate or s.hooks.OnUpdate) and isVisible(f) then list[#list + 1] = f end
    end
    for _, f in ipairs(list) do
        if isVisible(f) then runScript(f, "OnUpdate", dt) end
    end
    -- OnSizeChanged: a few passes so layouts that change other sizes can settle
    -- (only when something moved since the last check)
    for _ = 1, 4 do
        if c.sizeCheckedAt == W.layoutVersion then break end
        c.sizeCheckedAt = W.layoutVersion
        local changed = false
        for _, f in ipairs(c.frames) do
            local s = st(f)
            if (s.scripts.OnSizeChanged or s.hooks.OnSizeChanged) and isVisible(f) then
                local l, _, w, h = rect(f)
                if l then
                    local es = effScale(f)
                    w, h = floor(w / es * 100 + 0.5) / 100, floor(h / es * 100 + 0.5) / 100
                    if s.lastW ~= w or s.lastH ~= h then
                        s.lastW, s.lastH = w, h
                        runScript(f, "OnSizeChanged", w, h)
                        changed = true
                    end
                end
            end
        end
        if not changed then break end
    end
end

---------------------------------------------------------------------------
-- Mouse and keyboard (only for the client on screen)
---------------------------------------------------------------------------

local function clipOf(o)
    -- the clip rectangle (abs) that limits where this frame's contents show / get the mouse
    local s = st(o)
    if s.clV == W.layoutVersion then return s.cl[1], s.cl[2], s.cl[3], s.cl[4] end
    local p = s.parent
    local cl, cb, cr, ct = -1e9, -1e9, 1e9, 1e9
    while p do
        local ps = st(p)
        if ps.clips or ps.kind == "ScrollFrame" then
            local l, b, w, h = rect(p)
            if l then
                cl, cb, cr, ct = max(cl, l), max(cb, b), min(cr, l + w), min(ct, b + h)
            end
        end
        p = ps.parent
    end
    s.clV, s.cl = W.layoutVersion, { cl, cb, cr, ct }
    return cl, cb, cr, ct
end
W.ClipOf = clipOf

local function frameOrderKey(f)
    local s = st(f)
    if s.okV == W.layoutVersion then return s.ok end
    s.okV, s.ok = W.layoutVersion, STRATA[effStrata(f)] * 1e7 + effLevel(f) * 1e4
    return s.ok
end

local function frameUnder(c, x, y, want)
    local best, bestKey, bestId
    for _, f in ipairs(c.frames) do
        local s = st(f)
        if s[want] and not s.isRoot and isVisible(f) then
            local l, b, w, h = rect(f)
            if l then
                local ins = s.hitInsets
                if ins then
                    local es = effScale(f)
                    l, w = l + ins[1] * es, w - (ins[1] + ins[2]) * es
                    b, h = b + ins[4] * es, h - (ins[3] + ins[4]) * es
                end
                if x >= l and x <= l + w and y >= b and y <= b + h then
                    local cl, cb, cr, ct = clipOf(f)
                    if x >= cl and x <= cr and y >= cb and y <= ct then
                        local key = frameOrderKey(f)
                        if not best or key > bestKey or (key == bestKey and s.id > bestId) then
                            best, bestKey, bestId = f, key, s.id
                        end
                    end
                end
            end
        end
    end
    return best
end
W.FrameUnder = frameUnder

local function motionAllowed(f)
    local s = st(f)
    if s.enabled == false and not s.motionDisabled then return false end
    return true
end

local function clampToScreen(f)
    local s = st(f)
    if not s.clamped then return end
    local l, b, w, h = rect(f)
    if not l then return end
    local vw = W.VirtualWidth()
    local dx, dy = 0, 0
    if l < 0 then dx = -l elseif l + w > vw then dx = vw - (l + w) end
    if b < 0 then dy = -b elseif b + h > 768 then dy = 768 - (b + h) end
    if dx ~= 0 or dy ~= 0 then
        local es = effScale(f)
        local p = s.points[1]
        if p then p.x = p.x + dx / es; p.y = p.y + dy / es; bump() end
    end
end

-- Re-anchor a frame to the screen's bottom-left at its current spot (like WoW does when moved)
local function anchorAt(f, left, top)
    local s = st(f)
    local es = effScale(f)
    local root = s.client.ui
    s.points = { { point = "TOPLEFT", rel = root, relPoint = "BOTTOMLEFT",
                   x = left / es * (es / effScale(f)), y = top / es } }
    -- (offsets are in the frame's own units)
    s.points[1].x = left / es
    bump()
end

function W.MouseMove(c, x, y)
    local m = c.mouse
    m.x, m.y = x, y
    if c.moving then
        local f = c.moving.frame
        anchorAt(f, x - c.moving.dx, y - c.moving.dy)
        clampToScreen(f)
    elseif c.sizing then
        local z = c.sizing
        local f = z.frame
        local fs = st(f)
        local es = effScale(f)
        local bmin = fs.bounds or { 0, 0, 100000, 100000 }
        local dx, dy = x - z.mx, y - z.my
        local w, h = z.w, z.h
        local l, top = z.l, z.b + z.h
        if z.point:find("RIGHT") then w = z.w + dx elseif z.point:find("LEFT") then w = z.w - dx end
        if z.point:find("BOTTOM") then h = z.h - dy elseif z.point:find("TOP") then h = z.h + dy end
        w = max(bmin[1] * es, min(bmin[3] * es, w))
        h = max(bmin[2] * es, min(bmin[4] * es, h))
        if z.point:find("LEFT") then l = z.l + z.w - w end
        if z.point:find("TOP") then top = z.b + h end
        fs.w, fs.h = w / es, h / es
        anchorAt(f, l, top)
    end
    -- mouse focus (OnEnter / OnLeave)
    local focus = (not m.down) and frameUnder(c, x, y, "mouse") or m.focus
    if m.down and m.down.frame then
        -- while a button is held the focus stays, but leaving still fires OnLeave/OnEnter in WoW
        focus = frameUnder(c, x, y, "mouse")
    end
    if focus ~= m.focus then
        local old = m.focus
        m.focus = focus
        W.MarkDirty()
        if old and motionAllowed(old) then runScript(old, "OnLeave", false) end
        if focus and motionAllowed(focus) then runScript(focus, "OnEnter", false) end
    end
    -- dragging
    local d = m.down
    if d and not d.dragging and d.frame and st(d.frame).drag and #st(d.frame).drag > 0 then
        if abs(x - d.x) + abs(y - d.y) > 4 * (768 / W.screen.pxH) then
            d.dragging = true
            runScript(d.frame, "OnDragStart", d.button)
        end
    end
end

function W.MouseDown(c, x, y, button)
    W.MouseMove(c, x, y)
    local f = frameUnder(c, x, y, "mouse")
    c.mouse.down = { frame = f, x = x, y = y, button = button }
    W.MarkDirty()
    if f then
        local s = st(f)
        if s.enabled ~= false then
            s.pushed = true
            runScript(f, "OnMouseDown", button)
        end
        -- Toplevel frames come to the front when clicked
        local p = f
        while p and not st(p).isRoot do
            if st(p).toplevel then p:Raise() end
            p = st(p).parent
        end
    end
end

function W.MouseUp(c, x, y, button)
    local d = c.mouse.down
    c.mouse.down = nil
    W.MarkDirty()
    if not d or not d.frame then W.MouseMove(c, x, y); return end
    local f = d.frame
    local s = st(f)
    s.pushed = false
    if d.dragging then runScript(f, "OnDragStop") end
    if s.enabled ~= false then runScript(f, "OnMouseUp", button) end
    local over = frameUnder(c, x, y, "mouse")
    if over == f and s.enabled and (s.kind == "Button" or s.kind == "CheckButton") and not d.dragging then
        if s.kind == "CheckButton" then s.checked = not s.checked; W.MarkDirty() end
        runScript(f, "OnClick", button, false)
    end
    W.MouseMove(c, x, y)
end

function W.MouseWheel(c, x, y, delta)
    local f = frameUnder(c, x, y, "wheel")
    if f then runScript(f, "OnMouseWheel", delta) end
end

-- A key was pressed. Returns true if a frame used it.
function W.KeyDown(c, key)
    local list = {}
    for _, f in ipairs(c.frames) do
        local s = st(f)
        if s.keyboard and isVisible(f) then list[#list + 1] = f end
    end
    table.sort(list, function(a, b)
        local ka, kb = frameOrderKey(a), frameOrderKey(b)
        if ka ~= kb then return ka > kb end
        return st(a).id > st(b).id
    end)
    for _, f in ipairs(list) do
        runScript(f, "OnKeyDown", key)
        if not st(f).propagate then return true end
    end
    if key == "ESCAPE" then
        local closed = false
        for _, name in ipairs(c.env.UISpecialFrames) do
            local f = c.env[name]
            if f and f.IsShown and f:IsShown() then f:Hide(); closed = true end
        end
        return closed
    end
    return false
end

---------------------------------------------------------------------------
-- Drawing: build the list for the page
---------------------------------------------------------------------------

local function collectFrames(o, out)
    for _, f in ipairs(st(o).children) do
        if st(f).shown then
            out[#out + 1] = f
            collectFrames(f, out)
        end
    end
end

local function layerKey(r)
    local s = st(r)
    return LAYER[s.layer or "ARTWORK"] * 100 + (s.sublevel or 0)
end

function W.Draw(c)
    local h = W.host
    local k = W.PixelsPerUnit()
    local pxH = W.screen.pxH
    local frames = {}
    collectFrames(c.ui, frames)
    for i, f in ipairs(frames) do st(f).drawOrder = i end
    table.sort(frames, function(a, b)
        local ka, kb = frameOrderKey(a), frameOrderKey(b)
        if ka ~= kb then return ka < kb end
        return st(a).drawOrder < st(b).drawOrder
    end)
    local focus = c.mouse.focus
    local down = c.mouse.down
    h.beginFrame()
    for _, f in ipairs(frames) do
        local fs = st(f)
        local fl = rect(f)
        if fl then
            local alpha = effAlpha(f)
            if alpha > 0.003 then
                local cl, cb, cr, ct = clipOf(f)
                local clipped = cl > -1e8
                if clipped then
                    h.clip(floor(cl * k + 0.5), floor((768 - ct) * k + 0.5),
                           floor(cr * k + 0.5) - floor(cl * k + 0.5), floor((768 - cb) * k + 0.5) - floor((768 - ct) * k + 0.5))
                end
                local regions = fs.sortedRegions
                if not regions or fs.sortedN ~= #fs.regions then
                    regions = {}
                    for i, r in ipairs(fs.regions) do
                        st(r).drawOrder = i
                        regions[#regions + 1] = r
                    end
                    table.sort(regions, function(a, b)
                        local ka, kb = layerKey(a), layerKey(b)
                        if ka ~= kb then return ka < kb end
                        return st(a).drawOrder < st(b).drawOrder
                    end)
                    fs.sortedRegions, fs.sortedN = regions, #fs.regions
                end
                local hovered = (focus == f and motionAllowed(f) and fs.enabled ~= false) or fs.lockHL
                local pushed = down and down.frame == f and fs.pushed and focus == f
                for _, r in ipairs(regions) do
                    local rs = st(r)
                    if rs.shown and (rs.layer ~= "HIGHLIGHT" or hovered)
                        and (not rs.checkFor or st(rs.checkFor).checked) then
                        local l, b, w, hh = rect(r)
                        local a = alpha * rs.alpha
                        if rs.ignoreParentAlpha then a = rs.alpha end
                        if l and a > 0.003 then
                            -- snap the edges to whole screen pixels (like the game does)
                            local x1, x2 = floor(l * k + 0.5), floor((l + w) * k + 0.5)
                            local y1, y2 = floor((768 - b - hh) * k + 0.5), floor((768 - b) * k + 0.5)
                            if rs.kind == "Texture" then
                                if rs.color or rs.gradient or rs.file then
                                    if x2 > x1 and y2 > y1 or (rs.rot and rs.rot ~= 0) then
                                        local tc = rs.tc or { 0, 1, 0, 1 }
                                        local vc = rs.vc or { 1, 1, 1, 1 }
                                        if rs.gradient then
                                            local gr = rs.gradient
                                            h.gradient(x1, y1, x2 - x1, y2 - y1, gr.orient,
                                                gr.from[1], gr.from[2], gr.from[3], gr.from[4] * vc[4] * a,
                                                gr.to[1], gr.to[2], gr.to[3], gr.to[4] * vc[4] * a)
                                        elseif rs.color then
                                            local col = rs.color
                                            h.rect(x1, y1, x2 - x1, y2 - y1, col[1] * vc[1], col[2] * vc[2], col[3] * vc[3],
                                                col[4] * vc[4] * a, rs.blend or "BLEND", rs.rot or 0)
                                        else
                                            local es = effScale(r)
                                            h.texture(rs.file, l * k, (768 - b - hh) * k, w * k, hh * k,
                                                tc[1], tc[2], tc[3], tc[4], vc[1], vc[2], vc[3], vc[4] * a,
                                                rs.blend or "BLEND", rs.rot or 0, rs.desat or false,
                                                (rs.tileH or (rs.wrapH == "REPEAT" and rs.tileH ~= false)) and es * k or 0,
                                                (rs.tileV or (rs.wrapV == "REPEAT" and rs.tileV ~= false)) and es * k or 0,
                                                x1, y1, x2 - x1, y2 - y1)
                                        end
                                    end
                                end
                            elseif rs.text and rs.text ~= "" then
                                local es = effScale(r)
                                local col = rs.textColor or { 1, 1, 1, 1 }
                                local sc = rs.shadowColor or { 0, 0, 0, 0 }
                                local so = rs.shadowOffset or { 0, 0 }
                                local ox, oy = 0, 0
                                if pushed and fs.fontString == r and fs.pushedOffset then
                                    ox, oy = fs.pushedOffset[1] * es * k, -fs.pushedOffset[2] * es * k
                                end
                                local wrap = (rs.w or rs.twoX) and rs.wordWrap ~= false
                                h.text(rs.text, fontKey(rs.font), (rs.fontSize or 12) * es * k,
                                    l * k + ox, (768 - b - hh) * k + oy, w * k, hh * k,
                                    col[1], col[2], col[3], (col[4] or 1) * a,
                                    rs.justifyH or "CENTER", rs.justifyV or "MIDDLE", wrap and true or false,
                                    rs.fontFlags or "", sc[1], sc[2], sc[3], (sc[4] or 0) * a,
                                    so[1] * es * k, -so[2] * es * k, lineHeight(rs) * es * k,
                                    rs.maxLines or 0)
                            end
                        end
                    end
                end
                if clipped then h.unclip() end
            end
        end
    end
    h.endFrame()
end

---------------------------------------------------------------------------
-- Saved variables (kept in the browser between visits)
---------------------------------------------------------------------------

local function serialize(v, indent, seen)
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "0" end
        if v == floor(v) and abs(v) < 2^53 then return string.format("%d", v) end
        return string.format("%.17g", v)
    end
    if t == "boolean" then return tostring(v) end
    if t ~= "table" then return "nil" end
    seen = seen or {}
    if seen[v] then return "nil" end
    seen[v] = true
    local parts = {}
    local n = #v
    for i = 1, n do parts[#parts + 1] = serialize(v[i], indent, seen) end
    for key, val in pairs(v) do
        if not (type(key) == "number" and key >= 1 and key <= n and key == floor(key)) then
            local ks
            if type(key) == "string" and key:match("^[%a_][%w_]*$") then ks = key
            else ks = "[" .. serialize(key, indent, seen) .. "]" end
            if type(val) ~= "function" and type(val) ~= "userdata" then
                parts[#parts + 1] = ks .. "=" .. serialize(val, indent, seen)
            end
        end
    end
    seen[v] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end
W.Serialize = serialize

W.Classes = { Region = Region, Frame = Frame, Button = Button, CheckButton = CheckButton,
              ScrollFrame = ScrollFrame, Texture = Texture, FontString = FontString }

-- Anything that can change the picture marks it as "needs drawing" (the page then redraws;
-- when nothing changed, drawing is skipped, which keeps the preview fast).
W.visualVersion = 0
do
    local function wrap(fn)
        return function(...)
            W.visualVersion = W.visualVersion + 1
            return fn(...)
        end
    end
    local VISUAL = { "^Set", "^Show", "^Hide", "^Enable", "^Disable", "^Lock", "^Unlock", "^Click", "^Clear", "^Raise", "^Lower", "^Start" }
    for _, cls in pairs(W.Classes) do
        for name, fn in pairs(cls) do
            local selfTracked = { SetAlpha = true, SetPoint = true, SetSize = true, SetWidth = true, SetHeight = true,
                                  SetText = true, SetAllPoints = true, SetScript = true, SetFrameLevel = true }
            if type(fn) == "function" and rawget(cls, name) == fn and not selfTracked[name] then
                for _, pat in ipairs(VISUAL) do
                    if name:find(pat) then cls[name] = wrap(fn); break end
                end
            end
        end
    end
end
function W.MarkDirty() W.visualVersion = W.visualVersion + 1 end
W.IsVisible = isVisible
W.EffScale = effScale

return W
