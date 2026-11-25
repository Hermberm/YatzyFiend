-- Tests for Yatzy/AI.lua. Run from C:\Yatzy with:  luajit tests/test_ai.lua

local Yatzy = {}
assert(loadfile("Yatzy/Rules.lua"))("Yatzy", Yatzy)
assert(loadfile("Yatzy/AI.lua"))("Yatzy", Yatzy)
local R, AI = Yatzy.Rules, Yatzy.AI

local passed, failed = 0, 0
local function check(name, actual, expected)
    if actual == expected then passed = passed + 1
    else failed = failed + 1; print(("FAIL  %s: expected %s, got %s"):format(name, tostring(expected), tostring(actual))) end
end
local function heldString(h) local s = {} for i = 1, 5 do s[i] = h[i] and "x" or "." end return table.concat(s) end

-- Hold decisions
check("keeps three of a kind", heldString(AI.ChooseHolds({4,4,2,4,6}, {})), "xx.x.")
check("keeps a 4-run for large straight", heldString(AI.ChooseHolds({2,3,4,6,6}, {})), "xxxx.")
check("keeps highest pair", heldString(AI.ChooseHolds({2,2,5,5,1}, { twoPairs = 0, full = 0 })), "..xx.")
check("keeps both pairs if useful", heldString(AI.ChooseHolds({2,2,5,5,1}, {})), "xxxx.")
check("keeps high dice otherwise", heldString(AI.ChooseHolds({1,2,3,5,6}, { small = 0, large = 0 })), "...xx")

-- Category choice
check("takes the Yatzy", AI.ChooseCategory({3,3,3,3,3}, {}), "yatzy")
check("takes a large straight", AI.ChooseCategory({2,3,4,5,6}, {}), "large")
check("never picks a used category", AI.ChooseCategory({2,3,4,5,6}, { large = 20 }) ~= "large", true)

-- Full games: the computer always finishes and never breaks the rules
math.randomseed(12345)
local totals, games = 0, 300
local allFull = true
for _ = 1, games do
    local g = R.NewGame({ "Computer" })
    while g.status == "active" do AI.PlayTurnInstantly(g) end
    if not R.IsSheetFull(g.sheets[1]) then allFull = false end
    totals = totals + R.Total(g.sheets[1])
end
local average = totals / games
check("every game fills the whole sheet", allFull, true)
check("average score is decent (> 170)", average > 170, true)
print(("Computer average over %d games: %.1f points"):format(games, average))

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
