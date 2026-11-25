-- Tests for Yatzy/BGRules.lua. Run from C:\Yatzy with:  luajit tests/test_bgrules.lua
-- Plain Lua 5.1 / LuaJIT, no libraries. Exits with code 1 if anything fails.

local Yatzy = {}
assert(loadfile("Yatzy/BGRules.lua"))("Yatzy", Yatzy)
local BG = Yatzy.BG

local passed, failed = 0, 0
local function check(name, actual, expected)
    if actual == expected then
        passed = passed + 1
    else
        failed = failed + 1
        print(("FAIL  %s: expected %s, got %s"):format(name, tostring(expected), tostring(actual)))
    end
end

local function fixedRng(values)
    local i = 0
    return function() i = i + 1; return values[i] end
end

-- An empty board, then place checkers: place(b, seat, pos, n)
local function empty()
    local b = BG.NewBoard()
    for i = 1, 24 do b.pts[i] = 0 end
    return b
end
local function place(b, seat, pos, n)
    if pos == BG.BAR[seat] then b.bar[seat] = b.bar[seat] + n
    elseif pos == BG.OFF[seat] then b.off[seat] = b.off[seat] + n
    else b.pts[pos] = b.pts[pos] + BG.SIGN[seat] * n end
end
local function has(moves, from, to)
    for _, m in ipairs(moves) do if m.from == from and m.to == to then return true end end
    return false
end
local function total(b, seat)
    local n = b.bar[seat] + b.off[seat]
    for i = 1, 24 do
        local v = b.pts[i] * BG.SIGN[seat]
        if v > 0 then n = n + v end
    end
    return n
end

---------------------------------------------------------------------------
-- Start position
---------------------------------------------------------------------------
local b = BG.NewBoard()
check("15 checkers seat 1", total(b, 1), 15)
check("15 checkers seat 2", total(b, 2), 15)
check("pips at start seat 1", BG.Pips(b, 1), 167)
check("pips at start seat 2", BG.Pips(b, 2), 167)

---------------------------------------------------------------------------
-- Opening roll
---------------------------------------------------------------------------
local g = BG.NewGame({ "Herm", "Gulki" }, fixedRng({ 3, 3, 2, 5 }))   -- tie first, then 2 vs 5
check("tie rerolled, higher starts", g.first, 2)
check("opening dice kept", g.dice[1] .. g.dice[2], "25")
check("seat 2 plays turn 1", BG.CurrentPlayer(g), 2)
check("seat 1 plays turn 2", BG.PlayerForTurn(g, 2), 1)
check("turn 1 is already rolled", BG.Roll(g), false)

---------------------------------------------------------------------------
-- Simple moves, blocking, hitting
---------------------------------------------------------------------------
b = BG.NewBoard()
local moves = BG.LegalMoves(b, 1, { 3, 1 })
check("8 -> 5 with a 3", has(moves, 8, 5), true)
check("6 -> 5 with a 1", has(moves, 6, 5), true)
check("24 -> 21 with a 3", has(moves, 24, 21), true)
check("can't land on 12 (5 enemy)", BG.Target(b, 1, 13, 1), nil)
check("13 -> 12 blocked", has(moves, 13, 12), false)

b = empty()
place(b, 1, 10, 1); place(b, 2, 7, 1); place(b, 2, 20, 14)
check("hit lands", BG.Target(b, 1, 10, 3), 7)
local hit = BG.MoveChecker(b, 1, 10, 7)
check("hit reported", hit, true)
check("hit checker on the bar", b.bar[2], 1)
check("hitter on the point", b.pts[7], 1)
BG.UnmoveChecker(b, 1, 10, 7, hit)
check("undo hit: bar empty", b.bar[2], 0)
check("undo hit: enemy back", b.pts[7], -1)
check("undo hit: mine back", b.pts[10], 1)

---------------------------------------------------------------------------
-- Bar: must enter first
---------------------------------------------------------------------------
b = BG.NewBoard()
b.pts[6] = 4; b.bar[1] = 1
moves = BG.LegalMoves(b, 1, { 6, 2 })
check("enter with 2 on 23", has(moves, 25, 23), true)
check("6 can't enter (19 is blocked)", has(moves, 25, 19), false)
check("no other first move while on bar", has(moves, 13, 7), false)
-- seat 2 enters on 1..6
b = BG.NewBoard(); b.pts[19] = -4; b.bar[2] = 1
moves = BG.LegalMoves(b, 2, { 3, 4 })
check("seat 2 enters on 3", has(moves, 0, 3), true)
check("seat 2 entering on 4", has(moves, 0, 4), true)
-- fully blocked: no moves
b = empty()
for p = 19, 24 do place(b, 2, p, 2) end
place(b, 1, 25, 1); place(b, 1, 10, 14); place(b, 2, 1, 3)
moves = BG.LegalMoves(b, 1, { 3, 5 })
check("closed board: no moves", #moves, 0)

---------------------------------------------------------------------------
-- Use as many dice as possible / higher die rule
---------------------------------------------------------------------------
-- Seat 1 one checker on 10, blocks on 4 and 7: 10-3=7 blocked, 10-6=4 blocked...
b = empty()
place(b, 1, 10, 1); place(b, 1, 1, 14)
place(b, 2, 4, 2); place(b, 2, 2, 13)
-- dice 6,3: 10->4 blocked (6), 10->7 open (3), then 7->1 with 6 ok. Must use both:
moves = BG.LegalMoves(b, 1, { 6, 3 })
check("must play 3 first to use both", has(moves, 10, 7), true)
check("only that move", #moves, 1)

-- Only one die can be played: must be the higher
b = empty()
place(b, 1, 9, 1); place(b, 1, 1, 14)
place(b, 2, 5, 2); place(b, 2, 3, 2); place(b, 2, 7, 2); place(b, 2, 2, 9)
-- dice 6-1: 9->3 is blocked; 9->8 works, but then 8->2 is blocked: only one die can be used
local need
moves, need = BG.LegalMoves(b, 1, { 6, 1 })
check("one die playable", need, 1)
b = empty()
place(b, 1, 12, 1); place(b, 1, 1, 14)
place(b, 2, 6, 2); place(b, 2, 3, 2); place(b, 2, 2, 11)
-- dice 5,4: 12->7 ok (then 7->3 blocked, 7->... 4 used), 12->8 ok (then 8->3 blocked).
-- 7 -> 3 (4) blocked, 8 -> 3 (5) blocked: only one die can be played: must be the 5.
moves, need = BG.LegalMoves(b, 1, { 5, 4 })
check("higher die rule: need 1", need, 1)
check("higher die rule: 12 -> 7", has(moves, 12, 7), true)
check("higher die rule: not 12 -> 8", has(moves, 12, 8), false)

---------------------------------------------------------------------------
-- Bearing off
---------------------------------------------------------------------------
b = empty()
place(b, 1, 6, 1); place(b, 1, 3, 2); place(b, 1, 0, 12); place(b, 2, 24, 15)
check("exact bear off", BG.Target(b, 1, 3, 3), 0)
check("higher die only from the furthest", BG.Target(b, 1, 3, 5), nil)
check("higher die from the furthest point", BG.Target(b, 1, 6, 6), 0)
b = empty()
place(b, 1, 3, 2); place(b, 1, 0, 13); place(b, 2, 24, 15)
check("6 bears off from 3 when 3 is highest", BG.Target(b, 1, 3, 6), 0)
b = empty()
place(b, 1, 8, 1); place(b, 1, 3, 14); place(b, 2, 24, 15)
check("no bearing off with a checker outside", BG.Target(b, 1, 3, 3), nil)
-- seat 2
b = empty()
place(b, 2, 22, 2); place(b, 2, 25, 13); place(b, 1, 1, 15)
check("seat 2 bears off from 22 with a 3", BG.Target(b, 2, 22, 3), 25)
check("seat 2 bears off from 22 with a 6", BG.Target(b, 2, 22, 6), 25)

---------------------------------------------------------------------------
-- A turn: play, undo, finish, history
---------------------------------------------------------------------------
g = BG.NewGame({ "Herm", "Gulki" }, fixedRng({ 3, 1 }))          -- seat 1 starts with 3-1
check("seat 1 starts", BG.CurrentPlayer(g), 1)
check("can't finish before moving", BG.CanFinish(g), false)
check("8 -> 5", BG.Play(g, 8, 5) ~= nil, true)
check("illegal 13 -> 12", BG.Play(g, 13, 12), nil)
check("6 -> 5", BG.Play(g, 6, 5) ~= nil, true)
check("point made", g.board.pts[5], 2)
check("dice used up", #BG.DiceLeft(g), 0)
check("undo", BG.Undo(g), true)
check("undo gives the die back", #BG.DiceLeft(g), 1)
BG.Play(g, 6, 5)
check("finish", BG.Finish(g), true)
check("history dice", g.history[1].dice, "31")
check("history moves", g.history[1].moves, BG.EncodeMoves({ { from = 8, to = 5 }, { from = 6, to = 5 } }))
check("next player", BG.CurrentPlayer(g), 2)
check("dice cleared", g.dice, nil)
check("roll", BG.Roll(g, fixedRng({ 4, 4 })), true)
check("doubles give four steps", #BG.DiceLeft(g), 4)

-- encode / decode
local enc = BG.EncodeMoves({ { from = 25, to = 21 }, { from = 3, to = 0 } })
check("encode bar/off", enc, "zvda")
local dec = BG.DecodeMoves(enc)
check("decode", dec[1].from .. "-" .. dec[1].to .. "," .. dec[2].from .. "-" .. dec[2].to, "25-21,3-0")
check("decode rejects odd length", BG.DecodeMoves("abc"), nil)

-- Reachable with several dice: 13 -> 8 -> 5 with 5-3
g = BG.NewGame({ "Herm", "Gulki" }, fixedRng({ 5, 3 }))
local r = BG.Reachable(g, 13)
check("13 reaches 8", r[8] and #r[8], 1)
check("13 reaches 10", r[10] and #r[10], 1)
check("13 reaches 5 in two steps", r[5] and #r[5], 2)
check("Reachable leaves the board alone", #g.moves, 0)
check("board unchanged after Reachable", g.board.pts[13], 5)

---------------------------------------------------------------------------
-- Remote turns
---------------------------------------------------------------------------
local a = BG.NewGame({ "Herm", "Gulki" }, fixedRng({ 6, 2 }))
local c = BG.NewGame({ "Herm", "Gulki" }, fixedRng({ 6, 2 }))
BG.Play(a, 24, 18); BG.Play(a, 13, 11); BG.Finish(a)
check("remote turn applied", BG.ApplyTurn(c, 1, a.history[1].dice, a.history[1].moves), true)
check("copies agree", BG.BoardKey(a.board), BG.BoardKey(c.board))
check("wrong turn number refused", BG.ApplyTurn(c, 1, "62", a.history[1].moves), false)
local before = BG.BoardKey(c.board)
check("illegal remote move refused", BG.ApplyTurn(c, 2, "31", BG.EncodeMoves({ { from = 1, to = 9 } })), false)
check("refused turn changes nothing", BG.BoardKey(c.board), before)
check("too few moves refused", BG.ApplyTurn(c, 2, "31", BG.EncodeMoves({ { from = 1, to = 4 } })), false)
check("turn 1 dice must match the opening", BG.ApplyTurn(BG.NewGame({ "a", "b" }, fixedRng({ 6, 2 })), 1, "51", "ngnh"), false)

---------------------------------------------------------------------------
-- Winning
---------------------------------------------------------------------------
g = BG.NewGame({ "Herm", "Gulki" }, fixedRng({ 3, 1 }))
g.board = empty()
place(g.board, 1, 1, 1); place(g.board, 1, 2, 1); place(g.board, 1, 0, 13); place(g.board, 2, 24, 15)
check("bear off last", BG.Play(g, 2, 0) ~= nil and BG.Play(g, 1, 0) ~= nil, true)
check("finish winning turn", BG.Finish(g), true)
check("game over", g.status, "over")
check("winner", g.winner, 1)

g = BG.NewGame({ "Herm", "Gulki" }, fixedRng({ 3, 1 }))
check("resign", BG.Resign(g, 1), true)
check("resign: other wins", g.winner, 2)

---------------------------------------------------------------------------
-- Random games: the rules never lose or invent checkers, and games end
---------------------------------------------------------------------------
math.randomseed(42)
local ended, broken = 0, 0
for _ = 1, 200 do
    g = BG.NewGame({ "A", "B" })
    local guard = 0
    while g.status == "active" and guard < 2000 do
        guard = guard + 1
        BG.Roll(g)
        while true do
            local legal = BG.Legal(g)
            if #legal == 0 then break end
            local m = legal[math.random(#legal)]
            if not BG.Play(g, m.from, m.to) then broken = broken + 1; break end
        end
        if not BG.Finish(g) then broken = broken + 1; break end
        if total(g.board, 1) ~= 15 or total(g.board, 2) ~= 15 then broken = broken + 1; break end
    end
    if g.status == "over" then ended = ended + 1 end
end
check("random games all end", ended, 200)

-- Contact: still there at the start, gone once the sides have passed each other, and never back
do
    local nb = BG.NewBoard()
    check("contact at the start", BG.Contact(nb), true)
    local pb = BG.NewBoard()
    for i = 1, 24 do pb.pts[i] = 0 end
    pb.pts[3], pb.pts[5] = 4, 3          -- seat 1 low down
    pb.pts[10], pb.pts[20] = -2, -5      -- seat 2 higher up
    check("passed: no contact", BG.Contact(pb), false)
    pb.bar[1] = 1
    check("a checker on the bar means contact", BG.Contact(pb), true)
    pb.bar[1] = 0
    pb.pts[11] = 1                       -- one seat-1 checker behind a seat-2 checker
    check("one checker behind: contact", BG.Contact(pb), true)
    local back = 0
    math.randomseed(7)
    for _ = 1, 100 do
        local gg = BG.NewGame({ "A", "B" })
        local was, guard = false, 0
        while gg.status == "active" and guard < 2000 do
            guard = guard + 1
            BG.Roll(gg)
            while true do
                local legal = BG.Legal(gg)
                if #legal == 0 then break end
                local m = legal[math.random(#legal)]
                BG.Play(gg, m.from, m.to)
            end
            BG.Finish(gg)
            local c = BG.Contact(gg.board)
            if was and c then back = back + 1 end
            if not c then was = true end
        end
    end
    check("contact never comes back", back, 0)
end
check("random games never break", broken, 0)

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
