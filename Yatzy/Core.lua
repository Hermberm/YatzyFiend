-- Core.lua
-- Sets up the addon: saved settings, slash command, and combat auto-hide.

local ADDON_NAME, Yatzy = ...
Yatzy.version = "0.12.1"
-- The addon's name as players see it (title bar, start screen, minimap tooltip).
-- Also in Yatzy.toc ("## Title:"). The folder, saved data and messages keep the name "Yatzy".
Yatzy.DISPLAY_NAME = "YatzyFiend"

-- Settings every player starts with. Anything missing from the saved
-- data (for example after an update adds a new option) is filled in from here.
local defaults = {
    minimap = { angle = 225, hide = false },
    window  = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0, width = 780, height = 460 },
    options = { hideInCombat = true, acceptInvites = true, sound = true, turnAlert = true, sheetOpen = true,
                fade = true, fadeLevel = "low", soundVolume = "low", escCloses = true,
                announceYatzy = true, helpDeliver = true, sheetDetached = false, customSounds = false },
    stats   = {
        solo  = { played = 0, won = 0, best = 0, yatzys = 0 },
        guild = { played = 0, won = 0, best = 0, yatzys = 0 },
    },
}

local function applyDefaults(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            applyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

function Yatzy:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Yatzy:|r " .. tostring(message))
end

function Yatzy:PlayUISound(kitName)
    if self.db and self.db.options.sound and SOUNDKIT and SOUNDKIT[kitName] then
        PlaySound(SOUNDKIT[kitName])
    end
end

-- Events -----------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED") -- entered combat
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- left combat

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        YatzyDB = YatzyDB or {}
        applyDefaults(YatzyDB, defaults)
        Yatzy.db = YatzyDB

        -- Games belong to the character playing them (alts don't share games).
        YatzyCharDB = YatzyCharDB or {}
        YatzyCharDB.games = YatzyCharDB.games or {}
        Yatzy.charDB = YatzyCharDB
        -- Older versions kept games account-wide: move them to the first character that logs in.
        if type(YatzyDB.games) == "table" then
            for _, g in ipairs(YatzyDB.games) do table.insert(YatzyCharDB.games, g) end
            YatzyDB.games = nil
        end

        Yatzy.Style.PreloadFonts()
        Yatzy:CreateMainWindow()
        Yatzy:CreateMinimapButton()
        if Yatzy.TurnBanner then Yatzy.TurnBanner:Init() end     -- "Your turn!" box at the top of the screen
        if Yatzy.Guild then Yatzy.Guild:Init() end
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_REGEN_DISABLED" then
        Yatzy.inCombat = true                   -- used by fading (combat values may be secret)
        local window = Yatzy.mainWindow
        if Yatzy.db and Yatzy.db.options.hideInCombat and window and window:IsShown() then
            Yatzy.hiddenByCombat = true
            window:Hide()
        end
        local bg = Yatzy.BGBoard and Yatzy.BGBoard.window      -- the backgammon window too
        if Yatzy.db and Yatzy.db.options.hideInCombat and bg and bg:IsShown() then
            Yatzy.bgHiddenByCombat = true
            bg:Hide()
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        Yatzy.inCombat = false
        -- addon messages may have been held back or hidden in combat: compare notes now
        if Yatzy.Guild then C_Timer.After(3, function() Yatzy.Guild:Heartbeat(true) end) end
        if Yatzy.hiddenByCombat then
            Yatzy.hiddenByCombat = false
            Yatzy.mainWindow:Show()
        end
        if Yatzy.bgHiddenByCombat then
            Yatzy.bgHiddenByCombat = false
            if Yatzy.BGPlay.game then Yatzy.BGPlay:Open(Yatzy.BGPlay.game) end
        end
    end
end)

-- Slash command: /yatzy ----------------------------------------------------

SLASH_YATZY1 = "/yatzy"
SlashCmdList["YATZY"] = function(input)
    local command = strlower(strtrim(input or ""))

    if command == "" then
        Yatzy:ToggleMainWindow()
    elseif command == "minimap" then
        Yatzy:SetMinimapButtonShown(Yatzy.db.minimap.hide)
    elseif command == "reset" then
        Yatzy:ResetWindowPosition()
        Yatzy:Print("Window position reset.")
    elseif command == "debug" then
        -- Shows how names are written and every addon message sent/received
        Yatzy.debug = not Yatzy.debug
        Yatzy:Print("Debug " .. (Yatzy.debug and "ON: addon messages are shown in chat." or "OFF."))
        if Yatzy.debug then
            local G = Yatzy.Guild
            Yatzy:Print(("Version %s. Me: %s. Realm (roster): %s. Realm (WoW): %s.")
                :format(Yatzy.version, tostring(G:MyName()), tostring(G.realm),
                    tostring(GetNormalizedRealmName and GetNormalizedRealmName())))
            local online = {}
            for _, m in ipairs(G:Members()) do
                if m.online then
                    online[#online + 1] = G:Short(m.name) .. " (" .. (G:VersionOf(m.name) and ("Yatzy v" .. G:VersionOf(m.name)) or "no Yatzy seen") .. ")"
                end
            end
            Yatzy:Print("Online guild members: " .. (#online > 0 and table.concat(online, ", ") or "none"))
            -- Every saved game of this character, also hidden ones
            local all = Yatzy.Games:All()
            Yatzy:Print(("%d saved game(s), %d shown in the list:"):format(#all, #Yatzy.Games:Sorted()))
            for _, g in ipairs(all) do
                Yatzy:Print(("  %s  %s  %s  answers=%s  mine=%s%s"):format(
                    tostring(g.kind), tostring(g.status), Yatzy.Games:Title(g), tostring(g.answers),
                    tostring(g.kind == "guild" and G:MyAnswer(g)), g.hidden and "  (hidden)" or ""))
            end
        end
    elseif command == "soundtest" then
        Yatzy.Sound:Test()
    elseif command == "fade" then
        Yatzy.db.options.fade = not Yatzy.db.options.fade
        Yatzy:Print("Fading when the mouse is away: " .. (Yatzy.db.options.fade and "on" or "off") .. ".")
    elseif command:match("^size") then
        local pct = tonumber(command:match("(%d+)"))
        if pct then Yatzy.UI:SetWindowScale(pct / 100)
        else Yatzy:Print("Usage: /yatzy size 50-120   (or Ctrl + mouse wheel over the title bar)") end
    elseif command == "sync" then
        Yatzy.Guild:RequestRoster()
        Yatzy.Guild:AskWhoHasYatzy()
        for _, m in ipairs(Yatzy.Guild:Members()) do
            if m.online then Yatzy.Guild:SyncWith(m.name) end
        end
        Yatzy:Print("Syncing games with online guild members...")
    else
        Yatzy:Print("Commands:")
        Yatzy:Print("  /yatzy - open or close the game window")
        Yatzy:Print("  /yatzy minimap - show or hide the minimap button")
        Yatzy:Print("  /yatzy reset - move the window back to the center")
        Yatzy:Print("  /yatzy size 80 - window size in % (also: Ctrl + mouse wheel over the title bar)")
        Yatzy:Print("  /yatzy fade - turn fading on/off while you move or fight")
        Yatzy:Print("  /yatzy soundtest - play every sound and check that WoW can play them")
        Yatzy:Print("  /yatzy sync - send your guild games to online players now")
        Yatzy:Print("  /yatzy debug - show addon messages (for troubleshooting)")
    end
end
