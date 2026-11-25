-- BGAI.lua
-- The computer opponent for backgammon: one simple heuristic level.
-- It looks at every different way to play the dice (BG.AllTurns), scores each end
-- position with rules of thumb, and picks the best one. No look-ahead.
--
-- Like BGRules.lua, no WoW functions here (tests/test_bgai.lua).

local _, Yatzy = ...
local BG = Yatzy.BG
local AI = {}
Yatzy.BGAI = AI

-- How many of the 36 dice rolls hit a lone checker at this distance (ignoring blocks)
local SHOTS = { 11, 12, 14, 15, 15, 17, 6, 6, 5, 3, 2, 3 }

-- Is there still contact (can the players still hit each other)?
local function contact(b, seat)
    -- my rearmost checker vs their rearmost checker
    local s = BG.SIGN[seat]
    if b.bar[1] > 0 or b.bar[2] > 0 then return true end
    local myBack, theirBack
    for i = 1, 24 do
        if b.pts[i] * s > 0 then
            local d = BG.Distance(seat, i)
            if not myBack or d > myBack then myBack = d end
        elseif b.pts[i] * s < 0 then
            local d = BG.Distance(3 - seat, i)
            if not theirBack or d > theirBack then theirBack = d end
        end
    end
    if not myBack or not theirBack then return false end
    return myBack + theirBack > 25
end

-- How likely (0..1) a lone checker of `seat` at `pos` gets hit next turn
local function danger(b, seat, pos)
    local them, s = 3 - seat, BG.SIGN[seat]
    local shots = 0
    -- enemy checkers that move towards pos: they're "behind" it from their view
    for i = 1, 24 do
        if b.pts[i] * s < 0 then
            local dist = (i - pos) * BG.DIR[them] * -1
            if dist >= 1 and dist <= 12 then shots = math.max(shots, SHOTS[dist]) + 1 end
        end
    end
    if b.bar[them] > 0 then
        local dist = BG.Distance(them, pos)          -- from their bar (25 on their scale)
        dist = 25 - dist
        if dist >= 1 and dist <= 12 then shots = math.max(shots, SHOTS[dist]) + 1 end
    end
    return math.min(shots, 30) / 36
end

-- Score a position from `seat`'s point of view: higher is better
function AI.Evaluate(b, seat)
    local them = 3 - seat
    local s = BG.SIGN[seat]
    local score = (BG.Pips(b, them) - BG.Pips(b, seat))       -- the race
    score = score + b.off[seat] * 2

    if not contact(b, seat) then
        -- Pure race: just pips and getting checkers home / off
        for i = 1, 24 do
            local n = b.pts[i] * s
            if n > 0 and BG.Distance(seat, i) > 6 then score = score - 1 end
        end
        return score
    end

    score = score + b.bar[them] * 12                           -- hitting is strong
    score = score - b.bar[seat] * 12
    local run = 0
    for r = 1, 24 do                                           -- r = distance from my home end
        local pos = seat == 1 and r or 25 - r
        local n = b.pts[pos] * s
        if n >= 2 then
            score = score + 3
            if r <= 6 then score = score + 3 end               -- points in my home board
            if r >= 7 and r <= 9 then score = score + 1.5 end  -- bar point and nearby
            if r >= 19 then score = score + 1 end              -- anchor in their home
            run = run + 1
            if run >= 2 then score = score + run * 1.5 end     -- primes block them
            if n >= 5 then score = score - (n - 4) * 0.5 end   -- too many on one point
        else
            run = 0
            if n == 1 then
                local d = danger(b, seat, pos)
                local cost = 6 + (25 - r) * 0.3                -- further from home = worse to lose
                if r <= 6 and b.bar[them] > 0 then cost = cost + 2 end
                score = score - d * cost * 2
            end
        end
    end
    return score
end

-- Choose how to play: returns a list of moves { {from, to}, ... } (may be empty)
function AI.ChooseMoves(b, seat, dice)
    local turns = BG.AllTurns(b, seat, BG.DiceSteps(dice))
    local best, bestScore
    for _, t in ipairs(turns) do
        local sc = AI.Evaluate(t.board, seat)
        if not bestScore or sc > bestScore then best, bestScore = t, sc end
    end
    return best and best.moves or {}
end

-- Play the whole current turn at once (vs-computer games and timed-out turns).
function AI.PlayTurnInstantly(g, rng)
    if g.status ~= "active" then return false end
    BG.Roll(g, rng)
    while BG.Undo(g) do end
    local seat = BG.CurrentPlayer(g)
    for _, m in ipairs(AI.ChooseMoves(g.board, seat, g.dice)) do
        if not BG.Play(g, m.from, m.to) then break end
    end
    return BG.Finish(g)
end
