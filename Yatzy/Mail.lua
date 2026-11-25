-- Mail.lua
-- "Guild mailmen": a guild member with the addon keeps a small copy ("parcel") of the games
-- he overhears, even games he isn't in, and hands it to a player of that game who comes
-- online later. That way a turn reaches Bo even if Anna, who played it, is long gone.
-- (PLAN.md, "Guild mailmen".)
--
-- Nothing extra is sent to fill a parcel: every state ("S"/"BS") and turn ("T"/"BT") already
-- goes over the guild channel to everybody. A parcel has the same fields as a state message
-- plus the turns as the short strings that are sent today.
--
-- Handing over:
--  * A player who logs in asks (Mail:Ask): "MQ" = "any invitations for me?" and a state message
--    for each game where someone else is offline. A mailman that has more than the player
--    answers after a random wait (and stays quiet if another mailman got there first).
--  * Mailman messages carry the marker "M" in their last field (state: 8th, turns: 4th). The
--    receiving player accepts them from someone who isn't in the game, and still checks every
--    turn against the rules, so a mailman can delay a game but never change it.
--  * When a mailman lacks turns that a player has, he asks that player with a state message.
-- Versions without this ignore the marker, and ignore "MQ" altogether.

local _, Yatzy = ...
local Mail = {}
Yatzy.Mail = Mail

local MAX_PARCELS = 40
local KEEP = 14 * 86400            -- a parcel with no news for 14 days is thrown away
local MAX_TURN = 600               -- no game has more turns than this
local MAX_LENGTH = 190             -- characters of turn entries in one message (limit is 250)
local SEEN = 120                   -- seconds before the same delivery is repeated

local pending = {}                 -- [key] = true while a delayed message may still go out
local recent = {}                  -- [id|name] = { count =, t = } what I last delivered

local function Guild() return Yatzy.Guild end
local function Games() return Yatzy.Games end
local function now() return GetTime and GetTime() or 0 end
local function later(key, seconds, fn)
    pending[key] = true
    C_Timer.After(seconds, function()
        if pending[key] then pending[key] = nil; fn() end
    end)
end
local function wait(a, b) return a + math.random() * (b - a) end

function Mail:Enabled()
    return Yatzy.db and Yatzy.db.options.helpDeliver ~= false
end

function Mail:Parcels()
    Yatzy.db.mail = Yatzy.db.mail or {}
    return Yatzy.db.mail
end

local function split(s)
    local list = {}
    for name in (s or ""):gmatch("[^,]+") do list[#list + 1] = name end
    return list
end

local function seatOf(p, name)
    for i, n in ipairs(split(p.invited)) do
        if Guild():SameName(n, name) then return i end
    end
end

local function setChar(s, i, c) return s:sub(1, i - 1) .. c .. s:sub(i + 1) end

-- Fill in what I don't know from `theirs` (unknown = "?" for answers, "N" for left flags).
-- Returns the new string, whether it changed, and whether `theirs` lacks something I know.
local function merge(mine, theirs, unknown, closedWins)
    local changed, theyLack = false, false
    for i = 1, #mine do
        local a, b = mine:sub(i, i), theirs:sub(i, i)
        if closedWins and b == "X" and a ~= "X" then
            mine = setChar(mine, i, "X"); changed = true
        elseif a == unknown and b ~= unknown and b ~= "" then
            mine = setChar(mine, i, b); changed = true
        elseif (closedWins and a == "X" and b ~= "X") or (b == unknown and a ~= unknown) then
            theyLack = true
        end
    end
    return mine, changed, theyLack
end

function Mail:Prune()
    local parcels, t = self:Parcels(), time()
    local n = 0
    for id, p in pairs(parcels) do
        if t - (p.updated or 0) > KEEP then parcels[id] = nil else n = n + 1 end
    end
    while n > MAX_PARCELS do                       -- too many: drop the one with the oldest news
        local oldest, oldestId
        for id, p in pairs(parcels) do
            if not oldest or (p.updated or 0) < oldest then oldest, oldestId = p.updated or 0, id end
        end
        parcels[oldestId] = nil
        n = n - 1
    end
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

local function kindOf(p, base) return p.game == "backgammon" and ("B" .. base) or base end

function Mail:SendState(id, to)
    local p = self:Parcels()[id]
    if not p then return end
    Yatzy.Comm:Send(to, kindOf(p, "S"), id, p.creator, p.invited, p.answers, p.left,
        tostring(p.count), p.fast and "F" or "-", "M")
end

function Mail:SendTurns(id, to, first, last)
    local p = self:Parcels()[id]
    if not p then return end
    local n = first
    while n <= last do
        local entries, length, start = {}, 0, n
        while n <= last and p.turns[n] and length + #p.turns[n] + 1 <= MAX_LENGTH do
            entries[#entries + 1] = p.turns[n]
            length = length + #p.turns[n] + 1
            n = n + 1
        end
        if #entries == 0 then return end
        Yatzy.Comm:Send(to, kindOf(p, "T"), id, tostring(start), table.concat(entries, ";"), "M")
    end
end

-- Give `who` (a player) what he lacks: the turns after `theirTurns`, and the state if his
-- answers/left flags are behind mine.
function Mail:Deliver(id, who, theirTurns, withState)
    local p = self:Parcels()[id]
    if not p or not self:Enabled() then return end
    local key, t = id .. "|" .. Guild():Short(who), now()
    local r = recent[key]
    if r and r.count == p.count and r.state == withState and t - r.t < SEEN then return end
    recent[key] = { count = p.count, state = withState, t = t }
    if p.count > theirTurns then self:SendTurns(id, who, theirTurns + 1, p.count) end
    if withState then self:SendState(id, who) end
end

-- I miss turns that `player` has: tell him what I have, so he sends the rest.
function Mail:Request(id, player, theirTurns)
    local key = id .. "|r|" .. Guild():Short(player)
    if pending[key] then return end
    later(key, wait(1.5, 5), function()
        local p = Mail:Parcels()[id]
        if p and p.count < theirTurns then Mail:SendState(id, player) end    -- still lacking?
    end)
end

local function cancelDeliveries(id)
    for key in pairs(pending) do
        if key:sub(1, #id + 3) == id .. "|d|" then pending[key] = nil end
    end
end

---------------------------------------------------------------------------
-- Hearing (called from Guild.lua for games I'm not in)
---------------------------------------------------------------------------

-- A state message about a game I'm not in.
-- toMe: it is addressed to me or to everybody; isAll: addressed to everybody.
function Mail:HearState(f, sender, toMe, isAll, game)
    if not self:Enabled() then return end
    local G = Guild()
    local id, creator, invitedStr, answers, left = f[1], f[2], f[3], f[4], f[5]
    if not (id and creator and invitedStr and answers and left) then return end
    local invited = split(invitedStr)
    local maxPlayers = game == "backgammon" and 2 or Yatzy.Rules.MAX_PLAYERS
    if #invited < 2 or #invited > maxPlayers or #answers ~= #invited or #left ~= #invited then return end
    local me = G:MyName()
    for _, n in ipairs(invited) do
        if G:SameName(n, me) then
            self:Parcels()[id] = nil                  -- I'm a player after all: the game is mine
            return
        end
    end
    local theirTurns = tonumber(f[6]) or 0
    local fromMailman = f[8] == "M"
    local isPlayer = false
    for _, n in ipairs(invited) do
        if G:SameName(n, sender) then isPlayer = true end
    end
    if not isPlayer and not fromMailman then return end

    local parcels = self:Parcels()
    local p = parcels[id]
    local gameName = game or "yatzy"
    if not p then
        p = { game = gameName, creator = creator, invited = invitedStr, answers = answers,
              left = left, turns = {}, count = 0, updated = time() }
        parcels[id] = p
        self:Prune()
    end
    if p.game ~= gameName or p.invited ~= invitedStr then return end
    if f[7] == "F" then p.fast = true end

    local changedA, changedL, lackA, lackL
    p.answers, changedA, lackA = merge(p.answers, answers, "?", true)
    p.left, changedL, lackL = merge(p.left, left, "N", false)
    if changedA or changedL then p.updated = time() end
    if fromMailman then return end                    -- just copy it; someone is already delivering

    if p.count < theirTurns then
        self:Request(id, sender, theirTurns)          -- he has turns I haven't heard
    end
    if toMe and (p.count > theirTurns or lackA or lackL) then
        local withState = (lackA or lackL) and true or false
        if isAll then
            -- Everybody heard this: wait a little, and stay quiet if another mailman delivers first
            later(id .. "|d|" .. G:Short(sender), wait(1.5, 6), function()
                Mail:Deliver(id, sender, theirTurns, withState)
            end)
        else
            self:Deliver(id, sender, theirTurns, withState)
        end
    end
end

-- Turns for a game I'm not in.
function Mail:HearTurns(f, sender, toMe, game)
    if not self:Enabled() then return end
    local id, first = f[1], tonumber(f[2])
    local p = id and self:Parcels()[id]
    if not p or not first or not f[3] or p.game ~= (game or "yatzy") then return end
    local fromMailman = f[4] == "M"
    if not fromMailman and not seatOf(p, sender) then return end
    if fromMailman then cancelDeliveries(id) end      -- someone is delivering already
    local n, stored = first, false
    for entry in (f[3] .. ";"):gmatch("([^;]*);") do
        local ok
        if p.game == "backgammon" then ok = entry:match("^[1-6][1-6]%l*$")
        else ok = entry:match("^%l%d%d%d%d%d%d+$") end
        if ok and n >= 1 and n <= MAX_TURN and not p.turns[n] then
            p.turns[n] = entry
            stored = true
        end
        n = n + 1
    end
    if stored then
        while p.turns[p.count + 1] do p.count = p.count + 1 end
        p.updated = time()
    end
end

-- "MQ": a player has just logged in and asks for invitations waiting for him.
function Mail:OnQuery(f, sender)
    if not self:Enabled() then return end
    local G = Guild()
    for id, p in pairs(self:Parcels()) do
        local seat = seatOf(p, sender)
        if seat and p.answers:sub(seat, seat) == "?" and time() - (p.updated or 0) < 7 * 86400 then
            later(id .. "|d|" .. G:Short(sender), wait(2, 8), function()
                Mail:Deliver(id, sender, p.count, true)
            end)
        end
    end
end

-- I have just logged in: ask the mailmen for invitations, and tell them what I know of my
-- games where someone else is offline (they answer if they have more).
function Mail:Ask()
    local G = Guild()
    if not G:InGuild() then return end
    Yatzy.Comm:Send("*", "MQ", "1")
    local sent = 0
    for _, g in ipairs(Games():All()) do
        if g.kind == "guild" and (g.status == "active" or g.status == "pending") and sent < 8 then
            local someoneOffline = false
            for _, name in ipairs(G:Others(g)) do
                if not G:IsOnline(name) then someoneOffline = true end
            end
            if someoneOffline then
                G:SendState(g, "*")
                sent = sent + 1
            end
        end
    end
end
