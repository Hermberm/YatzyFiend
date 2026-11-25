-- Fast.lua
-- Fast mode for guild games: every turn has a time limit (10 minutes). When it runs out,
-- the computer plays that turn, so a game never stalls. Players can "poke" the one whose
-- turn it is. Invitations to a fast game run out after 5 minutes.
--
-- How the computer turn stays the same on every copy of the game:
--  * its dice come from a number generator started from the game id and the turn number,
--    so whoever plays it gets exactly the same dice and choices;
--  * normally the late player's own client plays it right at the deadline (its buttons are
--    locked from then on); if that player is offline, the first ONLINE player after them
--    in the turn order does it, 15 seconds later. Sending the same turn twice is harmless.
--  * the turn clock is not saved: after logging in or /reload it starts again, so an old
--    saved time can never make anyone play a turn that was already played elsewhere.
--
-- Message: K:to:id:turn   "poke" (the receiver only reacts if it's their turn)

local _, Yatzy = ...
local Rules = Yatzy.Rules
local Fast = {
    TURN_LIMIT = 600,        -- seconds per turn
    INVITE_LIMIT = 300,      -- seconds to answer a fast invitation
    GRACE = 15,              -- the others wait this much longer than the late player's own client
    SLEEP_AFTER = 3,         -- timeouts in a row before the short limit
    SLEEP_LIMIT = 30,        -- seconds per turn for a player who seems to be away
}
Yatzy.Fast = Fast
Fast.clock = {}              -- [game id] = { turn = n, started = server time }

local function Games() return Yatzy.Games end
local function Guild() return Yatzy.Guild end
local function now() return (GetServerTime and GetServerTime()) or time() end

function Fast:IsFast(g)
    return g and g.kind == "guild" and g.fast == true
end

-- Seconds the current player has for this turn
function Fast:Limit(g, seat)
    seat = seat or Games():CurrentSeat(g)
    local missed = g.missed and g.missed[seat] or 0
    return missed >= self.SLEEP_AFTER and self.SLEEP_LIMIT or self.TURN_LIMIT
end

-- Called whenever the turn may have changed: starts the clock for a new turn and works
-- out whether the turn that just ended ran out of time (the computer played it).
function Fast:Note(g)
    if not self:IsFast(g) then return end
    local c = self.clock[g.id]
    if g.status ~= "active" then self.clock[g.id] = nil; return end
    if c and c.turn == g.turn then return end
    if c and g.turn == c.turn + 1 then
        local seat = g.game == "backgammon" and Yatzy.BG.PlayerForTurn(g, c.turn) or Rules.PlayerForTurn(g, c.turn)
        g.missed = g.missed or {}
        local late = now() - c.started >= self:Limit(g, seat) - 1
        if late then
            g.missed[seat] = (g.missed[seat] or 0) + 1
            local who = seat == g.me and "you" or Games():PlayerName(g, seat)
            Yatzy:Print(("[%s] Time's up for %s: the computer played %s turn."):format(
                Yatzy.UI and Yatzy.UI.RowTitle and Yatzy.UI:RowTitle(g) or "Yatzy", who, seat == g.me and "your" or "their"))
        else
            g.missed[seat] = 0
        end
    end
    self.clock[g.id] = { turn = g.turn, started = now() }
end

-- Seconds left in the current turn (nil when the game has no clock)
function Fast:TimeLeft(g)
    if not self:IsFast(g) or g.status ~= "active" then return nil end
    local c = self.clock[g.id]
    if not c or c.turn ~= g.turn then self:Note(g); c = self.clock[g.id] end
    return c.started + self:Limit(g) - now()
end

-- My turn, and my time is up: my buttons do nothing any more
function Fast:TimeUp(g)
    local left = self:TimeLeft(g)
    return left ~= nil and left <= 0
end

-- "7:42"
function Fast:Format(seconds)
    seconds = math.max(0, math.floor(seconds))
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

-- Should MY client play the computer turn now? Returns true and how long after the
-- deadline to wait.
function Fast:ShouldPlay(g)
    local cur = Games():CurrentSeat(g)
    if cur == g.me then return true, 0 end
    local n = #g.players
    for k = 1, n - 1 do
        local seat = (cur - 1 + k) % n + 1
        if not Guild():HasLeft(g, seat) then
            if seat == g.me then return true, self.GRACE end
            if Guild():IsOnline(g.players[seat]) then return false end
        end
    end
    return false
end

-- The same "random" numbers on every copy: seeded by the game id and the turn
local function rngFor(g)
    local seed = ((tonumber((tostring(g.id):gsub("%D", ""):sub(-9))) or 1) + g.turn * 7919) % 2147483647
    if seed == 0 then seed = 1 end
    return function()
        seed = (seed * 48271) % 2147483647
        return seed % 6 + 1
    end
end
Fast.RngFor = rngFor

-- Play the current turn for the late player and send it to everyone
function Fast:AutoTurn(g)
    if g.game == "backgammon" then
        -- start the turn over (moves taken back; new dice from the shared generator, except
        -- turn 1 whose dice are the opening roll), so every copy plays exactly the same turn
        local BG, BGPlay = Yatzy.BG, Yatzy.BGPlay
        if BGPlay.game == g then Yatzy.BGBoard:StopAnimations(); Yatzy.BGBoard:Deselect() end
        while BG.Undo(g) do end
        if g.turn > 1 then g.dice = nil end
        Yatzy.BGAI.PlayTurnInstantly(g, rngFor(g))
        Games():Touch(g)
        Guild():OnLocalTurn(g)
        BGPlay:AfterTurn(g)
        return
    end
    local Board = Yatzy.Board
    if Yatzy.Play.game == g and Board and Board.animating then Board:FinishAnimation(true) end
    g.rollsUsed = 0
    for i = 1, Rules.NUM_DICE do g.held[i] = false end
    Yatzy.AI.PlayTurnInstantly(g, rngFor(g))
    Games():Touch(g)
    Guild():OnLocalTurn(g)          -- sends the turn (and moves the game on, which notes the clock)
    Yatzy.Play:AfterTurn(g)
end

-- Every second: run out turns and fast invitations, update the timers on screen
function Fast:Tick()
    local any = false
    for _, g in ipairs(Games():All()) do
        if self:IsFast(g) then
            if g.status == "active" and g.players then
                any = true
                local left = self:TimeLeft(g)
                if left <= 0 then
                    local mine, wait = self:ShouldPlay(g)
                    if mine and -left >= wait then self:AutoTurn(g) end
                end
            elseif g.status == "pending" and Guild():IsCreator(g)
                and now() - (g.created or now()) >= self.INVITE_LIMIT then
                Guild():StartNow(g)
            end
        end
    end
    if any then
        local Play = Yatzy.Play
        if Play.game and self:IsFast(Play.game) and Play:IsShowing(Play.game) then Yatzy.Board:UpdateTimer(Play.game) end
        local BGPlay = Yatzy.BGPlay
        if BGPlay.game and self:IsFast(BGPlay.game) and BGPlay:IsShowing(BGPlay.game) then Yatzy.BGBoard:UpdateTimer(BGPlay.game) end
        self.listTick = (self.listTick or 0) + 1
        if self.listTick >= 10 then
            self.listTick = 0
            local UI = Yatzy.UI
            if UI.start and UI.start:IsShown() then UI:RefreshStart() end
        end
    end
end

---------------------------------------------------------------------------
-- Poke
---------------------------------------------------------------------------

function Fast:CanPoke(g)
    return self:IsFast(g) and g.status == "active" and not Games():IsMyTurn(g) and g.pokedTurn ~= g.turn
end

function Fast:Poke(g)
    if not self:CanPoke(g) then return end
    g.pokedTurn = g.turn
    Yatzy.Comm:Send("*", "K", g.id, tostring(g.turn))
    Yatzy:Print(("You poked %s."):format(Games():PlayerName(g, Games():CurrentSeat(g))))
end

function Fast:OnPoke(f, sender)
    local g = Games():Get(f[1])
    if not g or not self:IsFast(g) or g.status ~= "active" or tonumber(f[2]) ~= g.turn then return end
    if not Games():IsMyTurn(g) then return end
    g.pokes = g.pokes or {}
    local key = Guild():Short(sender) .. ":" .. g.turn
    if g.pokes[key] then return end                       -- once per player per turn
    g.pokes[key] = true
    local who = Guild():DisplayName(sender)
    local left = self:TimeLeft(g)
    Yatzy:Print(("%s poked you: it's your turn in %s (%s left)."):format(who,
        Yatzy.UI:RowTitle(g), self:Format(left or 0)))
    Yatzy.Sound:Play("turn")
    if Yatzy.db.options.turnAlert ~= false and Yatzy.Board.TurnPopup then
        Yatzy.Board:TurnPopup(who .. " pokes you!")
    end
end

function Fast:Init()
    Yatzy.Comm:On("K", function(f, sender) Fast:OnPoke(f, sender) end)
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(1, function() Fast:Tick() end)
    end
end
