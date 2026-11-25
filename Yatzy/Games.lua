-- Games.lua
-- The list of saved games (kept in YatzyDB.games, so games survive /reload and logout).
-- In M2 only games vs the computer exist; guild games are added in M4-M5.

local _, Yatzy = ...
local Rules = Yatzy.Rules
local Games = {}
Yatzy.Games = Games

local MAX_ACTIVE = 10      -- active games per player
local MAX_FINISHED = 10    -- finished games kept in the list

local function list()
    return Yatzy.charDB.games
end

function Games:All()
    return list()
end

function Games:Get(id)
    for _, g in ipairs(list()) do
        if g.id == id then return g end
    end
end

function Games:CountActive()
    local n = 0
    for _, g in ipairs(list()) do
        if (g.status == "active" or g.status == "pending") and not g.hidden then n = n + 1 end
    end
    return n
end

function Games:CanCreate()
    return self:CountActive() < MAX_ACTIVE
end

-- Shown in the addon (not only in chat) when the list is full
function Games:FullText()
    return ("You already have %d games going (the most you can have). Finish one, or remove one from the list, to start a new game."):format(MAX_ACTIVE)
end

function Games:IsBackgammon(g)
    return g.game == "backgammon"
end

-- Seat whose turn it is (each game type has its own turn order)
function Games:CurrentSeat(g)
    if g.game == "backgammon" then return Yatzy.BG.CurrentPlayer(g) end
    return Rules.CurrentPlayer(g)
end

-- Is it the local player's turn / the computer's turn in this game?
function Games:IsMyTurn(g)
    return g.status == "active" and self:CurrentSeat(g) == g.me
end

function Games:IsComputerTurn(g)
    return g.status == "active" and g.computer and self:CurrentSeat(g) == g.computer
end

function Games:PlayerName(g, seat, short)
    if seat == g.me then return "You" end
    local name = g.players[seat]
    -- Full name ("Gulki Warr") everywhere; `short` = first name only (score sheet columns)
    if g.kind == "guild" then
        return short and Yatzy.Guild:FirstName(name) or Yatzy.Guild:DisplayName(name)
    end
    return name
end

-- A guild invitation I haven't answered yet
function Games:IsInvite(g)
    return g.kind == "guild" and g.status == "pending" and Yatzy.Guild:MyAnswer(g) == "?"
end

local function trimFinished()
    local finished = {}
    for i, g in ipairs(list()) do
        if g.status == "over" or g.status == "cancelled" then finished[#finished + 1] = i end
    end
    -- The list is newest-first, so drop finished games from the end.
    for k = #finished, MAX_FINISHED + 1, -1 do
        table.remove(list(), finished[k])
    end
end

function Games:NewVsComputer()
    if not self:CanCreate() then return nil end
    local myName = UnitName("player") or "You"
    -- who starts is random (coin toss)
    local meFirst = math.random(1, 2) == 1
    local g = Rules.NewGame(meFirst and { myName, "Computer" } or { "Computer", myName })
    g.id = tostring(time()) .. "-" .. math.random(1000, 9999)
    g.kind = "computer"
    g.me = meFirst and 1 or 2
    g.computer = meFirst and 2 or 1
    g.created = time()
    g.lastActivity = time()
    table.insert(list(), 1, g)
    trimFinished()
    return g
end

-- Backgammon vs the computer. You always sit in seat 1; the opening roll decides who starts.
function Games:NewBGVsComputer()
    if not self:CanCreate() then return nil end
    local g = Yatzy.BG.NewGame({ UnitName("player") or "You", "Computer" })
    g.id = tostring(time()) .. "-" .. math.random(1000, 9999)
    g.kind = "computer"
    g.me = 1
    g.computer = 2
    g.created = time()
    g.lastActivity = time()
    table.insert(list(), 1, g)
    trimFinished()
    return g
end

---------------------------------------------------------------------------
-- Replay: a new round with the same players (the Replay button on the game-over panels)
---------------------------------------------------------------------------

-- The replay already started for this game, if it is still alive (not declined away or cancelled).
-- Whoever presses Replay first starts it; everybody else's button then just goes to that game.
function Games:ReplayTarget(g)
    local r = g.replayed and self:Get(g.replayed)
    if r and not r.hidden and r.status ~= "cancelled" then return r end
end

-- Who gets an invitation: everyone who accepted and played the game to the end. (In backgammon
-- the opponent always counts, also if they gave up.)
function Games:ReplayNames(g)
    local Guild = Yatzy.Guild
    local me, names = Guild:MyName(), {}
    for i, name in ipairs(g.invited or {}) do
        local answer, left = g.answers:sub(i, i), g.left:sub(i, i)
        local played = answer == "Y" and (g.game == "backgammon" or left ~= "Y")
        if played and not Guild:SameName(name, me) then names[#names + 1] = name end
    end
    return names
end

-- My oldest game that still counts toward the limit
function Games:Oldest()
    local oldest
    for _, g in ipairs(list()) do
        if (g.status == "active" or g.status == "pending") and not g.hidden then
            if not oldest or (g.created or 0) < (oldest.created or 0) then oldest = g end
        end
    end
    return oldest
end

-- Make room for one more game: the oldest game goes (left, declined or deleted, like the bin icon)
function Games:DropOldest()
    local g = self:Oldest()
    if not g then return end
    local Guild = Yatzy.Guild
    if self:IsInvite(g) then Guild:Answer(g, false)
    elseif g.kind == "guild" then Guild:Leave(g)
    else self:Remove(g.id) end
end

-- Start the replay. Returns the game and "new" or "existing"; nil and "nobody" when there is
-- nobody to invite. A full list loses its oldest game first.
function Games:Replay(g)
    local existing = self:ReplayTarget(g)
    if existing then return existing, "existing" end
    if not self:CanCreate() then self:DropOldest() end
    local new
    if g.kind == "computer" then
        new = (g.game == "backgammon") and self:NewBGVsComputer() or self:NewVsComputer()
        if new then new.replayOf = g.id end
    else
        local names = self:ReplayNames(g)
        if #names == 0 then return nil, "nobody" end
        new = Yatzy.Guild:CreateGame(names, { fast = g.fast, game = g.game, replayOf = g.id })
    end
    if new then g.replayed = new.id end
    return new, "new"
end

function Games:Touch(g)
    g.lastActivity = time()
end

function Games:Remove(id)
    for i, g in ipairs(list()) do
        if g.id == id then
            table.remove(list(), i)
            local BGPlay = Yatzy.BGPlay
            if BGPlay and BGPlay.game == g then BGPlay:Close() end    -- it was open in its window
            -- Remember removed guild games: other players still have them and would
            -- otherwise send them back the next time we're online together.
            if g.kind == "guild" then self:Forget(id) end
            return true
        end
    end
end

local FORGET_DAYS = 90
function Games:Forget(id)
    local removed = Yatzy.charDB.removed or {}
    Yatzy.charDB.removed = removed
    removed[id] = time()
    for k, t in pairs(removed) do                      -- tidy up very old entries
        if time() - t > FORGET_DAYS * 86400 then removed[k] = nil end
    end
end

function Games:WasRemoved(id)
    return Yatzy.charDB.removed ~= nil and Yatzy.charDB.removed[id] ~= nil
end

-- Games that are really going on for me: running, not removed or left
function Games:Ongoing()
    local result = {}
    for _, g in ipairs(list()) do
        if g.status == "active" and not g.hidden then result[#result + 1] = g end
    end
    return result
end

-- Sorted for the games list: your turn first, then waiting, then finished; newest first within each.
function Games:Sorted()
    local sorted = {}
    for _, g in ipairs(list()) do
        if not g.hidden then sorted[#sorted + 1] = g end
    end
    local function rank(g)
        if self:IsInvite(g) then return 0 end
        if g.status == "pending" then return 2 end
        if g.status ~= "active" then return 3 end
        if self:IsMyTurn(g) then return 1 end
        return 2
    end
    table.sort(sorted, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        return (a.lastActivity or 0) > (b.lastActivity or 0)
    end)
    return sorted
end

-- Short text for the games list, e.g. "Round 3/15", "Computer's turn", "You won (231)".
function Games:Describe(g)
    local Guild = Yatzy.Guild
    if g.status == "pending" then
        if self:IsInvite(g) then
            return "Invitation from " .. Guild:DisplayName(g.creator), "Answer"
        end
        local waiting = {}
        for i, name in ipairs(g.invited) do
            if g.answers:sub(i, i) == "?" then waiting[#waiting + 1] = Guild:DisplayName(name) end
        end
        return "Waiting for answers", table.concat(waiting, ", ")
    end
    if g.status == "cancelled" then
        return "Cancelled", "Not enough players accepted"
    end
    if g.game == "backgammon" then
        if g.status ~= "active" then
            return "Finished", g.winner == g.me and "You won" or (self:PlayerName(g, g.winner) .. " won")
        end
        local turn = ("Turn %d"):format(g.turn)
        if self:IsMyTurn(g) then return turn, "Your turn" end
        return turn, self:PlayerName(g, self:CurrentSeat(g)) .. "'s turn"
    end
    if g.status ~= "active" then
        local standings = Rules.Standings(g)
        local winners = Rules.Winners(g)
        if #winners > 1 then
            return "Finished", ("Shared win (%d)"):format(standings[1].total)
        end
        local who = self:PlayerName(g, standings[1].seat)
        return "Finished", (who == "You" and "You won" or (who .. " won")) .. (" (%d)"):format(standings[1].total)
    end
    local round = ("Round %d/%d"):format(Rules.Round(g), Rules.NUM_TURNS)
    if self:IsMyTurn(g) then return round, "Your turn" end
    return round, self:PlayerName(g, Rules.CurrentPlayer(g)) .. "'s turn"
end

function Games:Title(g)
    local names = {}
    if g.kind == "guild" and (g.status == "pending" or g.status == "cancelled") then
        local me = Yatzy.Guild:MyName()
        for i, name in ipairs(g.invited) do
            if g.answers:sub(i, i) ~= "N" then
                names[#names + 1] = Yatzy.Guild:SameName(name, me) and "You" or Yatzy.Guild:DisplayName(name)
            end
        end
    else
        for seat = 1, #g.players do names[#names + 1] = self:PlayerName(g, seat) end
    end
    return table.concat(names, ", ")
end
