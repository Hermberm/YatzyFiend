-- Play.lua
-- Runs a game: your rolls, holds and scores, and the computer's turns.
-- The rules live in Rules.lua, the computer's decisions in AI.lua; this file only
-- decides WHEN things happen and tells the board and the sheet to redraw.

local _, Yatzy = ...
local Rules = Yatzy.Rules
local Play = {}
Yatzy.Play = Play

local COMPUTER_THINK = 0.7     -- pause before each computer action (seconds)
local COMPUTER_SAVE = 0.6      -- pause after the computer saves dice, before it rolls
local AFTER_SCORE = 0.8        -- pause after a score is written, before the next turn

Play.aiRuns = {}               -- [gameId] = token of the running computer turn

local function Games() return Yatzy.Games end
local function Board() return Yatzy.Board end
local function Sheet() return Yatzy.Sheet end

-- Is this game on screen right now?
function Play:IsShowing(g)
    return self.game == g and Yatzy.mainWindow and Yatzy.mainWindow:IsShown() and Yatzy.UI.game:IsShown()
end

function Play:Refresh()
    local g = self.game
    if not g then return end
    Board():Refresh(g)
    Sheet():Refresh(g)
end

---------------------------------------------------------------------------
-- Opening / closing a game
---------------------------------------------------------------------------

function Play:Open(g)
    self.game = g
    self.committing = false
    Board():SetGame(g)
    Sheet():SetGame(g)
    Yatzy.UI:Layout()
    self:Refresh()
    self:FlashMyTurn(g)
    self:ContinueComputer(g)
end

-- My turn just started in the game on screen: the Roll button flashes (once per turn).
function Play:FlashMyTurn(g)
    if not self:IsShowing(g) or not Games():IsMyTurn(g) or g.rollsUsed ~= 0 then return end
    if g.flashedTurn == g.turn then return end
    g.flashedTurn = g.turn
    Board():FlashRoll()
end

function Play:Close()
    self.game = nil
end

-- Computer turns in games that aren't on screen are played at once (e.g. after a /reload).
function Play:CatchUpComputerTurns()
    if Yatzy.BGPlay then Yatzy.BGPlay:CatchUpComputerTurns() end
    for _, g in ipairs(Games():All()) do
        if g.game ~= "backgammon" and g ~= self.game and Games():IsComputerTurn(g) and not self.aiRuns[g.id] then
            Yatzy.AI.PlayTurnInstantly(g)
            Games():Touch(g)
            if g.status ~= "active" then self:FinishGame(g) end
        end
    end
end

-- The window was opened again: redraw, and let a waiting computer turn continue.
function Play:OnWindowShown()
    self:CatchUpComputerTurns()
    if self.game then
        self:Refresh()
        self:FlashMyTurn(self.game)
        self:ContinueComputer(self.game)
    end
end

---------------------------------------------------------------------------
-- Your actions
---------------------------------------------------------------------------

function Play:Roll()
    local g = self.game
    if not g or not Games():IsMyTurn(g) or Board().animating or self.committing or Yatzy.Fast:TimeUp(g) then return end
    self.holdToken = (self.holdToken or 0) + 1      -- the roll message carries the saved dice
    Board():RollAnimated(g, function(roll) self:AfterRoll(g, false, roll) end)
    -- The dice are decided the moment RollAnimated returns: show them to the others now,
    -- so their animation runs at the same time as ours.
    if g.kind == "guild" and g.rollsUsed > 0 then Yatzy.Guild:SendLiveRoll(g) end
    Sheet():Refresh(g)
end

function Play:ToggleHold(index)
    local g = self.game
    if not g or not Games():IsMyTurn(g) or Board().animating or self.committing or Yatzy.Fast:TimeUp(g) then return end
    if Rules.SetHeld(g, index, not g.held[index]) then
        Yatzy.Sound:Play("hold")
        Board():Refresh(g)
        if g.kind == "guild" then
            -- Tell the others, after a short pause so quick clicks go as one message
            local token = (self.holdToken or 0) + 1
            self.holdToken = token
            C_Timer.After(0.3, function()
                if self.holdToken == token and g.status == "active" and Games():IsMyTurn(g) then
                    Yatzy.Guild:SendLiveHolds(g)
                end
            end)
        end
    end
end

-- Another player saved or put back dice between rolls: move them to/from the tray.
function Play:OnRemoteHolds(g, held)
    g.held = held
    if self:IsShowing(g) and not Board().animating then
        Yatzy.Sound:Play("hold")
        Board():Refresh(g)
    end
end

function Play:Score(categoryId)
    local g = self.game
    if not g or not Games():IsMyTurn(g) or Board().animating or self.committing or Yatzy.Fast:TimeUp(g) then return end
    local points = Rules.ScoreCategory(g, categoryId)
    if points == nil then return end
    Games():Touch(g)
    if g.kind == "guild" then Yatzy.Guild:OnLocalTurn(g) end   -- send the turn to the others
    self.committing = true
    Sheet():Refresh(g)
    Board():Refresh(g)
    C_Timer.After(AFTER_SCORE, function()
        self.committing = false
        Yatzy.UI:AfterScore()
        self:AfterTurn(g)
    end)
end

---------------------------------------------------------------------------
-- After rolls and turns
---------------------------------------------------------------------------

-- `roll` = what was rolled, frozen at the moment of the roll (see Board:RollAnimated).
function Play:AfterRoll(g, remote, roll)
    if roll and roll.rollNo and roll.rollNo > 0 and Rules.IsYatzy(roll.dice) then
        local mine = roll.seat == g.me
        if mine and not remote then
            Yatzy.Stats:AddYatzy(g)
            self:AnnounceYatzy(g, roll.turn)
        end
        self:CelebrateYatzy(g, roll.seat, roll.turn)
    end
    if self:IsShowing(g) then self:Refresh() end
end

-- I rolled a Yatzy in a game against guild members: tell the guild in guild chat.
-- Only my own client posts (no doubles), once per turn, never in games vs the computer.
-- Setting: "Announce my Yatzys in guild chat".
function Play:AnnounceYatzy(g, turn)
    if g.kind ~= "guild" or Yatzy.db.options.announceYatzy == false then return end
    if g.yatzyAnnounced == turn then return end
    g.yatzyAnnounced = turn
    if not (IsInGuild and IsInGuild()) or not SendChatMessage then return end
    local Guild = Yatzy.Guild
    local me = Guild:MyName() or (UnitName and UnitName("player")) or "Someone"
    SendChatMessage("YATZYYY", "GUILD")      -- chat already shows who wrote it
end

-- Someone rolled a Yatzy: celebrate once per turn. In the window if this game is on
-- screen, otherwise as a big YATZY! over the game world (on-screen notices setting).
function Play:CelebrateYatzy(g, seat, turn)
    turn = turn or g.turn
    if g.yatzyShown == turn then return end
    g.yatzyShown = turn
    local text = (seat == g.me) and "Five of a kind!" or (Games():PlayerName(g, seat) .. " rolled a Yatzy!")
    if self:IsShowing(g) then
        Board():Celebrate(text)
    elseif Yatzy.db.options.turnAlert ~= false then
        Board():CelebrateScreen(text)
    end
end

function Play:AfterTurn(g)
    if g.status ~= "active" then
        self:FinishGame(g)
    elseif Games():IsComputerTurn(g) then
        self:ContinueComputer(g)
    elseif Games():IsMyTurn(g) and not self:IsShowing(g) then
        self:AlertMyTurn(g)
    end
    if self:IsShowing(g) then self:Refresh(); self:FlashMyTurn(g) end
    if Yatzy.UI.start:IsShown() then Yatzy.UI:RefreshStart() end
end

function Play:FinishGame(g)
    if g.statsRecorded then return end
    Yatzy.Stats:Record(g)
    Games():Touch(g)
end

function Play:AlertMyTurn(g)
    if g.alertedTurn == g.turn then return end        -- only once per turn
    g.alertedTurn = g.turn
    Yatzy.Sound:Play("turn")                          -- the sound follows only the Sound setting
    if Yatzy.db.options.turnAlert == false then return end
    local others = {}
    for seat = 1, #g.players do
        if seat ~= g.me then others[#others + 1] = Games():PlayerName(g, seat) end
    end
    local vs = "vs " .. table.concat(others, " & ")
    Board():TurnPopup(vs)              -- big "Your turn!" in the title font, with a soft chime
    Yatzy:Print("Your turn " .. vs .. "!")
end

---------------------------------------------------------------------------
-- Guild games: news from other players
---------------------------------------------------------------------------

-- A guild game changed because of a message (answers, turns, someone left).
function Play:OnRemoteChange(g)
    if g.game == "backgammon" then return Yatzy.BGPlay:OnRemoteChange(g) end
    if g.status == "over" then
        self:FinishGame(g)
    elseif Games():IsMyTurn(g) and g.rollsUsed == 0 then
        if self:IsShowing(g) then
            if g.alertedTurn ~= g.turn then g.alertedTurn = g.turn; Yatzy.Sound:Play("turn") end
        else
            self:AlertMyTurn(g)
        end
    end
    if self:IsShowing(g) then
        Board():FinishAnimation(true)
        self:Refresh()
        self:FlashMyTurn(g)
    end
    if Yatzy.UI.start and Yatzy.UI.start:IsShown() then Yatzy.UI:RefreshStart() end
    if Yatzy.SideMenu.cover and Yatzy.SideMenu.cover:IsShown() then Yatzy.SideMenu:Refresh() end
end

-- Another player rolled while we're both online: show it live.
function Play:OnRemoteRoll(g, dice, held, rollNo)
    if self:IsShowing(g) then
        Board():FinishAnimation(true)
        Board():RollAnimated(g, function(roll) self:AfterRoll(g, true, roll) end, { dice = dice, held = held, roll = rollNo })
    else
        g.dice, g.held, g.rollsUsed = dice, held, rollNo
        if Rules.IsYatzy(dice) then self:CelebrateYatzy(g, Rules.CurrentPlayer(g)) end
    end
end

---------------------------------------------------------------------------
-- The computer's turn
-- Watched: one step at a time with pauses, so you can follow its rolls.
-- Not watched (window closed or another game open): the whole turn at once.
---------------------------------------------------------------------------

function Play:ContinueComputer(g)
    if not Games():IsComputerTurn(g) or self.aiRuns[g.id] then return end

    if not self:IsShowing(g) then
        Yatzy.AI.PlayTurnInstantly(g)
        Games():Touch(g)
        self:AfterTurn(g)
        return
    end

    local token = {}
    self.aiRuns[g.id] = token
    local function stillMine() return self.aiRuns[g.id] == token end
    local function stop() if stillMine() then self.aiRuns[g.id] = nil end end

    local step
    step = function()
        if not stillMine() then return end
        if not Games():IsComputerTurn(g) then stop(); return end

        -- Window closed or game switched while the computer was playing: finish at once.
        if not self:IsShowing(g) then
            stop()
            self:ContinueComputer(g)
            return
        end

        local action, arg = Yatzy.AI.NextAction(g)
        if action == "score" then
            Rules.ScoreCategory(g, arg)
            Games():Touch(g)
            self:Refresh()
            C_Timer.After(AFTER_SCORE, function()
                stop()
                self:AfterTurn(g)
            end)
            return
        end

        -- Save the dice it wants to keep, pause so you can see it, then roll.
        local changed = false
        if arg then
            for i = 1, Rules.NUM_DICE do
                if g.held[i] ~= arg[i] then
                    Rules.SetHeld(g, i, arg[i])
                    changed = true
                end
            end
        end
        if changed then Board():Refresh(g) end
        C_Timer.After(changed and COMPUTER_SAVE or 0, function()
            if not stillMine() then return end
            if not self:IsShowing(g) then stop(); self:ContinueComputer(g); return end
            Board():RollAnimated(g, function(roll)
                self:AfterRoll(g, false, roll)
                C_Timer.After(COMPUTER_THINK, step)
            end)
            Sheet():Refresh(g)
        end)
    end

    self:Refresh()
    C_Timer.After(COMPUTER_THINK, step)
end
