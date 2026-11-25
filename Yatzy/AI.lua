-- AI.lua
-- The computer opponent: one "decent" level built from rules of thumb (heuristics).
-- Plain Lua 5.1, no WoW functions, so it can be tested outside the game (tests/test_ai.lua).

local _, Yatzy = ...
local Rules = Yatzy.Rules
local AI = {}
Yatzy.AI = AI

-- Roughly what an average turn scores in each category. Used to judge whether
-- a score is "good" for that box, and which box hurts least to strike out.
local EXPECTED = {
    ones = 2, twos = 5, threes = 8, fours = 11, fives = 14, sixes = 17,
    pair = 8, twoPairs = 14, three = 10, four = 6, small = 5, large = 6,
    full = 10, chance = 22, yatzy = 4,
}

local function countFaces(dice)
    local counts = { 0, 0, 0, 0, 0, 0 }
    for i = 1, #dice do counts[dice[i]] = counts[dice[i]] + 1 end
    return counts
end

local function isOpen(sheet, id) return sheet[id] == nil end

-- Which dice to keep before the next roll. Returns { bool x5 }.
function AI.ChooseHolds(dice, sheet)
    local counts = countFaces(dice)

    -- Most common face (ties go to the higher face).
    local best, bestFace = 0, 0
    for face = 1, 6 do
        if counts[face] > best or (counts[face] == best and face > bestFace) then
            best, bestFace = counts[face], face
        end
    end

    local held = {}
    -- Three or more of a kind: keep them and go for four of a kind / Yatzy.
    if best >= 3 then
        for i = 1, #dice do held[i] = dice[i] == bestFace end
        return held
    end

    -- Four of a straight: keep one of each face in the run.
    local runs = { { from = 2, to = 6, id = "large" }, { from = 1, to = 5, id = "small" } }
    for _, run in ipairs(runs) do
        if isOpen(sheet, run.id) then
            local present = 0
            for face = run.from, run.to do
                if counts[face] > 0 then present = present + 1 end
            end
            if present >= 4 then
                local used = {}
                for i = 1, #dice do
                    local v = dice[i]
                    held[i] = v >= run.from and v <= run.to and not used[v]
                    if held[i] then used[v] = true end
                end
                return held
            end
        end
    end

    -- Pairs: keep two pairs if they're still useful, otherwise the highest pair.
    if best == 2 then
        local pairs = {}
        for face = 6, 1, -1 do
            if counts[face] >= 2 then pairs[#pairs + 1] = face end
        end
        local keepTwo = #pairs >= 2 and (isOpen(sheet, "twoPairs") or isOpen(sheet, "full"))
        for i = 1, #dice do
            local v = dice[i]
            held[i] = v == pairs[1] or (keepTwo and v == pairs[2])
        end
        return held
    end

    -- Nothing going on: keep high dice (good for Chance and the upper section).
    for i = 1, #dice do held[i] = dice[i] >= 5 end
    return held
end

-- Which empty category to write the dice into (or strike out).
function AI.ChooseCategory(dice, sheet)
    local counts = countFaces(dice)
    local bestId, bestValue
    for _, cat in ipairs(Rules.CATEGORIES) do
        if isOpen(sheet, cat.id) then
            local value = Rules.Score(cat.id, dice) - EXPECTED[cat.id]
            -- Three or more of a face in the upper section keeps the 63 bonus on track.
            if cat.upper and counts[cat.upper] >= 3 then value = value + 4 end
            if bestValue == nil or value > bestValue then
                bestId, bestValue = cat.id, value
            end
        end
    end
    return bestId
end

-- What the computer does next in its turn:
--   "roll", held  -> set these dice as held, then roll
--   "score", id   -> write the dice into this category
function AI.NextAction(game)
    local sheet = game.sheets[Rules.CurrentPlayer(game)]
    if game.rollsUsed == 0 then
        return "roll", nil
    end
    if game.rollsUsed >= Rules.MAX_ROLLS then
        return "score", AI.ChooseCategory(game.dice, sheet)
    end
    if Rules.IsYatzy(game.dice) and isOpen(sheet, "yatzy") then
        return "score", "yatzy"
    end
    local held = AI.ChooseHolds(game.dice, sheet)
    local allHeld = true
    for i = 1, Rules.NUM_DICE do
        if not held[i] then allHeld = false end
    end
    if allHeld then
        return "score", AI.ChooseCategory(game.dice, sheet)
    end
    return "roll", held
end

-- Play the computer's whole turn at once (used when nobody is watching).
function AI.PlayTurnInstantly(game, rng)
    while game.status == "active" do
        local action, arg = AI.NextAction(game)
        if action == "score" then
            return Rules.ScoreCategory(game, arg), arg
        end
        if arg then
            for i = 1, Rules.NUM_DICE do Rules.SetHeld(game, i, arg[i]) end
        end
        Rules.Roll(game, rng)
    end
end
