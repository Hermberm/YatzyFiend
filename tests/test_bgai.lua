-- Tests for Yatzy/BGAI.lua. Run from C:\Yatzy with:  luajit tests/test_bgai.lua

local Yatzy = {}
assert(loadfile("Yatzy/BGRules.lua"))("Yatzy", Yatzy)
assert(loadfile("Yatzy/BGAI.lua"))("Yatzy", Yatzy)
local BG, AI = Yatzy.BG, Yatzy.BGAI

local passed, failed = 0, 0
local function check(name, actual, expected)
    if actual == expected then
        passed = passed + 1
    else
        failed = failed + 1
        print(("FAIL  %s: expected %s, got %s"):format(name, tostring(expected), tostring(actual)))
    end
end
local function has(moves, from, to)
    for _, m in ipairs(moves) do if m.from == from and m.to == to then return true end end
    return false
end

-- Opening 3-1: the classic play is 8/5 6/5 (make the 5-point)
local b = BG.NewBoard()
local m = AI.ChooseMoves(b, 1, { 3, 1 })
check("3-1 makes the 5 point", has(m, 8, 5) and has(m, 6, 5), true)
-- Opening 6-1: 13/7 8/7 (make the bar point)
m = AI.ChooseMoves(b, 1, { 6, 1 })
check("6-1 makes the bar point", has(m, 13, 7) and has(m, 8, 7), true)

-- Seat 2 sees the board mirrored: 3-1 for seat 2 is 17/20 19/20
m = AI.ChooseMoves(b, 2, { 3, 1 })
check("seat 2: 3-1 makes its 5 point", has(m, 17, 20) and has(m, 19, 20), true)

-- Every chosen play is legal
math.randomseed(7)
local illegal = 0
for _ = 1, 50 do
    local g = BG.NewGame({ "A", "B" })
    for _ = 1, 30 do
        if g.status ~= "active" then break end
        if not AI.PlayTurnInstantly(g) then illegal = illegal + 1; break end
    end
end
check("computer plays only legal turns", illegal, 0)

-- The computer beats a random player most of the time
local function randomTurn(g)
    BG.Roll(g)
    while true do
        local legal = BG.Legal(g)
        if #legal == 0 then break end
        local mv = legal[math.random(#legal)]
        BG.Play(g, mv.from, mv.to)
    end
    return BG.Finish(g)
end
local wins, games = 0, 60
local slowest = 0
for i = 1, games do
    local g = BG.NewGame({ "AI", "Random" })
    while g.status == "active" do
        local t0 = os.clock()
        if BG.CurrentPlayer(g) == 1 then AI.PlayTurnInstantly(g) else randomTurn(g) end
        slowest = math.max(slowest, os.clock() - t0)
    end
    if g.winner == 1 then wins = wins + 1 end
end
print(("computer won %d of %d vs random; slowest turn %.0f ms"):format(wins, games, slowest * 1000))
check("computer wins at least 85%", wins >= games * 0.85, true)

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
