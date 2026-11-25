-- preview/main.lua
-- Starts the browser preview: loads the addon into several fake players ("clients"),
-- connects them with a fake guild (roster, addon messages, guild chat), lets the
-- other players play by themselves (bots), and passes mouse/keyboard from the page.

local js = require "js"
local jsHost = js.global.host

---------------------------------------------------------------------------
-- Lua 5.1 compatibility (WoW runs Lua 5.1; the browser runs 5.3)
---------------------------------------------------------------------------

unpack = unpack or table.unpack
table.getn = table.getn or function(t) return #t end
math.mod = math.mod or math.fmod
math.pow = math.pow or function(a, b) return a ^ b end
string.gfind = string.gfind or string.gmatch
loadstring = loadstring or load
do
    -- %d with a non-whole number works in 5.1 (it cuts off the decimals) but errors in 5.3
    local format = string.format
    string.format = function(fmt, ...)
        local args = { ... }
        local n = select("#", ...)
        local i = 0
        for spec in tostring(fmt):gmatch("%%[-+ #0]*%d*%.?%d*([%a%%])") do
            if spec ~= "%" then
                i = i + 1
                local v = args[i]
                if (spec == "d" or spec == "i" or spec == "x" or spec == "X" or spec == "c" or spec == "o")
                    and type(v) == "number" and math.type(v) == "float" then
                    args[i] = v >= 0 and math.floor(v) or math.ceil(v)
                end
            end
        end
        return format(fmt, table.unpack(args, 1, n))
    end
end

---------------------------------------------------------------------------
-- The page's functions
---------------------------------------------------------------------------

local host = {}
for _, name in ipairs({ "textWidth", "wrapLines", "beginFrame", "endFrame", "clip", "unclip", "rect", "gradient",
                        "texture", "text", "error", "playSound", "chat", "chatReset", "notice", "store", "load",
                        "panel", "fileExists", "fetchText", "log", "consumeRedraw" }) do
    local f = jsHost[name]
    host[name] = function(...) return f(jsHost, ...) end
end

local W = assert(load(host.fetchText("wow.lua"), "@preview/wow.lua"))()
W.host = host
local S = W.S
PreviewW = W          -- reachable from the "eval" test command

---------------------------------------------------------------------------
-- The fake guild
---------------------------------------------------------------------------

-- `me` is the player you play as. The others are bots you can also switch to.
W.members = {
    { short = "Herm", surname = "Berm", class = "Mage", level = 60, online = true, addon = true, me = true },
    { short = "Gulki", surname = "Warr", class = "Warrior", level = 60, online = true, addon = true },
    { short = "Father", surname = "Ghouliath", class = "Priest", level = 58, online = true, addon = true },
    { short = "Biggie", surname = "Icade", class = "Rogue", level = 60, online = false, addon = true },
    { short = "Tankie", class = "Paladin", level = 42, online = true, addon = false },
}
for i, m in ipairs(W.members) do
    m.realm = "CAMWOWEU" .. (3 + i) .. "Realm6PvP"      -- each client writes realms its own way (like WoW: Forever)
    m.bot = { auto = not m.me, answer = "accept", seen = {}, next = 0 }
end
local function member(short)
    for _, m in ipairs(W.members) do if m.short == short then return m end end
end

local bus = { queue = {} }
W.chatLog = {}

---------------------------------------------------------------------------
-- Loading the addon files (fetched once, run once per client)
---------------------------------------------------------------------------

local sources
local function addonFiles()
    if sources then return sources end
    sources = {}
    local toc = host.fetchText("../Yatzy/Yatzy.toc") or ""
    for line in toc:gmatch("[^\r\n]+") do
        local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
        if file then
            sources[#sources + 1] = { file = file, src = host.fetchText("../Yatzy/" .. file:gsub("\\", "/")) or "" }
        end
    end
    return sources
end

local function chatLine(c, text, r, g, b)
    c.chat[#c.chat + 1] = { text = text, r = r or 1, g = g or 1, b = b or 1 }
    if #c.chat > 300 then table.remove(c.chat, 1) end
    if W.view == c then host.chat(text, r or 1, g or 1, b or 1) end
end

local function saveClient(c)
    local data = "return { db = " .. W.Serialize(c.env.YatzyDB) .. ", char = " .. W.Serialize(c.env.YatzyCharDB) .. " }"
    host.store("yatzy-preview/" .. c.short, data)
end

local function loadSaved(short)
    local text = host.load("yatzy-preview/" .. short)
    if not text then return nil end
    local fn = load(text, "=saved", "t", {})
    if not fn then return nil end
    local ok, data = pcall(fn)
    if ok and type(data) == "table" then return data end
end

---------------------------------------------------------------------------
-- The WoW API each client sees
---------------------------------------------------------------------------

local SOUNDKIT_IDS = setmetatable({}, { __index = function(t, k) return 800 end })

local function makeEnv(c)
    local env = setmetatable({}, { __index = _G })
    env._G = env
    c.env = env

    -- strings & tables, the way WoW names them
    env.tinsert, env.tremove, env.tconcat, env.sort = table.insert, table.remove, table.concat, table.sort
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.strlower, env.strupper, env.strsub, env.strfind, env.strlen, env.strrep =
        string.lower, string.upper, string.sub, string.find, string.len, string.rep
    env.strmatch, env.gsub, env.format, env.strbyte, env.strchar = string.match, string.gsub, string.format, string.byte, string.char
    env.strtrim = function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
    env.strsplit = function(sep, s, limit)
        local out, pos = {}, 1
        while true do
            if limit and #out == limit - 1 then out[#out + 1] = s:sub(pos); break end
            local a, b = s:find(sep, pos, true)
            if not a then out[#out + 1] = s:sub(pos); break end
            out[#out + 1] = s:sub(pos, a - 1)
            pos = b + 1
        end
        return table.unpack(out)
    end
    env.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
    env.floor, env.ceil, env.abs, env.min, env.max, env.sqrt = math.floor, math.ceil, math.abs, math.min, math.max, math.sqrt
    env.sin = function(d) return math.sin(math.rad(d)) end
    env.cos = function(d) return math.cos(math.rad(d)) end
    env.random = math.random
    env.date = os.date
    env.time = function() return os.time() end
    env.GetTime = function() return W.now end
    env.GetServerTime = function() return os.time() end
    env.debugprofilestop = function() return W.now * 1000 end
    env.hooksecurefunc = function(a, b, cfn)
        local tbl, name, fn = env, a, b
        if type(a) == "table" then tbl, name, fn = a, b, cfn end
        local orig = tbl[name]
        tbl[name] = function(...) local r = { orig(...) }; fn(...); return table.unpack(r) end
    end
    env.geterrorhandler = function() return W.ReportError end
    env.seterrorhandler = function() end
    env.debugstack = function() return debug.traceback() end
    env.GetBuildInfo = function() return "1.16.0", "60000", "Nov 1 2026", 11600 end
    env.GetLocale = function() return "enUS" end
    env.GetCVar = function(name) if name == "Sound_SFXVolume" or name == "Sound_MasterVolume" then return "1.0" end return "1" end
    env.GetCVarBool = function() return true end

    -- frames
    c.frames, c.timers = {}, {}
    c.mouse = { x = 0, y = 0 }
    env.CreateFrame = function(kind, name, parent, template)
        if type(parent) == "string" then parent = env[parent] end
        return W.CreateFrame(c, kind, name, parent, template)
    end
    local root = W.NewRoot(c)
    c.ui = root
    env.UIParent = root
    env.WorldFrame = root
    env.GetScreenWidth = function() return W.VirtualWidth() / W.screen.uiScale end
    env.GetScreenHeight = function() return 768 / W.screen.uiScale end
    env.GetCursorPosition = function() return c.mouse.x, c.mouse.y end
    env.GetPhysicalScreenSize = function() return W.screen.pxW, W.screen.pxH end
    env.MouseIsOver = function(f, ...) return f:IsMouseOver(...) end
    env.GetMouseFocus = function() return c.mouse.focus end
    env.GetMouseFoci = function() return { c.mouse.focus } end
    env.IsControlKeyDown = function() return W.keys.ctrl end
    env.IsShiftKeyDown = function() return W.keys.shift end
    env.IsAltKeyDown = function() return W.keys.alt end
    env.IsModifierKeyDown = function() return W.keys.ctrl or W.keys.shift or W.keys.alt end
    env.UISpecialFrames = {}
    env.CreateColor = function(r, g, b, a)
        local col = { r = r, g = g, b = b, a = a or 1 }
        function col:GetRGBA() return self.r, self.g, self.b, self.a end
        function col:GetRGB() return self.r, self.g, self.b end
        function col:GenerateHexColor() return ("ff%02x%02x%02x"):format(self.r * 255, self.g * 255, self.b * 255) end
        function col:WrapTextInColorCode(t) return "|c" .. self:GenerateHexColor() .. t .. "|r" end
        return col
    end

    -- fonts
    local FRIZ = "Fonts\\FRIZQT__.TTF"
    env.STANDARD_TEXT_FONT = FRIZ
    env.UNIT_NAME_FONT = FRIZ
    env.DAMAGE_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    local fonts = {
        GameFontNormal = { 12, 1, 0.82, 0 }, GameFontNormalSmall = { 10, 1, 0.82, 0 }, GameFontNormalLarge = { 16, 1, 0.82, 0 },
        GameFontNormalHuge = { 20, 1, 0.82, 0 },
        GameFontHighlight = { 12, 1, 1, 1 }, GameFontHighlightSmall = { 10, 1, 1, 1 }, GameFontHighlightLarge = { 16, 1, 1, 1 },
        GameFontDisable = { 12, 0.5, 0.5, 0.5 }, GameFontDisableSmall = { 10, 0.5, 0.5, 0.5 }, GameFontDisableLarge = { 16, 0.5, 0.5, 0.5 },
        GameFontWhite = { 12, 1, 1, 1 }, GameFontRed = { 12, 1, 0.1, 0.1 }, GameFontGreen = { 12, 0.1, 1, 0.1 },
        GameFontBlack = { 12, 0, 0, 0 }, GameFontWhiteSmall = { 10, 1, 1, 1 }, NumberFontNormal = { 12, 1, 1, 1 },
        ChatFontNormal = { 14, 1, 1, 1 }, GameTooltipText = { 12, 1, 1, 1 }, GameTooltipHeaderText = { 14, 1, 1, 1 },
        SystemFont_Small = { 10, 1, 1, 1 }, SystemFont_Med1 = { 12, 1, 1, 1 }, SystemFont_Large = { 16, 1, 1, 1 },
    }
    for name, f in pairs(fonts) do W.NewFontObject(c, name, FRIZ, f[1], "", f[2], f[3], f[4], true) end
    env.CreateFont = function(name)
        local fo = W.NewFontObject(c, name, FRIZ, 12, "", 1, 1, 1, false)
        return fo
    end

    -- sound
    env.SOUNDKIT = SOUNDKIT_IDS
    env.PlaySound = function() return true end
    env.StopSound = function() end
    env.PlaySoundFile = function(path, channel)
        local url = tostring(path):gsub("\\", "/")
        local lower = url:lower()
        if lower:find("^interface/addons/yatzy/") then
            url = "../Yatzy/" .. url:sub(#"interface/addons/yatzy/" + 1)
        else
            return false
        end
        if not host.fileExists(url) then return false end
        if W.view == c then host.playSound(url) end
        return true, 1
    end

    -- chat
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg, r, g, b) chatLine(c, tostring(msg), r, g, b) end }
    env.ChatFrame1 = env.DEFAULT_CHAT_FRAME
    env.print = function(...)
        local t = {}
        for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
        chatLine(c, table.concat(t, " "))
    end
    env.ChatTypeInfo = setmetatable({ RAID_WARNING = { r = 1, g = 0.28, b = 0 } },
        { __index = function() return { r = 1, g = 1, b = 1 } end })
    env.RaidWarningFrame = W.CreateFrame(c, "Frame", "RaidWarningFrame", root)
    env.RaidNotice_AddMessage = function(_, text, info)
        if W.view == c then host.notice(tostring(text), info and info.r or 1, info and info.g or 0.82, info and info.b or 0) end
    end
    env.UIErrorsFrame = { AddMessage = function(_, msg) if W.view == c then host.notice(tostring(msg), 1, 0.1, 0.1) end end }
    env.SendChatMessage = function(msg, kind, _, target)
        kind = (kind or "SAY"):upper()
        local me = member(c.short)
        if kind == "GUILD" then
            for _, other in pairs(W.clients) do
                chatLine(other, "[Guild] [" .. c.short .. "]: " .. tostring(msg), 0.25, 1, 0.25)
            end
        else
            chatLine(c, "[" .. c.short .. "] says: " .. tostring(msg), 1, 1, 1)
        end
    end

    -- the player
    env.UnitName = function(unit) if unit == "player" then return c.short end return nil end
    env.UnitFullName = function(unit) if unit == "player" then return c.short, "ForeverRealm" end end
    env.UnitGUID = function(unit) if unit == "player" then return "Player-1-" .. c.short end end
    env.UnitClass = function() local m = member(c.short); return m.class, m.class:upper(), 1 end
    env.UnitLevel = function() return member(c.short).level end
    env.UnitExists = function(unit) return unit == "player" end
    env.UnitIsUnit = function(a, b) return a == b end
    env.GetRealmName = function() return "Forever Realm" end
    env.GetNormalizedRealmName = function() return "ForeverRealm" end
    env.InCombatLockdown = function() return W.view == c and W.player.combat end
    env.UnitAffectingCombat = function() return W.view == c and W.player.combat end
    local SECRET = setmetatable({ secret = true }, { __tostring = function() return "<secret>" end })
    env.issecretvalue = function(v) return v == SECRET end
    env.GetUnitSpeed = function()
        if W.view ~= c then return 0, 7, 7, 4.7 end
        if W.player.combat and W.player.secrets then return SECRET, SECRET, SECRET, SECRET end
        return (W.player.moving or W.player.taxi) and 7 or 0, 7, 7, 4.7
    end
    env.IsPlayerMoving = function() return W.view == c and (W.player.moving or W.player.taxi) end
    env.IsFalling = function() return false end
    env.UnitOnTaxi = function() return W.view == c and W.player.taxi end
    env.IsMounted = function() return false end
    env.SetPortraitTexture = function(tex, unit) if unit == "player" then tex:SetTexture("special:portrait:" .. c.short) end end

    -- guild
    env.IsInGuild = function() return true end
    env.GetGuildInfo = function() return "Lucker Club", "Member", 1 end
    env.GetNumGuildMembers = function() return #W.members, #W.members end
    env.GetGuildRosterInfo = function(i)
        local m = W.members[i]
        if not m then return nil end
        local name = m.short .. (m.surname and (" " .. m.surname) or "") .. "-" .. c.realm
        return name, "Member", 1, m.level, m.class, "Orgrimmar", "", "", m.online, 0, m.class:upper()
    end
    local function requestRoster() c.rosterAt = c.rosterAt or (W.now + 0.3) end
    env.C_GuildInfo = { GuildRoster = requestRoster }
    env.GuildRoster = requestRoster

    -- addon messages
    local prefixes = {}
    local function send(prefix, text, channel, target)
        text = tostring(text)
        if #text > 255 then
            W.ReportError(("%s sent an addon message longer than 255 characters (%d); WoW drops it.\n%s")
                :format(c.short, #text, text:sub(1, 120)))
            return false
        end
        channel = (channel or ""):upper()
        bus.sent = (bus.sent or 0) + 1
        if channel == "GUILD" then
            for name, other in pairs(W.clients) do
                bus.queue[#bus.queue + 1] = { at = W.now + 0.15, from = c.short, to = name, prefix = prefix, text = text, channel = "GUILD" }
            end
            return true
        elseif channel == "WHISPER" then
            local to = W.clients[tostring(target)]
            if not to then
                chatLine(c, ("No player named '%s' is currently playing."):format(tostring(target)), 1, 1, 0)
                return false
            end
            bus.queue[#bus.queue + 1] = { at = W.now + 0.15, from = c.short, to = target, prefix = prefix, text = text, channel = "WHISPER" }
            return true
        end
        return false
    end
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function(p) prefixes[p] = true; return true end,
        IsAddonMessagePrefixRegistered = function(p) return prefixes[p] or false end,
        SendAddonMessage = send,
    }
    env.SendAddonMessage = send
    env.RegisterAddonMessagePrefix = env.C_ChatInfo.RegisterAddonMessagePrefix

    -- timers
    env.C_Timer = {}
    local function newTimer(sec, fn, times)
        local t = { at = W.now + (sec or 0), fn = fn, every = times ~= 1 and sec or nil, left = times }
        t.handle = { Cancel = function() t.cancelled = true end, IsCancelled = function() return t.cancelled or false end }
        if times == 1 then t.every = nil end
        c.timers[#c.timers + 1] = t
        return t.handle
    end
    env.C_Timer.After = function(sec, fn) newTimer(sec, fn, 1) end
    env.C_Timer.NewTimer = function(sec, fn) return newTimer(sec, fn, 1) end
    env.C_Timer.NewTicker = function(sec, fn, iterations) return newTimer(sec, fn, iterations or false) end

    -- slash commands, popups, tooltip, minimap
    env.SlashCmdList = {}
    env.StaticPopupDialogs = {}
    env.StaticPopup_Show = function(which, a1, a2, data) return W.ShowPopup(c, which, a1, a2, data) end
    env.StaticPopup_Hide = function(which) if c.popup and c.popup.which == which then c.popup:Hide() end end
    env.CloseDropDownMenus = function() end
    env.GameTooltip = W.MakeTooltip(c)
    env.Minimap = W.MakeMinimap(c)
    env.MinimapCluster = env.Minimap
    env.ReloadUI = function() W.pendingReload = c.short end
    return env
end

---------------------------------------------------------------------------
-- Tooltip, popup dialog and minimap (drawn by us, plain look)
---------------------------------------------------------------------------

local Frame = W.Classes.Frame

function W.MakeTooltip(c)
    local tip = W.CreateFrame(c, "Frame", "GameTooltip", c.ui)
    tip:SetFrameStrata("TOOLTIP")
    tip:Hide()
    local bg = tip:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.03, 0.03, 0.06, 0.92)
    local function edge(p1, p2, horizontal)
        local t = tip:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.55, 0.55, 0.6, 1)
        t:SetPoint(p1); t:SetPoint(p2)
        if horizontal then t:SetHeight(1) else t:SetWidth(1) end
    end
    edge("TOPLEFT", "TOPRIGHT", true); edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    edge("TOPLEFT", "BOTTOMLEFT", false); edge("TOPRIGHT", "BOTTOMRIGHT", false)
    local lines = {}
    local function line(i)
        if not lines[i] then
            local l = tip:CreateFontString(nil, "OVERLAY")
            l:SetFont("Fonts\\FRIZQT__.TTF", i == 1 and 14 or 12, "")
            l:SetJustifyH("LEFT")
            local r = tip:CreateFontString(nil, "OVERLAY")
            r:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
            r:SetJustifyH("RIGHT")
            lines[i] = { l = l, r = r }
        end
        return lines[i]
    end
    local count = 0
    local owner, anchor
    function tip:SetOwner(o, a, x, y) owner, anchor = o, a or "ANCHOR_NONE"; self.ox, self.oy = x or 0, y or 0; self:ClearLines() end
    function tip:GetOwner() return owner end
    function tip:IsOwned(o) return owner == o end
    function tip:ClearLines()
        count = 0
        for _, l in ipairs(lines) do l.l:Hide(); l.r:Hide(); l.wrap = nil end
    end
    function tip:AddLine(text, r, g, b, wrap)
        count = count + 1
        local l = line(count)
        l.l:SetText(text); l.l:SetTextColor(r or (count == 1 and 1 or 1), g or (count == 1 and 1 or 0.82), b or (count == 1 and 1 or 0)); l.l:Show()
        if count == 1 and not r then l.l:SetTextColor(1, 1, 1) end
        l.r:Hide(); l.wrap = wrap
    end
    function tip:AddDoubleLine(a, b, lr, lg, lb, rr, rg, rbb)
        self:AddLine(a, lr, lg, lb)
        local l = lines[count]
        l.r:SetText(b); l.r:SetTextColor(rr or 1, rg or 1, rbb or 1); l.r:Show()
    end
    function tip:SetText(text, r, g, b) self:ClearLines(); self:AddLine(text, r or 1, g or 1, b or 1) end
    function tip:NumLines() return count end
    function tip:SetMinimumWidth() end
    function tip:SetPadding() end
    function tip:FadeOut() self:Hide() end
    function tip:Show()
        local width = 40
        for i = 1, count do
            local l = lines[i]
            local w = l.l:GetStringWidth() + (l.r:IsShown() and (l.r:GetStringWidth() + 20) or 0)
            if l.wrap then w = math.min(w, 260) end
            width = math.max(width, w)
        end
        width = width + 20
        local y = -10
        for i = 1, count do
            local l = lines[i]
            l.l:ClearAllPoints(); l.l:SetPoint("TOPLEFT", 10, y)
            if l.wrap then l.l:SetWidth(width - 20) else l.l[S].w = nil; W.bump() end
            l.r:ClearAllPoints(); l.r:SetPoint("TOPRIGHT", -10, y)
            y = y - l.l:GetStringHeight() - 2
        end
        self:SetSize(width, -y + 8)
        self:ClearAllPoints()
        if owner then
            if anchor == "ANCHOR_RIGHT" then self:SetPoint("BOTTOMLEFT", owner, "TOPRIGHT", self.ox, self.oy)
            elseif anchor == "ANCHOR_LEFT" then self:SetPoint("BOTTOMRIGHT", owner, "TOPLEFT", self.ox, self.oy)
            elseif anchor == "ANCHOR_TOP" then self:SetPoint("BOTTOM", owner, "TOP", self.ox, self.oy)
            elseif anchor == "ANCHOR_BOTTOM" then self:SetPoint("TOP", owner, "BOTTOM", self.ox, self.oy)
            elseif anchor == "ANCHOR_TOPLEFT" then self:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", self.ox, self.oy)
            elseif anchor == "ANCHOR_TOPRIGHT" then self:SetPoint("BOTTOMRIGHT", owner, "TOPRIGHT", self.ox, self.oy)
            elseif anchor == "ANCHOR_CURSOR" then
                local es = self:GetEffectiveScale()
                self:SetPoint("BOTTOMLEFT", c.ui, "BOTTOMLEFT", c.mouse.x / es + 12, c.mouse.y / es + 12)
            else self:SetPoint("BOTTOMRIGHT", c.ui, "BOTTOMRIGHT", -100, 120) end
        else
            self:SetPoint("BOTTOMRIGHT", c.ui, "BOTTOMRIGHT", -100, 120)
        end
        self:SetClampedToScreen(true)
        Frame.Show(self)
    end
    tip:HookScript("OnHide", function() owner = nil end)
    return tip
end

function W.ShowPopup(c, which, a1, a2, data)
    local d = c.env.StaticPopupDialogs[which]
    if not d then return nil end
    local p = c.popup
    if not p then
        p = W.CreateFrame(c, "Frame", "StaticPopup1", c.ui)
        p:SetFrameStrata("DIALOG")
        p:SetSize(320, 100)
        p:SetPoint("TOP", 0, -135)
        p:EnableMouse(true)
        local bg = p:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.04, 0.04, 0.07, 0.95)
        local br = p:CreateTexture(nil, "BORDER"); br:SetPoint("TOPLEFT", -2, 2); br:SetPoint("BOTTOMRIGHT", 2, -2)
        br:SetColorTexture(0.6, 0.6, 0.65, 1); br:SetDrawLayer("BACKGROUND", -1)
        p.text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        p.text:SetPoint("TOP", 0, -16); p.text:SetWidth(290)
        local function button(label, x)
            local b = W.CreateFrame(c, "Button", nil, p)
            b:SetSize(120, 22)
            b:SetPoint("BOTTOM", x, 14)
            local t = b:CreateTexture(nil, "BACKGROUND"); t:SetAllPoints(); t:SetColorTexture(0.45, 0.08, 0.05, 1)
            local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.15)
            b:SetText(label)
            return b
        end
        p.b1 = button("Okay", -66)
        p.b2 = button("Cancel", 66)
        p:EnableKeyboard(true)
        p:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:Hide()
                if self.dialog and self.dialog.OnCancel then W.safecall(self.dialog.OnCancel, self, self.data, "clicked") end
            end
        end)
        c.popup = p
    end
    p.which, p.dialog, p.data = which, d, data
    p.text:SetText((d.text or ""):format(a1 or "", a2 or ""))
    p.b1:SetText(d.button1 or "Okay")
    p.b2:SetText(d.button2 or "Cancel")
    p.b2:SetShown(d.button2 ~= nil)
    p.b1:SetScript("OnClick", function()
        p:Hide()
        if d.OnAccept then W.safecall(d.OnAccept, p, data) end
    end)
    p.b2:SetScript("OnClick", function()
        p:Hide()
        if d.OnCancel then W.safecall(d.OnCancel, p, data, "clicked") end
    end)
    p:SetHeight(64 + p.text:GetStringHeight())
    p:Show()
    return p
end

function W.MakeMinimap(c)
    local m = W.CreateFrame(c, "Frame", "Minimap", c.ui)
    m:SetSize(140, 140)
    m:SetPoint("TOPRIGHT", -24, -24)
    m:SetFrameStrata("LOW")
    local map = m:CreateTexture(nil, "BACKGROUND")
    map:SetAllPoints(); map:SetTexture("special:minimap")
    return m
end

---------------------------------------------------------------------------
-- Clients: log in, reload, log out
---------------------------------------------------------------------------

function W.Login(short)
    local m = member(short)
    if not m or not m.addon or W.clients[short] then return end
    local c = { short = short, realm = m.realm, chat = {}, member = m }
    W.clients[short] = c
    m.online = true
    makeEnv(c)
    local env = c.env
    c.ns = {}
    for _, f in ipairs(addonFiles()) do
        local chunk, err = load(f.src, "@Yatzy/" .. f.file, "t", env)
        if not chunk then W.ReportError(err)
        else W.safecall(chunk, "Yatzy", c.ns) end
    end
    local saved = loadSaved(short)
    if saved then env.YatzyDB, env.YatzyCharDB = saved.db, saved.char end
    W.FireEvent(c, "ADDON_LOADED", "Yatzy")
    W.FireEvent(c, "PLAYER_LOGIN")
    W.FireEvent(c, "PLAYER_ENTERING_WORLD", true, false)
    for _, other in pairs(W.clients) do other.rosterAt = W.now + 0.3 end
    if m.me and not W.view then W.view = c end
    W.SendPanel()
    return c
end

function W.Logout(short, keepOffline)
    local c = W.clients[short]
    if not c then return end
    saveClient(c)
    W.clients[short] = nil
    c.member.online = keepOffline and false or c.member.online
    if not keepOffline then c.member.online = false end
    for _, other in pairs(W.clients) do other.rosterAt = W.now + 0.3 end
    if W.view == c then W.SetView("Herm") end
    W.SendPanel()
end

function W.Reload(short)
    local c = W.clients[short]
    if not c then return end
    local wasView = W.view == c
    saveClient(c)
    W.clients[short] = nil
    local n = W.Login(short)
    if wasView and n then W.SetView(short) end
end

function W.SetView(short)
    local c = W.clients[short]
    if not c then return end
    W.view = c
    c.mouse.focus = nil
    host.chatReset()
    for _, l in ipairs(c.chat) do host.chat(l.text, l.r, l.g, l.b) end
    W.SendPanel()
end

function W.SaveAll()
    for _, c in pairs(W.clients) do saveClient(c) end
end

---------------------------------------------------------------------------
-- Bots: the other players accept invites and play their turns by themselves
---------------------------------------------------------------------------

local function botStep(c)
    local m = c.member
    local bot = m.bot
    if W.now < bot.next then return end
    bot.next = W.now + 0.9
    local ns = c.ns
    if not ns.Games or not ns.Guild then return end
    for _, g in ipairs(ns.Games:All()) do
        if ns.Games:IsInvite(g) and bot.answer ~= "wait" then
            bot.seen[g.id] = bot.seen[g.id] or W.now
            if W.now - bot.seen[g.id] > 2.5 then
                ns.Guild:Answer(g, bot.answer == "accept")
                if bot.answer == "accept" and ns.UI and ns.UI.start and ns.UI.start:IsShown() then ns.UI:RefreshStart() end
            end
        end
    end
    if not bot.auto or W.view == c then return end
    for _, g in ipairs(ns.Games:All()) do
        if g.kind == "guild" and g.game == "backgammon" and ns.Games:IsMyTurn(g) then
            -- backgammon: open the game, roll, play the computer's choice one checker at a time, Done
            local BG, BGPlay, Board = ns.BG, ns.BGPlay, ns.BGBoard
            if BGPlay.game ~= g or not Board:IsShown() then ns.UI:ShowGame(g.id); return end
            if Board:Busy() then return end
            if not g.dice then
                BGPlay:Roll()
            elseif #BG.Legal(g) > 0 then
                local key = g.id .. ":" .. g.turn
                if bot.planKey ~= key or #g.moves == 0 then
                    bot.planKey = key
                    bot.plan = ns.BGAI.ChooseMoves(g.board, BG.CurrentPlayer(g), g.dice)
                    bot.step = 0
                end
                bot.step = bot.step + 1
                local m = bot.plan[bot.step]
                if m and BG.FindMove(g, m.from, m.to) then
                    BGPlay:Move({ { from = m.from, to = m.to } })
                else
                    local any = BG.Legal(g)[1]                 -- (plan out of step: any legal move)
                    BGPlay:Move({ { from = any.from, to = any.to } })
                end
            else
                BGPlay:Done()
            end
            bot.next = W.now + 1.1
            return
        end
        if g.kind == "guild" and g.game ~= "backgammon" and ns.Games:IsMyTurn(g) then
            if not ns.mainWindow:IsShown() then ns:ToggleMainWindow() end
            if ns.Play.game ~= g then ns.UI:ShowGame(g.id); return end
            if ns.Board.animating or ns.Play.committing then return end
            local action, arg = ns.AI.NextAction(g)
            if action == "roll" then
                if arg and g.rollsUsed > 0 then
                    for i = 1, 5 do
                        if (g.held[i] and true or false) ~= (arg[i] and true or false) then ns.Play:ToggleHold(i) end
                    end
                end
                ns.Play:Roll()
            elseif arg then
                ns.Play:Score(arg)
            end
            bot.next = W.now + 1.3
            return
        end
    end
end

---------------------------------------------------------------------------
-- The page's side panel
---------------------------------------------------------------------------

local function jsonString(s)
    return '"' .. tostring(s):gsub('[%c"\\]', function(ch)
        if ch == '"' then return '\\"' elseif ch == "\\" then return "\\\\" elseif ch == "\n" then return "\\n" end
        return string.format("\\u%04x", ch:byte())
    end) .. '"'
end

function W.SendPanel()
    local parts = {}
    for _, m in ipairs(W.members) do
        local c = W.clients[m.short]
        local games = 0
        if c and c.ns.Games then
            for _, g in ipairs(c.ns.Games:All()) do if g.status ~= "over" and g.status ~= "cancelled" and not g.hidden then games = games + 1 end end
        end
        parts[#parts + 1] = ("{%s}"):format(table.concat({
            '"short":' .. jsonString(m.short),
            '"full":' .. jsonString(m.short .. (m.surname and (" " .. m.surname) or "")),
            '"class":' .. jsonString(m.class), '"level":' .. m.level,
            '"online":' .. tostring(m.online), '"addon":' .. tostring(m.addon), '"me":' .. tostring(m.me or false),
            '"viewing":' .. tostring(W.view ~= nil and W.view.short == m.short),
            '"auto":' .. tostring(m.bot.auto), '"answer":' .. jsonString(m.bot.answer), '"games":' .. games,
        }, ","))
    end
    host.panel("[" .. table.concat(parts, ",") .. "]")
end

---------------------------------------------------------------------------
-- Main loop and input from the page
---------------------------------------------------------------------------

W.keys = { ctrl = false, shift = false, alt = false }
local saveTimer = 0
local panelTimer = 0

local function deliver()
    if #bus.queue == 0 then return end
    local due, keep = {}, {}
    for _, msg in ipairs(bus.queue) do
        if msg.at <= W.now then due[#due + 1] = msg else keep[#keep + 1] = msg end
    end
    bus.queue = keep
    for _, msg in ipairs(due) do
        local to = W.clients[msg.to]
        if to then
            -- the receiver sees the sender's plain name with ITS OWN realm string (like WoW: Forever)
            W.FireEvent(to, "CHAT_MSG_ADDON", msg.prefix, msg.text, msg.channel, msg.from .. "-" .. to.realm)
        end
    end
end

local function tick(dt)
    dt = math.min(dt, 0.25)
    W.now = W.now + dt
    deliver()
    local list = {}
    for _, c in pairs(W.clients) do list[#list + 1] = c end
    table.sort(list, function(a, b) return a.short < b.short end)
    for _, c in ipairs(list) do
        if W.clients[c.short] == c then
            if c.rosterAt and c.rosterAt <= W.now then
                c.rosterAt = nil
                W.FireEvent(c, "GUILD_ROSTER_UPDATE", false)
            end
            W.TickClient(c, dt)
            if not c.member.me or W.view ~= c then botStep(c) end
        end
    end
    if W.pendingReload then local s = W.pendingReload; W.pendingReload = nil; W.Reload(s) end
    saveTimer = saveTimer + dt
    if saveTimer > 5 then saveTimer = 0; W.SaveAll() end
    panelTimer = panelTimer + dt
    if panelTimer > 1 then panelTimer = 0; W.SendPanel() end
    -- draw only when something changed (or a picture finished loading)
    if W.view then
        local c = W.view
        if host.consumeRedraw() or c.drawnVersion ~= W.visualVersion or c.drawnLayout ~= W.layoutVersion
            or W.drawnFor ~= c then
            W.Draw(c)
            c.drawnVersion, c.drawnLayout, W.drawnFor = W.visualVersion, W.layoutVersion, c
        end
    end
end

-- page pixels -> abs units (origin bottom-left)
local function toAbs(x, y)
    local k = W.PixelsPerUnit()
    return x / k, 768 - y / k
end

local function runSlash(c, text)
    local cmd, rest = text:match("^/(%S+)%s*(.*)$")
    if not cmd then
        c.env.SendChatMessage(text, "GUILD")
        return
    end
    cmd = cmd:lower()
    if cmd == "reload" or cmd == "rl" then W.Reload(c.short); return end
    if cmd == "g" or cmd == "gu" or cmd == "guild" then c.env.SendChatMessage(rest, "GUILD"); return end
    for k, v in pairs(c.env) do
        if type(k) == "string" and k:match("^SLASH_") and type(v) == "string" and v:lower() == "/" .. cmd then
            local key = k:match("^SLASH_(.-)%d+$")
            local fn = c.env.SlashCmdList[key]
            if fn then W.safecall(fn, rest); return end
        end
    end
    chatLine(c, "Unknown command: /" .. cmd, 1, 1, 0)
end

local handlers = {
    tick = function(dt) tick(dt) end,
    mousemove = function(x, y) if W.view then W.MouseMove(W.view, toAbs(x, y)) end end,
    mousedown = function(x, y, b) if W.view then local ax, ay = toAbs(x, y); W.MouseDown(W.view, ax, ay, b) end end,
    mouseup = function(x, y, b) if W.view then local ax, ay = toAbs(x, y); W.MouseUp(W.view, ax, ay, b) end end,
    wheel = function(x, y, d) if W.view then local ax, ay = toAbs(x, y); W.MouseWheel(W.view, ax, ay, d) end end,
    key = function(key)
        if W.view then return W.KeyDown(W.view, key) end
        return false
    end,
    mods = function(ctrl, shift, alt) W.keys.ctrl, W.keys.shift, W.keys.alt = ctrl and true, shift and true, alt and true end,
    slash = function(text) if W.view then runSlash(W.view, text) end end,
    view = function(name) W.SetView(name) end,
    online = function(name, on)
        if on then member(name).online = true; W.Login(name)
        else
            local m = member(name)
            if W.clients[name] then W.Logout(name) end
            m.online = false
            for _, other in pairs(W.clients) do other.rosterAt = W.now + 0.3 end
        end
        W.SendPanel()
    end,
    bot = function(name, field, value)
        local m = member(name)
        if field == "auto" then m.bot.auto = value and true or false
        elseif field == "answer" then m.bot.answer = value end
        W.SendPanel()
    end,
    state = function(field, value)
        local was = W.player.combat
        W.player[field] = value and true or false
        if field == "combat" and W.view and was ~= W.player.combat then
            W.FireEvent(W.view, W.player.combat and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
        end
    end,
    screen = function(w, h, scale)
        W.screen.pxW, W.screen.pxH, W.screen.uiScale = w, h, scale
        W.bump()
        for _, c in pairs(W.clients) do
            W.FireEvent(c, "DISPLAY_SIZE_CHANGED")
            W.FireEvent(c, "UI_SCALE_CHANGED")
        end
    end,
    reload = function() if W.view then W.Reload(W.view.short) end end,
    -- for testing: run Lua inside the shown player's addon environment and return the result as text
    eval = function(code, who)
        local c = (who and W.clients[who]) or W.view
        local env = setmetatable({ Yatzy = c.ns, client = c }, { __index = c.env, __newindex = c.env })
        local f = load("return " .. code, "=eval", "t", env) or assert(load(code, "=eval", "t", env))
        local r = { f() }
        for i = 1, #r do r[i] = tostring(r[i]) end
        return table.concat(r, "  ")
    end,
    save = function() W.SaveAll() end,
    reset = function()
        for _, m in ipairs(W.members) do host.store("yatzy-preview/" .. m.short, "") end
        for short in pairs(W.clients) do W.clients[short] = nil end
        W.view = nil
        bus.queue = {}
        for _, m in ipairs(W.members) do
            if m.online and m.addon then W.Login(m.short) end
        end
        W.SetView("Herm")
    end,
}

jsHost:setHandler(function(_, cmd, a, b, c, d)
    local fn = handlers[cmd]
    if not fn then return nil end
    local ok, res = xpcall(fn, function(e) return debug.traceback(tostring(e), 2) end, a, b, c, d)
    if not ok then W.ReportError(res); return nil end
    return res
end)

-- Log everyone in (the offline ones stay out until switched on)
for _, m in ipairs(W.members) do
    if m.online and m.addon then W.Login(m.short) end
end
W.SetView("Herm")
-- open the game window right away (like typing /yatzy)
do
    local me = W.clients.Herm
    if me and me.ns.mainWindow and not me.ns.mainWindow:IsShown() then W.safecall(me.ns.ToggleMainWindow, me.ns) end
end
