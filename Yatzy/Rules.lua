-- Rules.lua
-- The Yatzy rules (Scandinavian Yatzy): scoring and the turn flow of one game.
--
-- IMPORTANT: this file must not use any WoW functions. It is plain Lua 5.1, so it
-- can be tested outside the game (see tests/test_rules.lua). The UI, the computer
-- opponent and the guild sync all use these functions instead of their own rules.

local _, Yatzy = ...
local Rules = {}
Yatzy.Rules = Rules

Rules.NUM_DICE        = 5
Rules.MAX_ROLLS       = 3
Rules.BONUS_THRESHOLD = 63
Rules.BONUS_POINTS    = 50
Rules.YATZY_POINTS    = 50

-- The 15 categories, in score sheet order. `upper` = the face counted in the upper section.
Rules.CATEGORIES = {
    { id = "ones",     name = "Ones",            upper = 1 },
    { id = "twos",     name = "Twos",            upper = 2 },
    { id = "threes",   name = "Threes",          upper = 3 },
    { id = "fours",    name = "Fours",           upper = 4 },
    { id = "fives",    name = "Fives",           upper = 5 },
    { id = "sixes",    name = "Sixes",           upper = 6 },
    { id = "pair",     name = "One Pair" },
    { id = "twoPairs", name = "Two Pairs" },
    { id = "three",    name = "Three of a Kind" },
    { id = "four",     name = "Four of a Kind" },
    { id = "small",    name = "Small Straight" },
    { id = "large",    name = "Large Straight" },
    { id = "full",     name = "Full House" },
    { id = "chance",   name = "Chance" },
    { id = "yatzy",    name = "Yatzy" },
}
Rules.NUM_TURNS = #Rules.CATEGORIES   -- 15 turns per player

local categoryById = {}
for _, cat in ipairs(Rules.CATEGORIES) do
    categoryById[cat.id] = cat
end

function Rules.GetCategory(id)
    return categoryById[id]
end

---------------------------------------------------------------------------
-- Scoring
---------------------------------------------------------------------------

-- counts[face] = how many dice show that face
local function countFaces(dice)
    local counts = { 0, 0, 0, 0, 0, 0 }
    for i = 1, #dice do
        counts[dice[i]] = counts[dice[i]] + 1
    end
    return counts
end

local function sumDice(dice)
    local total = 0
    for i = 1, #dice do
        total = total + dice[i]
    end
    return total
end

-- Highest face that appears at least `n` times, or nil.
local function highestWithAtLeast(counts, n)
    for face = 6, 1, -1 do
        if counts[face] >= n then
            return face
        end
    end
    return nil
end

local function isRun(counts, from, to)
    for face = from, to do
        if counts[face] ~= 1 then
            return false
        end
    end
    return true
end

function Rules.IsValidDice(dice)
    if type(dice) ~= "table" or #dice ~= Rules.NUM_DICE then
        return false
    end
    for i = 1, Rules.NUM_DICE do
        local v = dice[i]
        if type(v) ~= "number" or v < 1 or v > 6 or v ~= math.floor(v) then
            return false
        end
    end
    return true
end

function Rules.IsYatzy(dice)
    local counts = countFaces(dice)
    return highestWithAtLeast(counts, 5) ~= nil
end

-- Points the dice would give in a category.
function Rules.Score(categoryId, dice)
    local cat = categoryById[categoryId]
    assert(cat, "unknown category: " .. tostring(categoryId))
    local counts = countFaces(dice)

    if cat.upper then
        return counts[cat.upper] * cat.upper
    end

    if categoryId == "pair" then
        local face = highestWithAtLeast(counts, 2)
        return face and face * 2 or 0

    elseif categoryId == "twoPairs" then
        -- Two DIFFERENT faces with at least two each (a full house counts; four of a kind doesn't).
        local first, second
        for face = 6, 1, -1 do
            if counts[face] >= 2 then
                if not first then first = face else second = face; break end
            end
        end
        return (first and second) and (first * 2 + second * 2) or 0

    elseif categoryId == "three" then
        local face = highestWithAtLeast(counts, 3)
        return face and face * 3 or 0

    elseif categoryId == "four" then
        local face = highestWithAtLeast(counts, 4)
        return face and face * 4 or 0

    elseif categoryId == "small" then
        return isRun(counts, 1, 5) and 15 or 0

    elseif categoryId == "large" then
        return isRun(counts, 2, 6) and 20 or 0

    elseif categoryId == "full" then
        -- Exactly three of one face and two of another (five of a kind is not a full house).
        local hasThree, hasTwo = false, false
        for face = 1, 6 do
            if counts[face] == 3 then hasThree = true end
            if counts[face] == 2 then hasTwo = true end
        end
        return (hasThree and hasTwo) and sumDice(dice) or 0

    elseif categoryId == "chance" then
        return sumDice(dice)

    elseif categoryId == "yatzy" then
        return Rules.IsYatzy(dice) and Rules.YATZY_POINTS or 0
    end

    return 0
end

---------------------------------------------------------------------------
-- Score sheets: sheet[categoryId] = points (0 = struck out), nil = still empty
---------------------------------------------------------------------------

function Rules.UpperSum(sheet)
    local total = 0
    for _, cat in ipairs(Rules.CATEGORIES) do
        if cat.upper then
            total = total + (sheet[cat.id] or 0)
        end
    end
    return total
end

function Rules.Bonus(sheet)
    return Rules.UpperSum(sheet) >= Rules.BONUS_THRESHOLD and Rules.BONUS_POINTS or 0
end

function Rules.Total(sheet)
    local total = 0
    for _, cat in ipairs(Rules.CATEGORIES) do
        total = total + (sheet[cat.id] or 0)
    end
    return total + Rules.Bonus(sheet)
end

function Rules.IsSheetFull(sheet)
    for _, cat in ipairs(Rules.CATEGORIES) do
        if sheet[cat.id] == nil then
            return false
        end
    end
    return true
end

---------------------------------------------------------------------------
-- A game
---------------------------------------------------------------------------
-- game = {
--   players   = { "Anna", "Bo", ... }      seat order = turn order
--   sheets    = { {..}, {..}, ... }        one score sheet per player
--   turn      = 1..(15 * #players)          the turn being played
--   rollsUsed = 0..3                        in the current turn
--   dice      = { 1..6 x5 }
--   held      = { bool x5 }                 dice saved in the tray
--   status    = "active" | "over"
-- }

local function newDiceState(game)
    game.rollsUsed = 0
    game.dice = { 1, 1, 1, 1, 1 }
    game.held = { false, false, false, false, false }
end

Rules.MAX_PLAYERS = 6

function Rules.NewGame(players)
    assert(type(players) == "table" and #players >= 1 and #players <= Rules.MAX_PLAYERS,
        "a game needs 1-" .. Rules.MAX_PLAYERS .. " players")
    local game = { players = {}, sheets = {}, turn = 1, status = "active" }
    for i, name in ipairs(players) do
        game.players[i] = name
        game.sheets[i] = {}
    end
    newDiceState(game)
    return game
end

function Rules.TotalTurns(game)
    return Rules.NUM_TURNS * #game.players
end

-- Seat number of the player whose turn it is.
function Rules.CurrentPlayer(game)
    return ((game.turn - 1) % #game.players) + 1
end

-- Which seat plays a given turn number (used to check turns that arrive from other players).
function Rules.PlayerForTurn(game, turn)
    return ((turn - 1) % #game.players) + 1
end

-- Round 1..15 (everyone plays once per round).
function Rules.Round(game)
    return math.min(Rules.NUM_TURNS, math.floor((game.turn - 1) / #game.players) + 1)
end

-- Roll all dice that aren't held. `rng` is optional: a function returning 1..6
-- (tests pass a fixed one; the game uses math.random).
function Rules.Roll(game, rng)
    if game.status ~= "active" then return false, "game is over" end
    if game.rollsUsed >= Rules.MAX_ROLLS then return false, "no rolls left" end
    rng = rng or function() return math.random(1, 6) end

    local rolledAny = false
    for i = 1, Rules.NUM_DICE do
        if game.rollsUsed == 0 or not game.held[i] then
            game.dice[i] = rng()
            rolledAny = true
        end
    end
    if not rolledAny then return false, "all dice are held" end

    game.rollsUsed = game.rollsUsed + 1
    return true
end

-- Hold (save) or release one die. Only between rolls 1 and 3.
function Rules.SetHeld(game, index, held)
    if game.status ~= "active" then return false, "game is over" end
    if game.rollsUsed == 0 then return false, "roll first" end
    if game.rollsUsed >= Rules.MAX_ROLLS then return false, "no rolls left" end
    if index < 1 or index > Rules.NUM_DICE then return false, "no such die" end
    game.held[index] = held and true or false
    return true
end

function Rules.CanScore(game, categoryId)
    if game.status ~= "active" then return false, "game is over" end
    if game.rollsUsed == 0 then return false, "roll first" end
    if not categoryById[categoryId] then return false, "unknown category" end
    if game.sheets[Rules.CurrentPlayer(game)][categoryId] ~= nil then return false, "category already used" end
    return true
end

-- Every finished turn is kept in game.history[turn] = { cat = id, dice = "12345", points = n }
-- (dice "00000" = a turn skipped because the player left). Guild sync re-sends these.
local function record(game, categoryId, dice, points)
    game.history = game.history or {}
    game.history[game.turn] = { cat = categoryId, dice = dice and table.concat(dice) or "00000", points = points }
end

local function advanceTurn(game)
    game.turn = game.turn + 1
    newDiceState(game)
    if game.turn > Rules.TotalTurns(game) then
        game.status = "over"
    end
end

-- The current player writes the current dice into a category (0 = strike it out).
-- Returns the points, or nil + reason.
function Rules.ScoreCategory(game, categoryId)
    local ok, reason = Rules.CanScore(game, categoryId)
    if not ok then return nil, reason end
    local points = Rules.Score(categoryId, game.dice)
    game.sheets[Rules.CurrentPlayer(game)][categoryId] = points
    record(game, categoryId, game.dice, points)
    advanceTurn(game)
    return points
end

-- A player who left the game: their turn strikes out their first empty category.
-- Every client does exactly the same, so all copies of the game stay identical.
function Rules.SkipTurn(game)
    if game.status ~= "active" then return false end
    local sheet = game.sheets[Rules.CurrentPlayer(game)]
    for _, cat in ipairs(Rules.CATEGORIES) do
        if sheet[cat.id] == nil then
            sheet[cat.id] = 0
            record(game, cat.id, nil, 0)
            advanceTurn(game)
            return true
        end
    end
    return false
end

-- Apply a finished turn that came from another player's client (guild games).
-- Checks everything so a broken or out-of-order message can't corrupt the game.
function Rules.ApplyTurn(game, turn, categoryId, dice, points)
    if game.status ~= "active" then return false, "game is over" end
    if turn ~= game.turn then return false, "wrong turn number" end
    if not categoryById[categoryId] then return false, "unknown category" end
    if not Rules.IsValidDice(dice) then return false, "invalid dice" end
    local seat = Rules.PlayerForTurn(game, turn)
    if game.sheets[seat][categoryId] ~= nil then return false, "category already used" end
    local expected = Rules.Score(categoryId, dice)
    if points ~= expected then return false, "points don't match the dice" end

    game.sheets[seat][categoryId] = expected
    record(game, categoryId, dice, expected)
    advanceTurn(game)
    return true
end

-- Dice string "12345" <-> table {1,2,3,4,5}
function Rules.DiceFromString(s)
    if type(s) ~= "string" or #s ~= Rules.NUM_DICE then return nil end
    local dice = {}
    for i = 1, Rules.NUM_DICE do dice[i] = tonumber(s:sub(i, i)) end
    return dice
end

-- Final standings: list of { seat, name, total }, best first.
function Rules.Standings(game)
    local list = {}
    for seat, name in ipairs(game.players) do
        list[#list + 1] = { seat = seat, name = name, total = Rules.Total(game.sheets[seat]) }
    end
    table.sort(list, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.seat < b.seat
    end)
    return list
end

-- Seats with the highest total (more than one = shared win).
function Rules.Winners(game)
    local standings = Rules.Standings(game)
    local winners = {}
    for _, entry in ipairs(standings) do
        if entry.total == standings[1].total then
            winners[#winners + 1] = entry.seat
        end
    end
    return winners
end
