-- A fake WoW API that can run several copies of the addon side by side ("clients"),
-- each with its own saved data, connected by a fake message server ("bus").
-- Used by tests/sim_guild.lua.

local Mock = {}

local function newObject(client, kind)
    local o = { _shown = true, _scripts = {}, _events = {}, _w = 600, _h = 400, _kind = kind, _scroll = 0, _text = "" }
    local methods = {
        GetWidth = function(self) return self._w end,
        GetHeight = function(self) return self._h end,
        SetSize = function(self, w, h) self._w, self._h = w, h end,
        SetWidth = function(self, w) self._w = w end,
        SetHeight = function(self, h) self._h = h end,
        Show = function(self)
            local was = self._shown; self._shown = true
            if not was and self._scripts.OnShow then self._scripts.OnShow(self) end
        end,
        Hide = function(self)
            local was = self._shown; self._shown = false
            if was and self._scripts.OnHide then self._scripts.OnHide(self) end
        end,
        SetShown = function(self, v) if v then self:Show() else self:Hide() end end,
        IsShown = function(self) return self._shown end,
        IsVisible = function(self) return self._shown end,
        SetScript = function(self, name, fn) self._scripts[name] = fn end,
        GetScript = function(self, name) return self._scripts[name] end,
        RegisterEvent = function(self, e) self._events[e] = true end,
        UnregisterEvent = function(self, e) self._events[e] = nil end,
        GetCenter = function() return 100, 100 end,
        GetLeft = function() return 0 end,
        GetBottom = function() return 0 end,
        GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
        GetFrameLevel = function() return 1 end,
        GetStringWidth = function() return 20 end,
        GetText = function(self) return self._text end,
        SetText = function(self, t) self._text = t end,
        GetChecked = function(self) return self._checked end,
        SetChecked = function(self, v) self._checked = v end,
        IsEnabled = function(self) return self._enabled ~= false end,
        SetEnabled = function(self, v) self._enabled = v end,
        Enable = function(self) self._enabled = true end,
        Disable = function(self) self._enabled = false end,
        GetFont = function() return "font" end,
        GetVerticalScroll = function(self) return self._scroll end,
        SetVerticalScroll = function(self, v) self._scroll = v end,
        CreateTexture = function() return newObject(client, "Texture") end,
        CreateMaskTexture = function() return newObject(client, "MaskTexture") end,
        CreateFontString = function() return newObject(client, "FontString") end,
        CreateAnimationGroup = function() return newObject(client, "AnimationGroup") end,
        CreateAnimation = function() return newObject(client, "Animation") end,
    }
    return setmetatable(o, { __index = function(_, k) return methods[k] or function() end end })
end

-- Behaves like WoW: Forever as observed in game:
--  * each client writes EVERY name with its own (internal) realm string, so the same
--    player is "Bo-EU4" for Anna and "Bo-EU5" for himself;
--  * characters can have a surname that only the guild roster shows
--    ("Father Ghouliath" in the roster, "Father" for UnitName and chat senders);
--  * whispering "Name-Realm" fails ("No player named ..."); guild messages reach everyone.
-- bus = { clients = {[short]=client}, members = { {short=, online=} }, queue = {} }
function Mock.NewBus()
    return { clients = {}, members = {}, queue = {}, time = 0, failed = 0 }
end

-- Log a player in or out; everyone's guild roster refreshes (like the 30 s roster timer would).
function Mock.SetOnline(bus, short, online)
    for _, m in ipairs(bus.members) do
        if m.short == short then m.online = online end
    end
    local c = bus.clients[short]
    if c then c.online = online end
    for _, other in pairs(bus.clients) do other.rosterRequested = true end
end

-- How `client` sees player `short` in its guild roster: with surname and the viewer's realm
function Mock.RosterName(client, short)
    local c = client.bus.clients[short]
    local full = c and c.surname and (short .. " " .. c.surname) or short
    return full .. "-" .. client.realm
end

-- `short` = the game's name for the character (UnitName); `surname` shows only in the roster
function Mock.NewClient(bus, short, realm, surname)
    local client = { bus = bus, short = short, surname = surname, realm = realm, name = short .. "-" .. realm,
                     frames = {}, timers = {}, online = true }
    local env = setmetatable({}, { __index = _G })
    client.env = env

    env.CreateFrame = function(kind, name)
        local f = newObject(client, kind)
        if name then env[name] = f end
        client.frames[#client.frames + 1] = f
        return f
    end
    env.UIParent = newObject(client, "Frame")
    env.Minimap = newObject(client, "Frame")
    env.GameTooltip = newObject(client, "Frame")
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) client.chat = (client.chat or "") .. msg .. "\n" end }
    env.RaidWarningFrame = newObject(client, "Frame")
    env.RaidNotice_AddMessage = function(_, msg) client.warnings = (client.warnings or 0) + 1 end
    env.ChatTypeInfo = { RAID_WARNING = {} }
    env.UISpecialFrames = {}
    env.SlashCmdList = {}
    env.StaticPopupDialogs = {}
    env.StaticPopup_Show = function(which) local d = env.StaticPopupDialogs[which]; if d and d.OnAccept then d.OnAccept() end end
    env.SOUNDKIT = setmetatable({}, { __index = function() return 1 end })
    env.PlaySound = function() end
    env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    env.tinsert = table.insert
    env.strlower = string.lower
    env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    env.unpack = unpack
    env.time = function() return 1800000000 + math.floor(bus.time) end
    env.GetTime = function() return bus.time end
    env.UnitName = function() return short end
    env.GetNormalizedRealmName = function() return "ForeverRealm" end   -- differs from the roster's realm string, like in game
    env.GetCursorPosition = function() return 0, 0 end
    env.IsInGuild = function() return true end
    client.guildChat = {}
    env.SendChatMessage = function(msg, kind) client.guildChat[#client.guildChat + 1] = kind .. ": " .. msg end
    env.C_Timer = {
        After = function(_, fn) client.timers[#client.timers + 1] = fn end,
        NewTicker = function() end,
    }
    env.C_GuildInfo = { GuildRoster = function() client.rosterRequested = true end }
    env.GetNumGuildMembers = function() return #bus.members end
    env.GetGuildRosterInfo = function(i)
        local m = bus.members[i]
        return Mock.RosterName(client, m.short), "Member", 1, 60, "Warrior", "Zone", "", "", m.online
    end
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function(prefix, text, channel, target)
            bus.sent = (bus.sent or 0) + 1
            if channel == "GUILD" then
                -- every online guild member gets it, the sender too (like WoW)
                for name, c in pairs(bus.clients) do
                    if c.online then
                        bus.queue[#bus.queue + 1] = { from = client.short, to = name, prefix = prefix, text = text }
                    end
                end
                return
            end
            local to = bus.clients[target]                -- whispers: only the plain name works
            if not to or not to.online then
                bus.failed = bus.failed + 1
                return
            end
            bus.queue[#bus.queue + 1] = { from = client.short, to = target, prefix = prefix, text = text }
        end,
    }

    bus.clients[short] = client
    bus.members[#bus.members + 1] = { short = short, online = true }

    -- Load the addon into this client's environment
    client.ns = {}
    for line in io.lines("Yatzy/Yatzy.toc") do
        local file = line:match("^%s*(%S+%.lua)%s*$")
        if file then
            local chunk = assert(loadfile("Yatzy/" .. file))
            setfenv(chunk, env)
            chunk("Yatzy", client.ns)
        end
    end
    Mock.Fire(client, "ADDON_LOADED", "Yatzy")
    Mock.Fire(client, "PLAYER_ENTERING_WORLD")
    for _, other in pairs(bus.clients) do other.rosterRequested = true end   -- others see the login
    return client
end

function Mock.Fire(client, event, ...)
    for _, f in ipairs(client.frames) do
        local h = f._scripts.OnEvent
        if h and f._events[event] then h(f, event, ...) end
    end
end

-- Run everything until nothing more happens: messages, timers, animations, roster updates.
function Mock.Pump(bus)
    for _ = 1, 5000 do
        local busy = false
        bus.time = bus.time + 0.1
        for _, c in pairs(bus.clients) do
            if c.online then
                if c.rosterRequested then
                    c.rosterRequested = false
                    Mock.Fire(c, "GUILD_ROSTER_UPDATE")
                    busy = true
                end
                local board = c.ns.Board and c.ns.Board.frame
                if board and board._scripts.OnUpdate then board._scripts.OnUpdate(board, 0.1); busy = true end
                if #c.timers > 0 then
                    local run = c.timers; c.timers = {}
                    for _, fn in ipairs(run) do fn() end
                    busy = true
                end
            end
        end
        if #bus.queue > 0 then
            local q = bus.queue; bus.queue = {}
            for _, m in ipairs(q) do
                local to = bus.clients[m.to]
                if to and to.online then
                    -- the receiver sees the game's name (no surname) with ITS OWN realm string
                    Mock.Fire(to, "CHAT_MSG_ADDON", m.prefix, m.text, "GUILD", m.from .. "-" .. to.realm)
                end
            end
            busy = true
        end
        if not busy then return end
    end
    error("pump: things never settled")
end

return Mock
