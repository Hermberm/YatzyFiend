-- Comm.lua
-- Hidden addon messages between players, sent over the GUILD addon channel.
--
-- Why the guild channel and not whispers: on WoW: Forever, whispering by name failed
-- (each client writes realm names differently, and names can contain spaces). Guild
-- addon messages need no name at all; every guild member with Yatzy receives them and
-- each addon keeps only what concerns its own games. Traffic is tiny (a few short
-- messages per turn) and invisible in chat.
--
-- Every message:  K:to:field:field:...
--   K  = what it is: one letter for Yatzy, two letters starting with B for backgammon
--   to = who should ANSWER it ("*" = anyone, otherwise a character name). Everyone may
--        still use the information in it (that's how turns spread to every player).

local _, Yatzy = ...
local Comm = {}
Yatzy.Comm = Comm

Comm.PREFIX = "YATZY2"          -- protocol 2 = guild channel (older versions used YATZY1)
local MAX_LENGTH = 250          -- WoW allows 255 characters per message
local BURST = 6                 -- messages that may go out at once
local REFILL = 1.0              -- seconds until one more message may be sent

local queue = {}
local tokens = BURST
local lastRefill = 0
local pumpScheduled = false
local handlers = {}

local function now() return GetTime and GetTime() or 0 end

function Comm:Init()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(self.PREFIX)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(self.PREFIX)
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:SetScript("OnEvent", function(_, _, prefix, text, _, sender)
        -- In combat inside an instance the game can hand addons "secret" values that may not
        -- be read. Such a message is skipped; the regular state check (Guild:Heartbeat) gets
        -- the turn across afterwards.
        if issecretvalue and (issecretvalue(prefix) or issecretvalue(text) or issecretvalue(sender)) then return end
        if prefix ~= Comm.PREFIX then return end
        local ok, err = pcall(Comm.Receive, Comm, text, sender)
        if not ok then Yatzy:Print("|cffff5555error|r reading an addon message: " .. tostring(err)) end
    end)
    lastRefill = now()
end

-- Register a handler for one message kind: fn(fields, sender, addressedToMe, addressedToAll)
function Comm:On(kind, fn)
    handlers[kind] = fn
end

function Comm:Receive(text, sender)
    local Guild = Yatzy.Guild
    if not sender or Guild:SameName(sender, Guild:MyName()) then return end   -- our own message echoed back
    -- (kinds of more than one letter, e.g. "BS" for backgammon, are skipped by versions
    -- before 0.10, which only read one letter: so they never mix up the two games)
    local kind, to, rest = text:match("^(%a+):([^:]*):?(.*)$")
    local fn = kind and handlers[kind]
    if not fn then return end
    if Yatzy.debug then Yatzy:Print(("|cff88ccffin|r %s: %s"):format(sender, text)) end
    local fields = {}
    for field in (rest .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = field end
    local toMe = to == "*" or Guild:SameName(to, Guild:MyName())
    Guild:SawOnline(sender)
    local ok, err = pcall(fn, fields, Guild:FullName(sender), toMe, to == "*")
    -- Always report problems (they're caught here, so BugSack wouldn't see them)
    if not ok then Yatzy:Print("|cffff5555error|r handling a message from " .. tostring(sender) .. ": " .. tostring(err)) end
end

-- Send a message to the guild. `to` = who should answer: a name, or nil/"*" for anyone.
function Comm:Send(to, kind, ...)
    local addressee = (to and to ~= "*") and Yatzy.Guild:Short(to) or "*"
    local text = kind .. ":" .. addressee .. ":" .. table.concat({ ... }, ":")
    if #text > MAX_LENGTH then
        Yatzy:Print("|cffff5555error|r message too long, not sent: " .. text:sub(1, 40))
        return
    end
    queue[#queue + 1] = { text = text, tries = 0 }
    self:Pump()
end

local RETRY_WAIT = 5            -- seconds before a message the game refused is tried again
local MAX_TRIES = 8             -- then it is dropped (the regular state check covers it)

-- The game may refuse addon messages for a while (throttling, or a chat lockdown in combat
-- inside instances). Older clients return nothing or true; newer ones a result code (0 = sent).
local function lockedDown()
    local fn = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
    if not fn then return false end
    local ok, locked = pcall(fn)
    return ok and locked == true
end

local function sendNow(prefix, text)
    local ok, result
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        ok, result = pcall(C_ChatInfo.SendAddonMessage, prefix, text, "GUILD")
    elseif SendAddonMessage then
        ok, result = pcall(SendAddonMessage, prefix, text, "GUILD")
    else
        return true
    end
    if not ok then return false end
    if result == nil or result == true or result == 0 then return true end
    return false
end

local function schedule(seconds)
    if pumpScheduled then return end
    pumpScheduled = true
    C_Timer.After(seconds, function()
        pumpScheduled = false
        Comm:Pump()
    end)
end

function Comm:Pump()
    if #queue == 0 then return end
    if lockedDown() then schedule(RETRY_WAIT); return end      -- wait until the game allows it again
    local t = now()
    tokens = math.min(BURST, tokens + (t - lastRefill) / REFILL)
    lastRefill = t
    while tokens >= 1 and #queue > 0 do
        local item = table.remove(queue, 1)
        tokens = tokens - 1
        if Yatzy.debug then Yatzy:Print(("|cffffaa55out|r %s"):format(item.text)) end
        if not sendNow(self.PREFIX, item.text) then
            item.tries = item.tries + 1
            if item.tries < MAX_TRIES then
                table.insert(queue, 1, item)                       -- keep the order: try again later
                schedule(RETRY_WAIT)
                return
            end
            if Yatzy.debug then Yatzy:Print("|cffff5555dropped|r " .. item.text) end
        end
    end
    if #queue > 0 then schedule(REFILL) end
end

function Comm:QueueLength()
    return #queue
end
