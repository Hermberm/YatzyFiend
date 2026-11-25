-- BGPlay.lua
-- Runs a backgammon game: your roll, moves, undo and Done, and the computer's turns.
-- The rules are in BGRules.lua, the computer's choices in BGAI.lua, the drawing in
-- BGBoard.lua. This file decides WHEN things happen.

local _, Yatzy = ...
local BG, AI = Yatzy.BG, Yatzy.BGAI
local Play = {}
Yatzy.BGPlay = Play

local COMPUTER_THINK = 0.7     -- pause before the computer rolls
local AFTER_ROLL = 0.5         -- pause between its roll and its first move
local BETWEEN_MOVES = 0.25     -- pause between its checker moves
local AFTER_TURN = 0.6         -- pause after its last move, before your turn

local function Games() return Yatzy.Games end
local function Board() return Yatzy.BGBoard end

-- Is this game on screen right now?
function Play:IsShowing(g)
    return g ~= nil and self.game == g and Board():IsShown()
end

-- May I click / move in this game now? (my turn, nothing animating, computer not busy,
-- and in a fast game my time isn't up)
-- `moving`: a checker still flying doesn't count (you may click the next checker at once)
function Play:CanAct(g, moving)
    local busy = moving and Board().rolling ~= nil or (not moving and Board():Busy())
    return g ~= nil and self:IsShowing(g) and Games():IsMyTurn(g) and not busy and not self.aiRun
        and not Yatzy.Fast:TimeUp(g)
end

local function isGuild(g) return g.kind == "guild" end

---------------------------------------------------------------------------
-- Auto finish: once the checkers have passed each other nothing can be hit any more.
-- If both players tick "Auto finish" (against the computer: just me), the computer plays
-- the rest of the game for both, and everything goes AUTO_SPEED times faster.
-- g.auto = { [seat] = true } is each player's choice (the other one's arrives as a message).
---------------------------------------------------------------------------

local AUTO_SPEED = 2

function Play:AutoOn(g)
    if not g or g.status ~= "active" or not g.auto or BG.Contact(g.board) then return false end
    local me = g.me or 1
    if g.kind == "computer" then return g.auto[me] == true end
    return g.auto[1] == true and g.auto[2] == true
end

-- How fast the animations and pauses run
function Play:Speed(g)
    return self:AutoOn(g) and AUTO_SPEED or 1
end

-- Is the computer playing MY turn for me right now?
function Play:AutoRunning(g)
    return self.aiRun ~= nil and self.autoMine == true and self.game == g
end

local function after(g, seconds, fn)
    C_Timer.After(seconds / Play:Speed(g), fn)
end

-- The tick box was clicked (or the other player's choice arrived)
function Play:SetAuto(g, on)
    if not g or g.status ~= "active" then return end
    g.auto = g.auto or {}
    g.auto[g.me or 1] = on and true or nil
    Games():Touch(g)
    if isGuild(g) then Yatzy.Guild:SendBGAuto(g) end
    Board():Refresh()
    self:ContinueAuto(g)
end

-- The other player ticked or unticked it
function Play:OnRemoteAuto(g, seat, on)
    if not g or g.status ~= "active" or seat == g.me then return end
    g.auto = g.auto or {}
    g.auto[seat] = on and true or nil
    if self:IsShowing(g) then Board():Refresh() end
    self:ContinueAuto(g)
end

-- My turn, and Auto finish is on for both: play it for me (nothing half-played yet)
function Play:ContinueAuto(g)
    if not g or g.status ~= "active" or self.aiRun then return end
    if not Games():IsMyTurn(g) or not self:AutoOn(g) then return end
    if #(g.moves or {}) > 0 then return end
    if self:IsShowing(g) and Board():Busy() then return end
    self:RunTurn(g, true)
end

function Play:Open(g)
    if self.game ~= g then self.aiRun = nil end
    self.game = g
    Board():Show(g)
    self:ContinueComputer(g)
    self:ContinueAuto(g)                       -- (opened mid-game with Auto finish already on)
end

function Play:Close()
    self.game = nil
    Board():Close()
end

---------------------------------------------------------------------------
-- Your actions
---------------------------------------------------------------------------

function Play:Roll()
    local g = self.game
    if not self:CanAct(g) then return end
    if g.dice then
        -- the opening roll is decided already: throwing shows it (once)
        if not Board():NeedsOpening(g) then return end
        g.openRolled = true
    else
        BG.Roll(g)
    end
    Games():Touch(g)
    -- the others online see the roll at the same time
    if isGuild(g) then Yatzy.Guild:SendBGLive(g, true) end
    Board():AnimateRoll(g, function() Board():Refresh() end)
end

-- steps = { {from, to}, ... }: one checker, one or more dice
function Play:Move(steps, startXY)
    local g = self.game
    if not self:CanAct(g, true) or not g.dice then return end
    Board():AnimatePath(g, steps, startXY, function()
        Board():Refresh()
        if isGuild(g) then Yatzy.Guild:SendBGLive(g) end
    end)
end

-- Takes back ALL your moves this turn in one click
function Play:Undo()
    local g = self.game
    if not self:CanAct(g) then return end
    local any = false
    while BG.Undo(g) do any = true end
    if any then
        Yatzy.Sound:Play("hold")
        Board():Deselect()
        Board():Refresh()
        if isGuild(g) then Yatzy.Guild:SendBGLive(g) end
    end
end

function Play:Done()
    local g = self.game
    if not self:CanAct(g) or not BG.CanFinish(g) then return end
    Board():Deselect()
    BG.Finish(g)
    Games():Touch(g)
    if isGuild(g) then
        Yatzy.Guild:OnLocalTurn(g)                         -- send the turn to the others
        if g.auto and g.auto[g.me] then Yatzy.Guild:SendBGAuto(g) end   -- (so they know my choice)
    end
    self:AfterTurn(g)
end

---------------------------------------------------------------------------
-- Guild games: news from the other player
---------------------------------------------------------------------------

-- A turn of mine has started in this game (nothing rolled or moved yet)
local function freshTurn(g)
    return Games():IsMyTurn(g) and #(g.moves or {}) == 0 and (g.dice == nil or g.turn == 1)
end

-- The game changed because of a message (answers, a turn arrived, someone gave up)
function Play:OnRemoteChange(g)
    if g.status == "over" then
        self:FinishGame(g)
    elseif freshTurn(g) and g.alertedTurn ~= g.turn then
        if self:IsShowing(g) then
            g.alertedTurn = g.turn
            Yatzy.Sound:Play("turn")
        else
            Yatzy.Play:AlertMyTurn(g)
        end
    end
    if self:IsShowing(g) then
        Board():StopAnimations()
        Board():Deselect()
        Board():Refresh()
    end
    local UI = Yatzy.UI
    if UI.start and UI.start:IsShown() and Yatzy.mainWindow and Yatzy.mainWindow:IsShown() then UI:RefreshStart() end
    if Yatzy.SideMenu.cover and Yatzy.SideMenu.cover:IsShown() then Yatzy.SideMenu:Refresh() end
    self:ContinueAuto(g)                       -- Auto finish: their turn arrived, play mine
end

-- The other player rolled or moved while we're both online: show it.
-- `moves` = all their moves so far this turn (encoded); usually one more than before.
function Play:OnRemoteLive(g, dice, moves)
    local list = BG.DecodeMoves(moves)
    if not list then return end
    local showing = self:IsShowing(g)
    if showing then Board():StopAnimations() end
    local newRoll = not g.dice or g.dice[1] ~= dice[1] or g.dice[2] ~= dice[2]
    local shown = BG.EncodeMoves(g.moves or {})

    -- Their moves so far, without animation
    local function applyAll()
        while BG.Undo(g) do end
        g.dice, g.moves = dice, {}
        for _, m in ipairs(list) do
            if not BG.Play(g, m.from, m.to) then break end
        end
    end

    if not showing then applyAll(); return end
    if newRoll then
        while BG.Undo(g) do end
        g.dice, g.moves = dice, {}
        if g.turn == 1 or #list > 0 then
            applyAll()
            Board():Refresh()
        else
            Board():AnimateRoll(g, function() Board():Refresh() end)
        end
    elseif #list == #(g.moves or {}) + 1 and moves:sub(1, #shown) == shown then
        local m = list[#list]
        Board():AnimatePath(g, { { from = m.from, to = m.to } }, nil, function() Board():Refresh() end)
    else
        applyAll()                     -- an undo, or several moves at once
        Board():Refresh()
    end
end

---------------------------------------------------------------------------
-- After a turn
---------------------------------------------------------------------------

function Play:AfterTurn(g)
    if g.status ~= "active" then
        self:FinishGame(g)
    elseif Games():IsComputerTurn(g) then
        self:ContinueComputer(g)
    elseif g.kind == "computer" then
        self:ContinueAuto(g)                   -- Auto finish: the computer is done, my turn again
    end
    if self:IsShowing(g) then Board():Refresh() end
    local UI = Yatzy.UI
    if UI.start and UI.start:IsShown() and Yatzy.mainWindow and Yatzy.mainWindow:IsShown() then UI:RefreshStart() end
end

-- Saved per game type: YatzyDB.stats.backgammon = { solo = {played, won}, guild = {...} }
function Play:FinishGame(g)
    if g.statsRecorded then return end
    g.statsRecorded = true
    g.auto = nil
    Games():Touch(g)
    local all = Yatzy.db.stats
    all.backgammon = all.backgammon or {}
    local key = g.kind == "guild" and "guild" or "solo"
    local s = all.backgammon[key] or { played = 0, won = 0 }
    s.played = s.played + 1
    if g.winner == g.me then s.won = s.won + 1 end
    all.backgammon[key] = s
    -- Head-to-head against the guild member (shared with Yatzy on the stats card)
    if g.kind == "guild" and g.players and g.me then
        local Guild = Yatzy.Guild
        local name = g.players[3 - g.me]
        if name then
            all.vs = all.vs or {}
            local k = Guild:Key(name)
            local r = all.vs[k] or { played = 0, won = 0, lost = 0 }
            r.name = Guild:DisplayName(name)
            r.played = r.played + 1
            if g.winner == g.me then r.won = r.won + 1 elseif g.winner then r.lost = r.lost + 1 end
            all.vs[k] = r
        end
    end
    if Yatzy.Stats then Yatzy.Stats:Refresh() end
end

-- Computer turns in games that aren't on screen are played at once (e.g. after a /reload)
function Play:CatchUpComputerTurns()
    for _, g in ipairs(Games():All()) do
        if g.game == "backgammon" and g ~= self.game and Games():IsComputerTurn(g) then
            AI.PlayTurnInstantly(g)
            Games():Touch(g)
            if g.status ~= "active" then self:FinishGame(g) end
        end
    end
end

---------------------------------------------------------------------------
-- The computer's turn
-- Watched: it rolls, then moves one checker at a time so you can follow.
-- Not watched (window closed or another game open): the whole turn at once.
---------------------------------------------------------------------------

function Play:ContinueComputer(g)
    if not Games():IsComputerTurn(g) or self.aiRun then return end
    self:RunTurn(g, false)
end

-- The computer plays the current turn: for the computer opponent (mine = false), or for
-- me when Auto finish is on (mine = true; in guild games my live moves and the finished
-- turn are sent like when I play by hand).
function Play:RunTurn(g, mine)
    local guild = mine and isGuild(g)
    -- Not watched: the whole turn at once
    local function instantly()
        AI.PlayTurnInstantly(g)
        Games():Touch(g)
        if guild then Yatzy.Guild:OnLocalTurn(g); Yatzy.Guild:SendBGAuto(g) end
        self:AfterTurn(g)
    end
    if not self:IsShowing(g) then return instantly() end

    local token = {}
    self.aiRun, self.autoMine = token, mine
    local function alive() return self.aiRun == token end
    -- The window was closed or another game opened: finish the turn at once
    local function bail()
        if alive() then self.aiRun = nil end
        if mine then self:ContinueAuto(g) else self:ContinueComputer(g) end
    end

    local function finish()
        if not alive() then return end
        self.aiRun = nil
        if not BG.Finish(g) then AI.PlayTurnInstantly(g) end   -- (safety: should not happen)
        Games():Touch(g)
        if guild then Yatzy.Guild:OnLocalTurn(g); Yatzy.Guild:SendBGAuto(g) end
        self:AfterTurn(g)
    end

    local function playMoves()
        if not alive() then return end
        if not self:IsShowing(g) then return bail() end
        local moves = AI.ChooseMoves(g.board, BG.CurrentPlayer(g), g.dice)
        local i = 0
        local function nextMove()
            if not alive() then return end
            if not self:IsShowing(g) then return bail() end
            i = i + 1
            local m = moves[i]
            if not m then
                after(g, AFTER_TURN, finish)
                return
            end
            Board():AnimatePath(g, { { from = m.from, to = m.to } }, nil, function()
                if guild then Yatzy.Guild:SendBGLive(g) end
                after(g, BETWEEN_MOVES, nextMove)
            end)
        end
        nextMove()
    end

    Board():Refresh()
    after(g, COMPUTER_THINK, function()
        if not alive() then return end
        if not self:IsShowing(g) then return bail() end
        if g.dice then
            playMoves()                                   -- the opening roll: already rolled
        else
            BG.Roll(g)
            if guild then Yatzy.Guild:SendBGLive(g, true) end
            Board():AnimateRoll(g, function() after(g, AFTER_ROLL, playMoves) end)
        end
    end)
end
