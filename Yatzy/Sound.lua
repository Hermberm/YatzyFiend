-- Sound.lua
-- Minimal, realistic sounds (CC0 by Kenney.nl, see Media\Sounds\CREDITS.txt):
--   roll / rollOne  dice thrown on the table (several dice / a single die)
--   hold            a die picked up and put in the tray
--   turn            it's your turn
--   invite          you got a game invitation
--   yatzy           someone rolled a Yatzy
-- Each comes in a Low (default) and a Normal version; WoW can't set the volume of a
-- single sound, so the files themselves are quieter. They play on the "SFX" channel,
-- so WoW's own sound-effects slider applies as well.
--
-- Your own sounds: put a file named yatzy.ogg (or .mp3), turn.ogg or invite.ogg in
--   Interface\AddOns\Yatzy\Media\Sounds\Custom\
-- restart WoW, and turn on Settings -> "Use my own sound files". Your file is then
-- played instead of the built-in one.

local _, Yatzy = ...
local Sound = {}
Yatzy.Sound = Sound

local DIR = "Interface\\AddOns\\Yatzy\\Media\\Sounds\\"
local CUSTOM = DIR .. "Custom\\"
local CHANNEL = "SFX"

Sound.SETS = {
    roll    = { "DiceThrow1", "DiceThrow2", "DiceThrow3" },
    rollOne = { "DieThrow1", "DieThrow2", "DieThrow3", "DieThrow4" },
    hold    = { "DiceGrab1", "DiceGrab2" },
    turn    = { "YourTurn" },
    chime   = { "TurnChime" },          -- very soft shimmer with the "Your turn!" popup
    invite  = { "Invite" },
    yatzy   = { "Yatzy" },
}
local CUSTOMIZABLE = { yatzy = true, turn = true, invite = true }

Sound.LEVELS = { "low", "normal", "high", "off" }    -- order used by the Sound button
local FOLDER = { low = "Low", normal = "Normal", high = "High" }
-- High plays on WoW's Master channel, so a low "Sound Effects" slider doesn't hold it back
local CHANNEL_FOR = { low = "SFX", normal = "SFX", high = "Master" }

local function level()
    local opts = Yatzy.db.options
    if opts.sound == false then return "off" end
    return opts.soundVolume or "low"
end

function Sound:Level() return level() end

-- Cycle Low -> Normal -> High -> Off -> Low (the title-bar Sound button)
function Sound:NextLevel()
    local current = level()
    local next = "low"
    for i, l in ipairs(self.LEVELS) do
        if l == current then next = self.LEVELS[i % #self.LEVELS + 1] end
    end
    Yatzy.db.options.sound = next ~= "off"
    if next ~= "off" then Yatzy.db.options.soundVolume = next end
    if next ~= "off" then self:Play("rollOne") end      -- a short sample at the new volume
    return next
end

-- /yatzy soundtest: plays every sound once (ignoring the Off setting) and reports in
-- chat whether WoW could play each file, to find out why sound might be missing.
function Sound:Test()
    local l = level()
    local folder = FOLDER[l] or "Low"
    local channel = CHANNEL_FOR[l] or CHANNEL
    Yatzy:Print(("Sound test. Setting: %s. Files: Media\\Sounds\\%s. WoW channel: %s."):format(l, folder, channel))
    if l == "off" then Yatzy:Print("Sound is set to OFF in Yatzy (title bar button or Settings) - playing anyway for the test.") end
    if GetCVar then
        Yatzy:Print(("WoW settings: sound %s, effects %s (volume %s), master volume %s.")
            :format(GetCVar("Sound_EnableAllSound") == "1" and "on" or "OFF",
                    GetCVar("Sound_EnableSFX") == "1" and "on" or "OFF",
                    tostring(GetCVar("Sound_SFXVolume")), tostring(GetCVar("Sound_MasterVolume"))))
    end
    local names = { "roll", "rollOne", "hold", "turn", "invite", "yatzy" }
    for i, name in ipairs(names) do
        C_Timer.After((i - 1) * 1.2, function()
            local file = DIR .. folder .. "\\" .. self.SETS[name][1] .. ".ogg"
            local ok = PlaySoundFile and PlaySoundFile(file, channel)
            Yatzy:Print(("  %-8s %s"):format(name, ok and "|cff7ad36aplayed|r" or ("|cffff5555WoW could not play|r " .. file)))
        end)
    end
end

function Sound:Play(name)
    local l = level()
    if l == "off" or not PlaySoundFile then return end
    local channel = CHANNEL_FOR[l] or CHANNEL
    -- Your own sound files only when turned on in Settings: the client may report a missing
    -- custom file as played, and then the built-in sound was skipped (silent "your turn").
    if CUSTOMIZABLE[name] and Yatzy.db.options.customSounds == true then
        for _, ext in ipairs({ ".ogg", ".mp3" }) do
            if PlaySoundFile(CUSTOM .. name .. ext, channel) then return end
        end
    end
    local list = self.SETS[name]
    if not list then return end
    local file = list[math.random(#list)]
    PlaySoundFile(DIR .. (FOLDER[l] or "Low") .. "\\" .. file .. ".ogg", channel)
end
