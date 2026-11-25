-- Guild.lua
-- Games against guild members, played turn by turn like Wordfeud: players don't
-- need to be online at the same time.
--
-- How it works (see PLAN.md, section 6):
--  * Every player keeps a full copy of each game. There is no host.
--  * Whenever two players of a game are online at the same time, their addons
--    compare notes ("S" = state) and send each other whatever the other is missing:
--    invitation answers, players who left, and finished turns ("T").
--  * Anyone who has a turn passes it on, so turns spread even after their author logs off.
--  * Turn order is fixed when the game starts, so copies can be behind but never disagree.
--  * While you're online together you also see each other's rolls live ("R").
--
-- Messages go over the guild addon channel (see Comm.lua); "to" says who should answer.
--   P:to:version:ask              "I have Yatzy" (ask=1: everyone please answer)
--   S:to:id:creator:invited(comma list):answers:left:turnsDone
--        answers/left: one letter per invited player (Y = yes, N = no, ? = unknown,
--        X = didn't answer before the creator started the game / the invitation ran out).
--        Only the creator ever writes X, and an X always wins over Y/N/?, so every copy
--        ends up with the creator's player list (see Guild:StartNow).
--   T:to:id:firstTurn:entries     entries ";"-separated, each <category letter><5 dice><points>
--   R:to:id:turn:rollNo:dice:heldMask     (live view only)
--   H:to:id:turn:rollNo:heldMask          (live view only: dice saved between rolls)
--
-- Backgammon games use the same flow with their own message kinds, which versions
-- before 0.10 skip (see Comm.lua), so an old client never mistakes one for a Yatzy game:
--   BS  = S for a backgammon game (same fields)
--   BT:to:id:firstTurn:entries    each entry: <2 dice><moves, two letters each> (BG.EncodeMoves)
--   BM:to:id:turn:dice:moves      (live view only: the dice and the moves made so far this turn)
-- A backgammon game has 2 players. Its opening roll comes from the game id, so every copy
-- has the same. A player who leaves gives up: the other one wins.

local _, Yatzy = ...
local Rules = Yatzy.Rules
local BG = Yatzy.BG

local function isBG(g) return g.game == "backgammon" end
local function kindFor(g, base) return isBG(g) and ("B" .. base) or base end
local Guild = {}
Yatzy.Guild = Guild

local ROSTER_INTERVAL = 30           -- seconds between guild roster refreshes
local KEEP_FINISHED_SYNC = 14 * 86400 -- keep syncing finished games for 14 days
local MAX_ENTRIES_PER_MESSAGE = 20
local HEARTBEAT = 45                 -- seconds between state checks while players are online together
local HEARTBEAT_AFTER_TURN = 8       -- seconds after my turn: did it arrive?

Guild.online = {}                    -- [name key] = true while online

local function Games() return Yatzy.Games end
local function Play() return Yatzy.Play end

---------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------

-- WoW: Forever quirks seen in game:
--  * characters have a surname: the guild roster says "Father Ghouliath", while the
--    game's own name for the character (UnitName, chat senders) is just "Father";
--  * each client writes the realm differently ("...EU4..." vs "...EU5...").
-- So players are identified by their FIRST name (unique on the realm), lower case.
-- Messages go over the guild channel, so we never need a name WoW can whisper to.

local function myRealm()
    if Guild.realm then return Guild.realm end              -- as written in the guild roster
    if GetNormalizedRealmName then
        local r = GetNormalizedRealmName()
        if r and r ~= "" then return r end
    end
    return ((GetRealmName and GetRealmName()) or ""):gsub("[%s%-]", "")
end

local function realmOf(name)
    return name and name:match("%-(.+)$")
end

-- "Name-Realm" for any name (adds my realm when it's missing)
function Guild:FullName(name)
    if not name or name == "" then return nil end
    if name:find("-", 1, true) then return name end
    return name .. "-" .. myRealm()
end

function Guild:MyName()
    return self.myFull or self:FullName(UnitName("player"))
end

-- Name for display: without the realm (keeps the surname, e.g. "Father Ghouliath")
function Guild:Short(name)
    if not name then return "?" end
    return name:match("^([^%-]+)") or name
end

-- What players see: the first name only ("Gulki Warr-Realm" -> "Gulki").
-- (Short is still used for matching and messages, so it keeps the surname.)
function Guild:FirstName(name)
    local short = self:Short(name)
    return short:match("^(%S+)") or short
end

-- Identity key: first name only, lower case ("Father Ghouliath-Realm" -> "father")
local function key(name)
    if not name then return "" end
    local short = Guild:Short(name)
    return (short:match("^(%S+)") or short):lower()
end
Guild.Key = function(_, name) return key(name) end

-- Same character? (ignores realm spelling and surnames)
function Guild:SameName(a, b)
    if not a or not b then return false end
    if a == b then return true end
    return key(a) == key(b)
end

-- Best display name for a player: the guild roster's (with surname) if known
function Guild:DisplayName(name)
    local fromRoster = self.rosterNames and self.rosterNames[key(name)]
    return self:Short(fromRoster or name)
end

---------------------------------------------------------------------------
-- Guild roster: who is online
---------------------------------------------------------------------------

function Guild:InGuild()
    return IsInGuild and IsInGuild() or false
end

function Guild:RequestRoster()
    if not self:InGuild() then return end
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
end

-- Guild members except me: { {name=, online=, level=, class=}, ... } online first
function Guild:Members()
    local list = {}
    if not self:InGuild() or not GetNumGuildMembers then return list end
    local myKey = key(UnitName("player"))
    self.rosterNames = self.rosterNames or {}
    for i = 1, GetNumGuildMembers() do
        local name, _, _, level, class, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if name and classFile then
            self.rosterClass = self.rosterClass or {}
            self.rosterClass[key(name)] = classFile          -- "MAGE", ... (for the class icon)
        end
        if name and key(name) == myKey then
            -- My own row: learn how this roster writes my name and realm
            self.myFull = self:FullName(name)
            self.realm = realmOf(self.myFull) or self.realm
        elseif name then
            local full = self:FullName(name)
            self.rosterNames[key(full)] = full
            list[#list + 1] = { name = full, online = online and true or false, level = level, class = class }
        end
    end
    table.sort(list, function(a, b)
        if a.online ~= b.online then return a.online end
        return a.name < b.name
    end)
    return list
end

-- A guild member's class ("MAGE", "WARRIOR", ...), from the roster; nil if unknown
function Guild:ClassOf(name)
    return name and self.rosterClass and self.rosterClass[key(name)]
end

function Guild:OnRosterUpdate()
    local was = self.online
    local nowOnline = {}
    local names = {}
    for _, m in ipairs(self:Members()) do
        if m.online then
            nowOnline[key(m.name)] = true
            names[key(m.name)] = m.name
        end
    end
    self.online = nowOnline
    -- Someone who just came online: compare notes about the games we share
    for k in pairs(nowOnline) do
        if not was[k] then self:SyncWith(names[k]) end
    end
    if not self.loginSummaryDone then
        self.loginSummaryDone = true
        C_Timer.After(6, function()
            Guild:CloseExpired()
            Guild:LoginSummary()
        end)
    end
end

function Guild:IsOnline(name)
    return name and self.online[key(name)] == true
end

-- Any message from someone means they're online right now.
function Guild:SawOnline(name)
    if name then self.online[key(name)] = true end
end

---------------------------------------------------------------------------
-- Who has Yatzy? Presence messages ("P") with the addon version.
-- Remembered between sessions in YatzyDB.players[key] = { name, version, seen }.
---------------------------------------------------------------------------

local lastPresenceReply = -100

function Guild:Players()
    Yatzy.db.players = Yatzy.db.players or {}
    return Yatzy.db.players
end

-- Ask the guild who has the addon (everyone with it answers with their version).
function Guild:AskWhoHasYatzy()
    Yatzy.Comm:Send("*", "P", Yatzy.version, "1")
end

function Guild:OnPresence(f, sender)
    local version, ask = f[1], f[2]
    local p = self:Players()
    p[key(sender)] = { name = sender, version = version, seen = time() }
    -- Answer an "ask", once in a while and after a small random wait, so a guild full of
    -- Yatzy players doesn't answer all at the same moment.
    local t = GetTime and GetTime() or 0
    if ask == "1" and t - lastPresenceReply > 20 then
        lastPresenceReply = t
        C_Timer.After(0.5 + math.random() * 2.5, function()
            Yatzy.Comm:Send("*", "P", Yatzy.version, "0")
        end)
    end
    if Yatzy.InviteDialog and Yatzy.InviteDialog.cover and Yatzy.InviteDialog.cover:IsShown() then
        Yatzy.InviteDialog:Refresh()
    end
end

-- What we know about this player's addon: version string or nil
function Guild:VersionOf(name)
    local p = self:Players()[key(name)]
    return p and p.version
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

function Guild:Init()
    local Comm = Yatzy.Comm
    Comm:Init()
    Comm:On("P", function(f, sender) Guild:OnPresence(f, sender) end)
    Comm:On("S", function(f, sender, toMe, isAll) Guild:OnState(f, sender, toMe, nil, isAll) end)
    Comm:On("T", function(f, sender, toMe) Guild:OnTurns(f, sender, toMe) end)
    Comm:On("MQ", function(f, sender) Yatzy.Mail:OnQuery(f, sender) end)
    Comm:On("R", function(f, sender) Guild:OnLiveRoll(f, sender) end)
    Comm:On("H", function(f, sender) Guild:OnLiveHolds(f, sender) end)
    Comm:On("BS", function(f, sender, toMe, isAll) Guild:OnState(f, sender, toMe, "backgammon", isAll) end)
    Comm:On("BT", function(f, sender, toMe) Guild:OnTurns(f, sender, toMe, "backgammon") end)
    Comm:On("BM", function(f, sender) Guild:OnBGLive(f, sender) end)
    Comm:On("BA", function(f, sender) Guild:OnBGAuto(f, sender) end)
    if Yatzy.Fast then Yatzy.Fast:Init() end         -- poke messages and the 1-second turn clock

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("GUILD_ROSTER_UPDATE")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(_, event)
        if event == "GUILD_ROSTER_UPDATE" then
            Guild:OnRosterUpdate()
        else
            Guild:RequestRoster()
            if not Guild.askedAtLogin then
                Guild.askedAtLogin = true
                C_Timer.After(5, function() Guild:AskWhoHasYatzy() end)
                C_Timer.After(12, function() Yatzy.Mail:Ask() end)      -- anything waiting for me in a mailbox?
            else
                -- a loading screen (into or out of an instance): messages may have been missed
                C_Timer.After(8, function() Guild:Heartbeat(true) end)
            end
        end
    end)
    if C_Timer.NewTicker then
        C_Timer.NewTicker(ROSTER_INTERVAL, function()
            Guild:RequestRoster()
            Guild:CloseExpired()
        end)
        C_Timer.NewTicker(HEARTBEAT, function() Guild:Heartbeat() end)
    end
end

---------------------------------------------------------------------------
-- Game records
-- g.kind = "guild", g.creator, g.invited = { full names }, g.answers = "Y?N", g.left = "NNN"
-- g.status: "pending" (waiting for answers) -> "active" -> "over"; or "cancelled"
-- g.hidden = true when I declined or left (kept so the news still reaches the others)
---------------------------------------------------------------------------

local function charAt(s, i) return s:sub(i, i) end
local function setChar(s, i, c) return s:sub(1, i - 1) .. c .. s:sub(i + 1) end

function Guild:InviteIndex(g, name)
    for i, n in ipairs(g.invited) do if self:SameName(n, name) then return i end end
end

-- Seat number (turn order) -> index in g.invited
function Guild:InvitedIndexOfSeat(g, seat)
    return g.seatInvite and g.seatInvite[seat]
end

function Guild:HasLeft(g, seat)
    local idx = self:InvitedIndexOfSeat(g, seat)
    return idx and charAt(g.left, idx) == "Y"
end

function Guild:MyAnswer(g)
    local idx = self:InviteIndex(g, self:MyName())
    return idx and charAt(g.answers, idx)
end

function Guild:TurnsDone(g)
    if g.status == "active" or g.status == "over" then
        if isBG(g) then return BG.TurnsDone(g) end
        return g.turn - 1
    end
    return 0
end

-- Games created since 0.10 have ids starting with "r": their turn order is random.
-- Older games (still waiting for answers when someone updated) keep the invitation order,
-- so a copy on an old version and one on the new version never disagree about it.
local function newId()
    return ("r%d%04d"):format(time(), math.random(0, 9999))
end

-- The same "random" order on every player's copy: a small number generator started from
-- the game's id, so nobody has to send the order around.
local function shuffleFor(id, list, paired)
    local seed = (tonumber((tostring(id):gsub("%D", ""):sub(-12))) or 1) % 2147483647
    if seed == 0 then seed = 1 end
    for i = #list, 2, -1 do
        seed = (seed * 48271) % 2147483647
        local j = seed % i + 1
        list[i], list[j] = list[j], list[i]
        paired[i], paired[j] = paired[j], paired[i]
    end
end
Guild.ShuffleFor = shuffleFor

-- Start the game once everyone has answered. The turn order (and so who starts) is
-- random, but the same on every copy (see shuffleFor).
local function activate(self, g)
    local players, seatInvite = {}, {}
    for i, name in ipairs(g.invited) do
        if charAt(g.answers, i) == "Y" and charAt(g.left, i) ~= "Y" then   -- withdrew before the start = not playing
            players[#players + 1] = name
            seatInvite[#players] = i
        end
    end
    if #players < 2 then
        g.status = "cancelled"
        return
    end
    if tostring(g.id):sub(1, 1) == "r" then Guild.ShuffleFor(g.id, players, seatInvite) end
    if isBG(g) then
        if #players ~= 2 then
            g.status = "cancelled"
            return
        end
        -- the opening roll comes from the game id: the same on every copy
        local bg = BG.NewGame(players, BG.RngFromId(g.id))
        g.players, g.board, g.turn, g.first = bg.players, bg.board, bg.turn, bg.first
        g.opening, g.dice, g.moves, g.history = bg.opening, bg.dice, bg.moves, bg.history
    else
        local rg = Rules.NewGame(players)
        g.players, g.sheets, g.turn = rg.players, rg.sheets, rg.turn
        g.rollsUsed, g.dice, g.held = rg.rollsUsed, rg.dice, rg.held
        g.history = {}
    end
    g.status = "active"
    g.seatInvite = seatInvite
    local me = self:MyName()
    for seat, name in ipairs(players) do
        if self:SameName(name, me) then g.me = seat end
    end
end

-- Move the game forward as far as the known information allows:
-- start it, apply buffered turns in order, skip the turns of players who left.
-- Returns true if anything changed.
function Guild:Advance(g)
    local changed = false
    if g.status == "pending" and not g.answers:find("?", 1, true) then
        activate(self, g)
        changed = true
    end
    if g.status ~= "active" then return changed end
    g.pendingTurns = g.pendingTurns or {}
    if isBG(g) then return self:AdvanceBG(g, changed) end
    for _ = 1, 200 do
        if g.status ~= "active" then break end
        local seat = Rules.CurrentPlayer(g)
        local entry = g.pendingTurns[g.turn]
        if entry then
            g.pendingTurns[g.turn] = nil
            local ok
            if entry.dice == "00000" then
                ok = Rules.SkipTurn(g)
            else
                ok = Rules.ApplyTurn(g, g.turn, entry.cat, Rules.DiceFromString(entry.dice), entry.points)
            end
            if ok then changed = true end
        elseif self:HasLeft(g, seat) then
            Rules.SkipTurn(g)
            changed = true
        else
            break
        end
    end
    -- forget buffered turns we've passed
    for n in pairs(g.pendingTurns) do
        if n < g.turn then g.pendingTurns[n] = nil end
    end
    if Yatzy.Fast then Yatzy.Fast:Note(g) end      -- fast games: start the clock for the new turn
    return changed
end

-- Backgammon: apply buffered turns in order (each is checked against the rules);
-- a player who left has given up, so the other one wins.
function Guild:AdvanceBG(g, changed)
    for _ = 1, 400 do
        if g.status ~= "active" then break end
        local entry = g.pendingTurns[g.turn]
        if not entry then break end
        g.pendingTurns[g.turn] = nil
        if BG.ApplyTurn(g, g.turn, entry.dice, entry.moves) then changed = true end
    end
    if g.status == "active" then
        for seat = 1, 2 do
            if self:HasLeft(g, seat) then
                BG.Resign(g, seat)
                changed = true
                break
            end
        end
    end
    for n in pairs(g.pendingTurns) do
        if n < g.turn then g.pendingTurns[n] = nil end
    end
    if Yatzy.Fast then Yatzy.Fast:Note(g) end
    return changed
end

---------------------------------------------------------------------------
-- Encoding
---------------------------------------------------------------------------

local function catLetter(id)
    for i, cat in ipairs(Rules.CATEGORIES) do
        if cat.id == id then return string.char(96 + i) end
    end
end
local function catFromLetter(letter)
    local cat = Rules.CATEGORIES[letter:byte() - 96]
    return cat and cat.id
end

-- Names go without realm ("Gulki Warr", not "Gulki Warr-CAMWOWEU4Realm6PvP"): players are
-- matched by first name anyway, and six full names wouldn't fit in one message (250 chars).
function Guild:StateMessage(g)
    local names = {}
    for i, n in ipairs(g.invited) do names[i] = self:Short(n) end
    local fields = { g.id, self:Short(g.creator), table.concat(names, ","), g.answers, g.left, tostring(self:TurnsDone(g)),
        g.fast and "F" or "-" }         -- 7th field (0.10): F = fast game
    -- 8th field is for the mailman marker (Mail.lua); 9th (0.12): the finished game this one replays
    if g.replayOf then fields[8] = ""; fields[9] = g.replayOf end
    return unpack(fields)
end

function Guild:SendState(g, to)
    Yatzy.Comm:Send(to, kindFor(g, "S"), self:StateMessage(g))
end

-- Send turns first..last to a player (several per message)
function Guild:SendTurns(g, to, first, last)
    local n = first
    while n <= last do
        local entries = {}
        local start = n
        local length = 0
        while n <= last and #entries < MAX_ENTRIES_PER_MESSAGE do
            local h = g.history and g.history[n]
            if not h then break end
            local entry
            if isBG(g) then
                entry = h.dice .. h.moves
            else
                entry = catLetter(h.cat) .. h.dice .. h.points
            end
            if #entries > 0 and length + #entry + 1 > 190 then break end    -- one message holds 255 characters
            entries[#entries + 1] = entry
            length = length + #entry + 1
            n = n + 1
        end
        if #entries == 0 then return end
        Yatzy.Comm:Send(to, kindFor(g, "T"), g.id, tostring(start), table.concat(entries, ";"))
    end
end

-- The other players of a game (full names), optionally only those online
function Guild:Others(g, onlineOnly)
    local me, list = self:MyName(), {}
    for i, name in ipairs(g.invited) do
        local a = charAt(g.answers, i)
        if not self:SameName(name, me) and a ~= "N" and a ~= "X" and (not onlineOnly or self:IsOnline(name)) then
            list[#list + 1] = name
        end
    end
    return list
end

-- Tell everyone online what I know about this game (one guild-channel message).
function Guild:Broadcast(g)
    self:SendState(g, "*")
end

---------------------------------------------------------------------------
-- Syncing
---------------------------------------------------------------------------

local function stillSyncing(g)
    if g.kind ~= "guild" then return false end
    if g.status == "active" or g.status == "pending" then return true end
    return (time() - (g.lastActivity or 0)) < KEEP_FINISHED_SYNC
end

-- Someone came online: send them the state of every game we share.
function Guild:SyncWith(name)
    for _, g in ipairs(Games():All()) do
        if stillSyncing(g) and self:InviteIndex(g, name) then
            self:SendState(g, name)
        end
    end
end

-- Merge their answers/left flags into mine. Returns changed, theyLackSomething.
local function mergeFlags(mine, theirs, unknown)
    local changed, theyLack = false, false
    for i = 1, #mine do
        local a, b = charAt(mine, i), charAt(theirs, i)
        if a == unknown and b ~= unknown and b ~= "" then
            mine = setChar(mine, i, b); changed = true
        elseif b == unknown and a ~= unknown then
            theyLack = true
        end
    end
    return mine, changed, theyLack
end

function Guild:OnState(f, sender, toMe, game, isAll)
    local id, creator, invitedStr, answers, left, theirTurns = f[1], f[2], f[3], f[4], f[5], tonumber(f[6]) or 0
    if not id or not invitedStr or not answers or not left then return end
    local invited = {}
    for name in invitedStr:gmatch("[^,]+") do invited[#invited + 1] = name end
    local maxPlayers = game == "backgammon" and 2 or Rules.MAX_PLAYERS
    if #invited < 2 or #invited > maxPlayers or #answers ~= #invited or #left ~= #invited then return end
    local me = self:MyName()
    local g = Games():Get(id)
    local isNew = false
    if g and g.game ~= game then return end              -- (never happens: ids are unique)

    if not g then
        if Games():WasRemoved(id) then return end      -- I removed it: don't bring it back
        -- A game I'm invited to that I haven't heard of yet
        local myIdx
        for i, n in ipairs(invited) do if self:SameName(n, me) then myIdx = i end end
        if not myIdx then
            Yatzy.Mail:HearState(f, sender, toMe, isAll, game)   -- not my game: maybe keep it for the players
            return
        end
        -- from a player of the game, or from a mailman holding it for them (marker "M")
        if f[8] ~= "M" and not self:InviteIndex({ invited = invited }, sender) then return end
        -- A replay of a game I have: the first one started wins (ids start with the time).
        -- A second one for the same game is ignored, or, if it is the earlier one, takes over.
        local replayOf = (f[9] and f[9] ~= "") and f[9] or nil
        local old = replayOf and Games():Get(replayOf)
        local rival = old and old.replayed and old.replayed ~= id and Games():Get(old.replayed)
        if rival and (rival.hidden or rival.status == "cancelled") then rival = nil end
        if rival and rival.id < id then return end
        g = {
            id = id, kind = "guild", creator = creator, invited = invited,
            answers = answers, left = left, status = "pending",
            created = time(), lastActivity = time(), pendingTurns = {}, game = game,
        }
        g.replayOf = replayOf
        table.insert(Games():All(), 1, g)
        isNew = true
        if old then
            old.replayed = id
            if rival then                          -- mine started later: it gives way to this one
                if self:IsCreator(rival) then self:Leave(rival)
                elseif Games():IsInvite(rival) then self:Answer(rival, false)
                else rival.hidden = true end
            end
        end
    end
    if f[8] ~= "M" and not self:InviteIndex(g, sender) then return end
    if f[7] == "F" then g.fast = true end            -- fast game (only ever set, never unset)

    local oldAnswers, oldLeft, oldStatus = g.answers, g.left, g.status
    -- The creator's "X" (started without them) wins over anything else
    local closedChange, theyLackX = false, false
    for i = 1, #g.answers do
        local a, b = charAt(g.answers, i), charAt(answers, i)
        if b == "X" and a ~= "X" then
            g.answers = setChar(g.answers, i, "X"); closedChange = true
        elseif a == "X" and b ~= "X" then
            theyLackX = true
        end
    end
    local changedA, changedL, lackA, lackL
    g.answers, changedA, lackA = mergeFlags(g.answers, answers, "?")
    lackA = lackA or theyLackX
    g.left, changedL, lackL = mergeFlags(g.left, left, "N")
    -- The game may already have started here with someone the creator left out (they
    -- accepted at the same moment the creator pressed Start now): start it again with
    -- the creator's list, as long as nobody has played a turn yet.
    if closedChange and g.status == "active" and g.turn == 1 and (g.rollsUsed or 0) == 0
        and #(g.history or {}) == 0 then
        g.status, g.players, g.sheets, g.seatInvite, g.me = "pending", nil, nil, nil, nil
        g.board, g.moves = nil, nil
    end
    local changed = isNew or changedA or changedL or closedChange
    if self:Advance(g) then changed = true end
    -- I was left out (didn't answer in time): the game goes on without me
    local myIdx = self:InviteIndex(g, me)
    if myIdx and charAt(g.answers, myIdx) == "X" and not g.hidden then
        g.hidden = true
        if not isNew then
            Yatzy:Print(("%s started the game without you (you hadn't answered)."):format(self:DisplayName(g.creator)))
        end
    end

    -- Answer only messages meant for me (everyone else online heard the same message)
    if toMe then
        local myTurns = self:TurnsDone(g)
        if myTurns > theirTurns then
            self:SendTurns(g, sender, theirTurns + 1, myTurns)
        end
        -- Reply only if they lack something I know, or I need their turns (no endless ping-pong)
        if lackA or lackL or myTurns < theirTurns then
            self:SendState(g, sender)
        end
    end

    if changed then
        Games():Touch(g)
        if isNew and self:MyAnswer(g) == "?" then self:NotifyInvite(g) end
        if not isNew then self:ReportChanges(g, oldAnswers, oldLeft, oldStatus) end
        Play():OnRemoteChange(g)
    end
end

-- Tell me in chat what the OTHER players did with a game I'm in: accepted, declined,
-- withdrew, left; and whether the game started or was cancelled because of it.
-- (My own actions aren't reported: I just did them.)
function Guild:ReportChanges(g, oldAnswers, oldLeft, oldStatus)
    local me = self:MyName()
    local myIdx = self:InviteIndex(g, me)
    if not myIdx or charAt(g.left, myIdx) == "Y" or charAt(g.answers, myIdx) == "N" or charAt(g.answers, myIdx) == "X" then return end
    local title = Yatzy.UI and Yatzy.UI.RowTitle and Yatzy.UI:RowTitle(g) or "Yatzy"
    local lines = {}
    for i, name in ipairs(g.invited) do
        if i ~= myIdx then
            local who = self:DisplayName(name)
            local a0, a1 = charAt(oldAnswers, i), charAt(g.answers, i)
            local l0, l1 = charAt(oldLeft, i), charAt(g.left, i)
            if a0 == "?" and a1 == "Y" then
                lines[#lines + 1] = who .. " accepted."
            elseif a0 == "?" and a1 == "N" then
                lines[#lines + 1] = who .. " declined."
            elseif a0 ~= "X" and a1 == "X" then
                lines[#lines + 1] = who .. " didn't answer in time and isn't playing."
            end
            if l0 ~= "Y" and l1 == "Y" then
                if oldStatus == "pending" then
                    lines[#lines + 1] = who .. " withdrew from the game."
                elseif isBG(g) then
                    lines[#lines + 1] = who .. " gave up: you win!"
                else
                    lines[#lines + 1] = who .. " left the game; their turns are skipped."
                end
            end
        end
    end
    if oldStatus == "active" and g.status == "active" and g.turn == 1 and oldAnswers ~= g.answers then
        local names = {}
        for seat = 1, #g.players do names[#names + 1] = Games():PlayerName(g, seat) end
        lines[#lines + 1] = "The players are: " .. table.concat(names, ", ") .. "."
    elseif oldStatus == "pending" and g.status == "active" then
        local names = {}
        for seat = 1, #g.players do names[#names + 1] = Games():PlayerName(g, seat) end
        lines[#lines + 1] = "The game has started: " .. table.concat(names, ", ") .. "."
    elseif oldStatus ~= "cancelled" and g.status == "cancelled" then
        lines[#lines + 1] = "The game is cancelled: not enough players accepted."
    elseif g.status == "pending" then
        local waiting = {}
        for i, name in ipairs(g.invited) do
            if charAt(g.answers, i) == "?" then waiting[#waiting + 1] = self:DisplayName(name) end
        end
        if #lines > 0 and #waiting > 0 then lines[#lines + 1] = "Still waiting for " .. table.concat(waiting, ", ") .. "." end
    end
    if #lines > 0 then
        Yatzy:Print("[" .. title .. "] " .. table.concat(lines, " "))
    end
end

function Guild:OnTurns(f, sender, toMe, game)
    local g = Games():Get(f[1])
    local first = tonumber(f[2])
    if not g then Yatzy.Mail:HearTurns(f, sender, toMe, game); return end     -- not my game
    if g.kind ~= "guild" or not first or not f[3] then return end
    if f[4] ~= "M" and not self:InviteIndex(g, sender) then return end        -- a player, or a mailman ("M")
    if g.game ~= game then return end
    g.pendingTurns = g.pendingTurns or {}
    if isBG(g) then
        local n = first
        for entry in (f[3] .. ";"):gmatch("([^;]*);") do
            local dice, moves = entry:match("^([1-6][1-6])(%l*)$")
            if dice and n >= (g.status == "active" and g.turn or 1) then
                g.pendingTurns[n] = { dice = dice, moves = moves }
            end
            n = n + 1
        end
        if self:Advance(g) then
            Games():Touch(g)
            Play():OnRemoteChange(g)
        end
        return
    end
    local n = first
    local fresh = {}            -- turns we didn't have yet, to look for a Yatzy we missed live
    local count = 0
    for entry in f[3]:gmatch("[^;]+") do
        local letter, dice, points = entry:match("^(%a)(%d%d%d%d%d)(%d+)$")
        local cat = letter and catFromLetter(letter)
        if cat and n >= (g.status == "active" and g.turn or 1) then
            g.pendingTurns[n] = { cat = cat, dice = dice, points = tonumber(points) }
            fresh[#fresh + 1] = { turn = n, dice = dice }
        end
        count = count + 1
        n = n + 1
    end
    if self:Advance(g) then
        Games():Touch(g)
        -- A turn with five of a kind that just arrived (not a big catch-up after logging in)
        if count <= 2 then
            for _, t in ipairs(fresh) do
                local d = t.dice ~= "00000" and Rules.IsValidDice(Rules.DiceFromString(t.dice)) and Rules.DiceFromString(t.dice)
                if d and Rules.IsYatzy(d) and t.turn < g.turn then
                    Play():CelebrateYatzy(g, Rules.PlayerForTurn(g, t.turn), t.turn)
                end
            end
        end
        Play():OnRemoteChange(g)
    end
end

function Guild:OnLiveRoll(f, sender)
    local g = Games():Get(f[1])
    if not g or g.status ~= "active" then return end
    local turn, roll, dice, mask = tonumber(f[2]), tonumber(f[3]), Rules.DiceFromString(f[4]), f[5]
    if turn ~= g.turn or not dice or not roll or not mask or #mask ~= Rules.NUM_DICE then return end
    local seat = Rules.CurrentPlayer(g)
    if not self:SameName(g.players[seat], sender) or seat == g.me then return end
    local held = {}
    for i = 1, Rules.NUM_DICE do held[i] = mask:sub(i, i) == "1" end
    Play():OnRemoteRoll(g, dice, held, roll)
end

-- The player whose turn it is saved or put back dice (live view only).
function Guild:OnLiveHolds(f, sender)
    local g = Games():Get(f[1])
    if not g or g.status ~= "active" then return end
    local turn, roll, mask = tonumber(f[2]), tonumber(f[3]), f[4]
    if turn ~= g.turn or roll ~= g.rollsUsed or not mask or #mask ~= Rules.NUM_DICE then return end
    local seat = Rules.CurrentPlayer(g)
    if not self:SameName(g.players[seat], sender) or seat == g.me then return end
    local held = {}
    for i = 1, Rules.NUM_DICE do held[i] = mask:sub(i, i) == "1" end
    Play():OnRemoteHolds(g, held)
end

---------------------------------------------------------------------------
-- My actions
---------------------------------------------------------------------------

-- Create a game and invite 1-5 guild members (up to 6 players; backgammon: exactly 1).
-- opts.fast = fast game, opts.game = "backgammon" (nil = Yatzy)
function Guild:CreateGame(names, opts)
    local me = self:MyName()
    local invited = { me }
    for _, n in ipairs(names) do invited[#invited + 1] = n end
    local game = opts and opts.game
    if game == "backgammon" and #invited ~= 2 then return nil end
    local g = {
        id = newId(), kind = "guild", creator = me, invited = invited,
        answers = "Y" .. ("?"):rep(#invited - 1), left = ("N"):rep(#invited),
        status = "pending", created = time(), lastActivity = time(), pendingTurns = {},
        fast = (opts and opts.fast) and true or nil, game = game,
        replayOf = opts and opts.replayOf or nil,
    }
    table.insert(Games():All(), 1, g)
    local old = g.replayOf and Games():Get(g.replayOf)
    if old then old.replayed = g.id end
    self:Broadcast(g)
    return g
end

function Guild:Answer(g, accept)
    local idx = self:InviteIndex(g, self:MyName())
    if not idx or charAt(g.answers, idx) ~= "?" then return end
    g.answers = setChar(g.answers, idx, accept and "Y" or "N")
    if not accept then g.hidden = true end
    self:Advance(g)
    Games():Touch(g)
    self:Broadcast(g)
end

-- Leave a running game: my remaining turns are struck out, the others play on.
function Guild:Leave(g)
    local idx = self:InviteIndex(g, self:MyName())
    if not idx then return end
    g.left = setChar(g.left, idx, "Y")
    g.hidden = true
    self:Advance(g)
    Games():Touch(g)
    self:Broadcast(g)
end

---------------------------------------------------------------------------
-- Starting before everyone has answered (creator only)
---------------------------------------------------------------------------

local INVITE_DAYS = 7               -- unanswered invitations run out after this

function Guild:IsCreator(g)
    return g.creator and self:SameName(g.creator, self:MyName()) or false
end

-- Can I start this game now, with whoever has accepted so far?
function Guild:CanStartNow(g)
    if g.kind ~= "guild" or g.status ~= "pending" or not self:IsCreator(g) then return false end
    local myIdx = self:InviteIndex(g, self:MyName())
    if not myIdx or charAt(g.left, myIdx) == "Y" then return false end
    local accepted = false
    for i = 1, #g.answers do
        if i ~= myIdx and charAt(g.answers, i) == "Y" and charAt(g.left, i) ~= "Y" then accepted = true end
    end
    return accepted and g.answers:find("?", 1, true) ~= nil
end

-- Who would play if I started now (display names, me = "You")
function Guild:StartNowPlayers(g)
    local me, names, missing = self:MyName(), {}, {}
    for i, name in ipairs(g.invited) do
        local a = charAt(g.answers, i)
        if a == "Y" and charAt(g.left, i) ~= "Y" then
            names[#names + 1] = self:SameName(name, me) and "You" or self:DisplayName(name)
        elseif a == "?" then
            missing[#missing + 1] = self:DisplayName(name)
        end
    end
    return names, missing
end

-- Close the invitations: everyone who hasn't answered is out (X), and the game starts
-- with those who accepted (or is cancelled if nobody did). Only the creator does this,
-- so all copies of the game follow the same list.
function Guild:StartNow(g)
    if g.kind ~= "guild" or g.status ~= "pending" or not self:IsCreator(g) then return end
    for i = 1, #g.answers do
        if charAt(g.answers, i) == "?" then g.answers = setChar(g.answers, i, "X") end
    end
    self:Advance(g)
    Games():Touch(g)
    self:Broadcast(g)
    Play():OnRemoteChange(g)
end

-- My invitations that nobody has answered for INVITE_DAYS days: start them now
function Guild:CloseExpired()
    for _, g in ipairs(Games():All()) do
        if g.kind == "guild" and g.status == "pending" and self:IsCreator(g)
            and time() - (g.created or time()) > INVITE_DAYS * 86400 then
            local names, missing = self:StartNowPlayers(g)
            self:StartNow(g)
            if #missing > 0 then
                Yatzy:Print(("Your invitation ran out after %d days. %s didn't answer. %s"):format(INVITE_DAYS,
                    table.concat(missing, ", "),
                    g.status == "active" and ("The game has started: " .. table.concat(names, ", ") .. ".")
                        or "The game is cancelled: nobody accepted."))
            end
        end
    end
end

-- I finished a turn: send it to everyone online right away (the rest get it later).
function Guild:OnLocalTurn(g)
    local n = self:TurnsDone(g)
    self:SendTurns(g, "*", n, n)
    if self:Advance(g) then Play():OnRemoteChange(g) end    -- e.g. skip players who left
    -- Check a moment later that it arrived: if nothing has happened since, tell the others
    -- how far I am (anyone who missed the turn answers, and gets it again).
    C_Timer.After(HEARTBEAT_AFTER_TURN, function()
        if g.status == "active" and self:TurnsDone(g) == n and not Games():IsMyTurn(g) then
            self:SendState(g, "*")
        end
    end)
end

-- Regular state check while players are online together (every HEARTBEAT seconds, after
-- combat and after a loading screen). A turn message can get lost, e.g. in combat inside an
-- instance, where the game holds back or hides addon messages; then one player waits for
-- the other while the other waits for them. For each game where I'm waiting for someone
-- who is online, I say how many turns I have (one short state message). Anyone with more
-- turns sends the missing ones; anyone with fewer answers and gets them. Equal = no answer.
-- `all` = also games where it's my turn (after combat or a loading screen I may be behind).
function Guild:Heartbeat(all)
    local sent = 0
    for _, g in ipairs(Games():All()) do
        if sent >= 4 then break end
        if g.kind == "guild" and g.status == "active" and not g.hidden
            and (all or not Games():IsMyTurn(g)) and #self:Others(g, true) > 0 then
            self:SendState(g, "*")
            sent = sent + 1
        end
    end
    return sent
end

-- I rolled: show it live to the others who are online.
function Guild:SendLiveRoll(g)
    local mask = {}
    for i = 1, Rules.NUM_DICE do mask[i] = g.held[i] and "1" or "0" end
    Yatzy.Comm:Send("*", "R", g.id, tostring(g.turn), tostring(g.rollsUsed), table.concat(g.dice), table.concat(mask))
end

-- I saved or put back dice: show it to the others who are online.
function Guild:SendLiveHolds(g)
    local mask = {}
    for i = 1, Rules.NUM_DICE do mask[i] = g.held[i] and "1" or "0" end
    Yatzy.Comm:Send("*", "H", g.id, tostring(g.turn), tostring(g.rollsUsed), table.concat(mask))
end

-- Backgammon, live: the dice and my moves so far this turn (sent again after each move
-- or undo, a moment later so quick clicks go as one message).
function Guild:SendBGLive(g, now)
    if g.kind ~= "guild" or not g.dice then return end
    local function send()
        if g.status ~= "active" or not g.dice or not Games():IsMyTurn(g) then return end
        Yatzy.Comm:Send("*", "BM", g.id, tostring(g.turn), g.dice[1] .. g.dice[2], BG.EncodeMoves(g.moves or {}))
    end
    self.bgLiveToken = (self.bgLiveToken or 0) + 1
    if now then send(); return end
    local token = self.bgLiveToken
    C_Timer.After(0.3, function() if Guild.bgLiveToken == token then send() end end)
end

-- Backgammon "Auto finish": tell the other player whether I've ticked it
function Guild:SendBGAuto(g)
    if g.kind ~= "guild" or g.status ~= "active" then return end
    Yatzy.Comm:Send("*", "BA", g.id, (g.auto and g.auto[g.me]) and "1" or "0")
end

function Guild:OnBGAuto(f, sender)
    local g = Games():Get(f[1])
    if not g or not isBG(g) or g.status ~= "active" or not g.me then return end
    local seat = 3 - g.me
    if not self:SameName(g.players[seat], sender) then return end
    Yatzy.BGPlay:OnRemoteAuto(g, seat, f[2] == "1")
end

function Guild:OnBGLive(f, sender)
    local g = Games():Get(f[1])
    if not g or not isBG(g) or g.status ~= "active" then return end
    local turn, dice, moves = tonumber(f[2]), f[3], f[4] or ""
    if turn ~= g.turn or not dice or not dice:match("^[1-6][1-6]$") or not moves:match("^%l*$") then return end
    local seat = BG.CurrentPlayer(g)
    if seat == g.me or not self:SameName(g.players[seat], sender) then return end
    Yatzy.BGPlay:OnRemoteLive(g, { tonumber(dice:sub(1, 1)), tonumber(dice:sub(2, 2)) }, moves)
end

---------------------------------------------------------------------------
-- Notices
---------------------------------------------------------------------------

function Guild:NotifyInvite(g)
    local game = isBG(g) and "Backgammon" or "Yatzy"
    local msg = ("%s invited you to a game of %s!"):format(self:DisplayName(g.creator), game)
    Yatzy:Print(msg .. " Open Yatzy to accept or decline.")
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
    end
    Yatzy.Sound:Play("invite")
    if Yatzy.UI and Yatzy.UI.start and Yatzy.UI.start:IsShown() then Yatzy.UI:RefreshStart() end
end

function Guild:LoginSummary()
    -- Only games that are really going on (not removed, left or finished), and not the ones
    -- you were already told about this turn.
    local mine = {}
    for _, g in ipairs(Games():Ongoing()) do
        if Games():IsMyTurn(g) and g.alertedTurn ~= g.turn then
            mine[#mine + 1] = g
            g.alertedTurn = g.turn
        end
    end
    local invites = 0
    for _, g in ipairs(Games():All()) do
        if not g.hidden and g.kind == "guild" and g.status == "pending" and self:MyAnswer(g) == "?" then
            invites = invites + 1
        end
    end
    local function vs(g)
        local others = {}
        for seat = 1, #g.players do
            if seat ~= g.me then others[#others + 1] = Games():PlayerName(g, seat) end
        end
        return "vs " .. table.concat(others, " & ")
    end
    if #mine > 0 then Yatzy.Sound:Play("turn") end     -- once, also for several games
    if #mine == 1 then
        Yatzy:Print("Your turn " .. vs(mine[1]) .. "!")
    elseif #mine > 1 then
        local list = {}
        for _, g in ipairs(mine) do list[#list + 1] = vs(g) end
        Yatzy:Print(("Your turn in %d games: %s."):format(#mine, table.concat(list, ", ")))
    end
    if invites > 0 then Yatzy:Print(("You have %d game invitation%s."):format(invites, invites > 1 and "s" or "")) end
end
