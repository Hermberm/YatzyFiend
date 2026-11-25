-- BGRules.lua
-- The backgammon rules: the board, legal moves, turns and winning.
-- Standard rules without the doubling cube: hitting, entering from the bar, bearing off.
--
-- IMPORTANT: like Rules.lua, this file must not use any WoW functions. It is plain Lua 5.1,
-- so it can be tested outside the game (tests/test_bgrules.lua).
--
-- The board, seen from one fixed side:
--   positions 1..24 are the points. pts[i] > 0 = seat 1's checkers, pts[i] < 0 = seat 2's.
--   Seat 1 moves from 24 down to 1 (home board 1-6). Its bar is 25 and "borne off" is 0.
--   Seat 2 moves from 1 up to 24 (home board 19-24). Its bar is 0 and "borne off" is 25.
-- So every move is just "from -> to" with numbers 0..25, whoever makes it.
-- (The UI turns the board around so that you always play from the bottom.)

local _, Yatzy = ...
local BG = {}
Yatzy.BG = BG

BG.CHECKERS = 15

local SIGN = { 1, -1 }
local DIR  = { -1, 1 }
local BAR  = { 25, 0 }
local OFF  = { 0, 25 }
BG.SIGN, BG.DIR, BG.BAR, BG.OFF = SIGN, DIR, BAR, OFF

local function defaultRng() return math.random(1, 6) end

---------------------------------------------------------------------------
-- Board
---------------------------------------------------------------------------

function BG.NewBoard()
    local pts = {}
    for i = 1, 24 do pts[i] = 0 end
    -- seat 1: 2 on its 24-point, 5 on 13, 3 on 8, 5 on 6
    pts[24], pts[13], pts[8], pts[6] = 2, 5, 3, 5
    -- seat 2: the mirror image
    pts[1], pts[12], pts[17], pts[19] = -2, -5, -3, -5
    return { pts = pts, bar = { 0, 0 }, off = { 0, 0 } }
end

function BG.CopyBoard(b)
    local pts = {}
    for i = 1, 24 do pts[i] = b.pts[i] end
    return { pts = pts, bar = { b.bar[1], b.bar[2] }, off = { b.off[1], b.off[2] } }
end

-- How many of `seat`'s checkers are at a position (point, bar or off)
function BG.Count(b, seat, pos)
    if pos == BAR[seat] then return b.bar[seat] end
    if pos == OFF[seat] then return b.off[seat] end
    if pos < 1 or pos > 24 then return 0 end
    local v = b.pts[pos] * SIGN[seat]
    return v > 0 and v or 0
end

-- Distance still to travel for a checker of `seat` at a point (bar = 25)
local function distance(seat, pos)
    if seat == 1 then return pos end
    return 25 - pos
end
BG.Distance = distance

-- Pip count: the total number of pips a player still needs to bear everything off
function BG.Pips(b, seat)
    local total = b.bar[seat] * 25
    for i = 1, 24 do
        local n = b.pts[i] * SIGN[seat]
        if n > 0 then total = total + n * distance(seat, i) end
    end
    return total
end

local function allHome(b, seat)
    if b.bar[seat] > 0 then return false end
    local s = SIGN[seat]
    for i = 1, 24 do
        if b.pts[i] * s > 0 and distance(seat, i) > 6 then return false end
    end
    return true
end
BG.AllHome = allHome

-- Where a checker of `seat` at `from` lands with `die`, or nil if that move isn't allowed.
-- (Only this single step: the "use as many dice as possible" rule is in LegalMoves.)
function BG.Target(b, seat, from, die)
    if b.bar[seat] > 0 and from ~= BAR[seat] then return nil end   -- enter from the bar first
    if BG.Count(b, seat, from) == 0 or from == OFF[seat] then return nil end
    local to = from + DIR[seat] * die
    if to >= 1 and to <= 24 then
        if b.pts[to] * SIGN[seat] <= -2 then return nil end     -- blocked: 2 or more of theirs
        return to
    end
    -- Bearing off: only when all 15 are in the home board
    if not allHome(b, seat) then return nil end
    local d = distance(seat, from)
    if die == d then return OFF[seat] end
    -- A higher die than needed may only bear off the checker furthest from home
    for p = d + 1, 6 do
        local pos = seat == 1 and p or 25 - p
        if b.pts[pos] * SIGN[seat] > 0 then return nil end
    end
    return OFF[seat]
end

-- Can the two players still meet (hit or block each other)? Seat 1 moves down, seat 2 up,
-- so once every checker of seat 1 is below every checker of seat 2 they have passed each
-- other for good and the rest of the game is a plain race.
function BG.Contact(b)
    local top1, low2
    if b.bar[1] > 0 then top1 = 25 end
    if b.bar[2] > 0 then low2 = 0 end
    for i = 24, 1, -1 do
        if b.pts[i] > 0 then top1 = top1 or i; break end
    end
    for i = 1, 24 do
        if b.pts[i] < 0 then low2 = low2 or i; break end
    end
    if not top1 or not low2 then return false end     -- one side has nothing left on the board
    return top1 > low2
end

-- Move one checker (no checks). Returns true if it hit a lone enemy checker.
function BG.MoveChecker(b, seat, from, to)
    local s = SIGN[seat]
    if from == BAR[seat] then b.bar[seat] = b.bar[seat] - 1 else b.pts[from] = b.pts[from] - s end
    if to == OFF[seat] then
        b.off[seat] = b.off[seat] + 1
        return false
    end
    local hit = false
    if b.pts[to] * s == -1 then
        b.pts[to] = 0
        b.bar[3 - seat] = b.bar[3 - seat] + 1
        hit = true
    end
    b.pts[to] = b.pts[to] + s
    return hit
end

-- Exactly undo MoveChecker
function BG.UnmoveChecker(b, seat, from, to, hit)
    local s = SIGN[seat]
    if to == OFF[seat] then
        b.off[seat] = b.off[seat] - 1
    else
        b.pts[to] = b.pts[to] - s
        if hit then
            b.pts[to] = -s
            b.bar[3 - seat] = b.bar[3 - seat] - 1
        end
    end
    if from == BAR[seat] then b.bar[seat] = b.bar[seat] + 1 else b.pts[from] = b.pts[from] + s end
end

-- Positions a player could move a checker from right now
local function sources(b, seat)
    if b.bar[seat] > 0 then return { BAR[seat] } end
    local list, s = {}, SIGN[seat]
    for i = 1, 24 do
        if b.pts[i] * s > 0 then list[#list + 1] = i end
    end
    return list
end

local function without(dice, index)
    local rest = {}
    for i, d in ipairs(dice) do if i ~= index then rest[#rest + 1] = d end end
    return rest
end

local function boardKey(b)
    return table.concat(b.pts, ",") .. "|" .. b.bar[1] .. "," .. b.bar[2] .. "|" .. b.off[1] .. "," .. b.off[2]
end
BG.BoardKey = boardKey

local function diceKey(dice)
    local copy = {}
    for i, d in ipairs(dice) do copy[i] = d end
    table.sort(copy)
    return table.concat(copy)
end

-- The most dice that can still be used from this position (remembered in `memo`)
local function depth(b, seat, dice, memo)
    if #dice == 0 then return 0 end
    local k = boardKey(b) .. "#" .. diceKey(dice)
    if memo[k] then return memo[k] end
    local best, tried = 0, {}
    for i, die in ipairs(dice) do
        if not tried[die] then
            tried[die] = true
            local rest = without(dice, i)
            for _, from in ipairs(sources(b, seat)) do
                local to = BG.Target(b, seat, from, die)
                if to then
                    local hit = BG.MoveChecker(b, seat, from, to)
                    local d = 1 + depth(b, seat, rest, memo)
                    BG.UnmoveChecker(b, seat, from, to, hit)
                    if d > best then best = d end
                    if best == #dice then break end
                end
            end
        end
        if best == #dice then break end
    end
    memo[k] = best
    return best
end

-- All single-checker moves allowed now: { {from=, to=, die=}, ... }, and how many dice
-- will be used in total. The rules: use as many dice as possible; if only one of two
-- different dice can be used, it must be the higher one when that's possible.
function BG.LegalMoves(b, seat, dice)
    local memo = {}
    local need = depth(b, seat, dice, memo)
    local moves = {}
    if need == 0 then return moves, 0 end
    local tried = {}
    for i, die in ipairs(dice) do
        if not tried[die] then
            tried[die] = true
            local rest = without(dice, i)
            for _, from in ipairs(sources(b, seat)) do
                local to = BG.Target(b, seat, from, die)
                if to then
                    local hit = BG.MoveChecker(b, seat, from, to)
                    local d = 1 + depth(b, seat, rest, memo)
                    BG.UnmoveChecker(b, seat, from, to, hit)
                    if d == need then moves[#moves + 1] = { from = from, to = to, die = die } end
                end
            end
        end
    end
    if need == 1 and #dice == 2 and dice[1] ~= dice[2] then
        local high = math.max(dice[1], dice[2])
        local big = {}
        for _, m in ipairs(moves) do if m.die == high then big[#big + 1] = m end end
        if #big > 0 then moves = big end
    end
    return moves, need
end

-- Every different end position a whole turn can reach (for the computer opponent):
-- { {board=, moves={ {from,to,die}, ... }}, ... }. Uses the same rules as LegalMoves.
function BG.AllTurns(b, seat, dice)
    local results, seen, visited = {}, {}, {}
    local path = {}
    local function walk(board, rest)
        local moves = BG.LegalMoves(board, seat, rest)
        if #moves == 0 then
            local k = boardKey(board)
            if not seen[k] then
                seen[k] = true
                local copy = {}
                for i, m in ipairs(path) do copy[i] = m end
                results[#results + 1] = { board = BG.CopyBoard(board), moves = copy }
            end
            return
        end
        local vk = boardKey(board) .. "#" .. diceKey(rest)
        if visited[vk] then return end
        visited[vk] = true
        for _, m in ipairs(moves) do
            local idx
            for i, d in ipairs(rest) do if d == m.die then idx = i; break end end
            local hit = BG.MoveChecker(board, seat, m.from, m.to)
            path[#path + 1] = m
            walk(board, without(rest, idx))
            path[#path] = nil
            BG.UnmoveChecker(board, seat, m.from, m.to, hit)
        end
    end
    walk(BG.CopyBoard(b), dice)
    return results
end

---------------------------------------------------------------------------
-- Games and turns
-- g.game = "backgammon", g.players = { name1, name2 } (seat 1, seat 2)
-- g.board, g.turn (1, 2, ...), g.first (seat that plays turn 1)
-- g.dice = { a, b } once this turn is rolled, else nil
-- g.moves = moves made so far this turn (can be undone): { {from, to, die, hit}, ... }
-- g.history[n] = { dice = "35", moves = "nifd" } (two letters per move, see EncodeMoves)
-- g.status = "active" or "over"; g.winner = seat
---------------------------------------------------------------------------

-- `rng` is optional: a function returning 1..6.
-- The opening roll: each player rolls one die (again on a tie); the higher die starts
-- and plays both dice, so turn 1 is already rolled.
function BG.NewGame(players, rng)
    rng = rng or defaultRng
    if #players ~= 2 then error("backgammon needs exactly 2 players") end
    local a, b
    repeat a, b = rng(), rng() until a ~= b
    return {
        game = "backgammon",
        players = { players[1], players[2] },
        board = BG.NewBoard(),
        turn = 1,
        first = a > b and 1 or 2,
        opening = { a, b },            -- seat 1's die, seat 2's die (for the UI)
        dice = { a, b },
        moves = {},
        history = {},
        status = "active",
    }
end

function BG.PlayerForTurn(g, n)
    return (g.first - 1 + n - 1) % 2 + 1
end

function BG.CurrentPlayer(g)
    return BG.PlayerForTurn(g, g.turn)
end

-- Roll this turn's dice (does nothing if they're rolled already)
function BG.Roll(g, rng)
    if g.status ~= "active" or g.dice then return false end
    rng = rng or defaultRng
    g.dice = { rng(), rng() }
    g.moves = {}
    return true
end

-- The dice of this turn as single steps: doubles give four
function BG.DiceSteps(dice)
    if not dice then return {} end
    if dice[1] == dice[2] then return { dice[1], dice[1], dice[1], dice[1] } end
    return { dice[1], dice[2] }
end

-- Dice not used yet this turn
function BG.DiceLeft(g)
    local left = BG.DiceSteps(g.dice)
    for _, m in ipairs(g.moves or {}) do
        for i, d in ipairs(left) do
            if d == m.die then table.remove(left, i); break end
        end
    end
    return left
end

function BG.Legal(g)
    if g.status ~= "active" or not g.dice then return {}, 0 end
    return BG.LegalMoves(g.board, BG.CurrentPlayer(g), BG.DiceLeft(g))
end

-- Find the allowed move from -> to. When several dice could do it (bearing off with a
-- higher die), the lowest one is used.
function BG.FindMove(g, from, to)
    local best
    for _, m in ipairs((BG.Legal(g))) do
        if m.from == from and m.to == to and (not best or m.die < best.die) then best = m end
    end
    return best
end

-- Move one checker this turn. Returns the move, or nil if it isn't allowed.
function BG.Play(g, from, to)
    local m = BG.FindMove(g, from, to)
    if not m then return nil end
    local hit = BG.MoveChecker(g.board, BG.CurrentPlayer(g), m.from, m.to)
    local done = { from = m.from, to = m.to, die = m.die, hit = hit }
    g.moves[#g.moves + 1] = done
    return done
end

-- Where one checker can get to this turn by using several dice in a row
-- (e.g. 13 -> 8 -> 5 with 5-3). Returns { [to] = { move, move, ... } }, shortest first.
function BG.Reachable(g, from)
    local seat = BG.CurrentPlayer(g)
    local result = {}
    local function walk(pos, steps)
        for _, m in ipairs((BG.Legal(g))) do
            if m.from == pos then
                local newSteps = {}
                for i, s in ipairs(steps) do newSteps[i] = s end
                newSteps[#newSteps + 1] = { from = m.from, to = m.to }
                if not result[m.to] or #result[m.to] > #newSteps then result[m.to] = newSteps end
                if m.to ~= OFF[seat] then
                    local done = BG.Play(g, m.from, m.to)
                    if done then
                        walk(m.to, newSteps)
                        BG.Undo(g)
                    end
                end
            end
        end
    end
    walk(from, {})
    return result
end

function BG.CanUndo(g)
    return g.moves ~= nil and #g.moves > 0
end

function BG.Undo(g)
    local m = g.moves and g.moves[#g.moves]
    if not m then return false end
    BG.UnmoveChecker(g.board, BG.CurrentPlayer(g), m.from, m.to, m.hit)
    g.moves[#g.moves] = nil
    return true
end

-- The turn can be finished when no more moves are allowed (or required)
function BG.CanFinish(g)
    return g.status == "active" and g.dice ~= nil and #(BG.Legal(g)) == 0
end

-- Positions 0..25 as letters a..z (so one move is two letters)
function BG.EncodeMoves(moves)
    local out = {}
    for _, m in ipairs(moves) do
        out[#out + 1] = string.char(97 + m.from) .. string.char(97 + m.to)
    end
    return table.concat(out)
end

function BG.DecodeMoves(s)
    local moves = {}
    if not s or #s % 2 ~= 0 then return nil end
    for i = 1, #s, 2 do
        local a, b = s:byte(i) - 97, s:byte(i + 1) - 97
        if a < 0 or a > 25 or b < 0 or b > 25 then return nil end
        moves[#moves + 1] = { from = a, to = b }
    end
    return moves
end

-- Lock in this turn: written to the history, the game ends when someone has borne
-- everything off, otherwise the other player is next. Returns true if it was allowed.
function BG.Finish(g)
    if not BG.CanFinish(g) then return false end
    local seat = BG.CurrentPlayer(g)
    g.history[g.turn] = { dice = g.dice[1] .. g.dice[2], moves = BG.EncodeMoves(g.moves) }
    g.lastMoves = g.moves                  -- for the UI: show what was just played
    g.lastDice = g.dice
    g.moves = {}
    g.dice = nil
    if g.board.off[seat] >= BG.CHECKERS then
        g.status = "over"
        g.winner = seat
    else
        g.turn = g.turn + 1
    end
    return true
end

-- A whole turn from someone else (guild games): checked move by move against the rules.
-- Returns true if it was valid and applied; otherwise nothing changes.
function BG.ApplyTurn(g, turnNo, diceStr, movesStr)
    if g.status ~= "active" or turnNo ~= g.turn then return false end
    local a, b = tonumber(diceStr:sub(1, 1)), tonumber(diceStr:sub(2, 2))
    if #diceStr ~= 2 or not a or not b or a < 1 or a > 6 or b < 1 or b > 6 then return false end
    local moves = BG.DecodeMoves(movesStr)
    if not moves then return false end
    local o = g.opening
    if turnNo == 1 and o and not (o[1] == a and o[2] == b) then return false end
    -- Moves shown live (or my own half-played moves, when the computer played my late
    -- turn elsewhere) are taken back first: the turn that arrived is the real one.
    while BG.Undo(g) do end
    local saved = { board = BG.CopyBoard(g.board), dice = g.dice, moves = g.moves }
    g.dice, g.moves = { a, b }, {}
    local ok = true
    for _, m in ipairs(moves) do
        if not BG.Play(g, m.from, m.to) then ok = false; break end
    end
    if ok then ok = BG.Finish(g) end
    if not ok then
        g.board, g.dice, g.moves = saved.board, saved.dice, saved.moves
    end
    return ok
end

-- Turns finished so far (the history has no gaps)
function BG.TurnsDone(g)
    return #(g.history or {})
end

-- The same "random" numbers on every copy of a game: started from the game id.
-- (Used for the opening roll of guild games, so nobody has to send it.)
function BG.RngFromId(id, salt)
    local seed = ((tonumber((tostring(id):gsub("%D", ""):sub(-9))) or 1) + (salt or 0) * 7919) % 2147483647
    if seed == 0 then seed = 1 end
    return function()
        seed = (seed * 48271) % 2147483647
        return seed % 6 + 1
    end
end

-- A player left or resigned: the other one wins.
function BG.Resign(g, seat)
    if g.status ~= "active" then return false end
    -- put back anything half-played this turn
    while BG.Undo(g) do end
    g.status = "over"
    g.winner = 3 - seat
    g.resigned = seat
    return true
end
