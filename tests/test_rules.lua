-- Tests for Yatzy/Rules.lua. Run from C:\Yatzy with:  luajit tests/test_rules.lua
-- Plain Lua 5.1 / LuaJIT, no libraries. Exits with code 1 if anything fails.

local Yatzy = {}
local chunk = assert(loadfile("Yatzy/Rules.lua"))
chunk("Yatzy", Yatzy)          -- same arguments WoW passes to addon files
local R = Yatzy.Rules

local passed, failed = 0, 0
local function check(name, actual, expected)
    if actual == expected then
        passed = passed + 1
    else
        failed = failed + 1
        print(("FAIL  %s: expected %s, got %s"):format(name, tostring(expected), tostring(actual)))
    end
end

-- A fake dice "random generator" that returns the given numbers in order.
local function fixedRng(values)
    local i = 0
    return function() i = i + 1; return values[i] end
end

---------------------------------------------------------------------------
-- Scoring
---------------------------------------------------------------------------
local S = R.Score
check("ones",                 S("ones",   {1,1,2,3,1}), 3)
check("ones none",            S("ones",   {2,3,4,5,6}), 0)
check("sixes",                S("sixes",  {6,6,6,2,1}), 18)
check("pair takes highest",   S("pair",   {3,3,5,5,1}), 10)
check("pair from three",      S("pair",   {4,4,4,2,1}), 8)
check("pair none",            S("pair",   {1,2,3,4,6}), 0)
check("two pairs",            S("twoPairs", {3,3,5,5,1}), 16)
check("two pairs from full",  S("twoPairs", {6,6,6,1,1}), 14)
check("6 players allowed", #R.NewGame({ "a", "b", "c", "d", "e", "f" }).players, 6)
check("7 players refused", pcall(R.NewGame, { "a", "b", "c", "d", "e", "f", "g" }), false)
check("two pairs not four",   S("twoPairs", {2,2,2,2,5}), 0)
check("two pairs none",       S("twoPairs", {2,2,3,4,5}), 0)
check("three of a kind",      S("three",  {2,2,2,5,5}), 6)
check("three from four",      S("three",  {3,3,3,3,1}), 9)
check("three none",           S("three",  {3,3,4,4,1}), 0)
check("four of a kind",       S("four",   {5,5,5,5,1}), 20)
check("four from yatzy",      S("four",   {5,5,5,5,5}), 20)
check("four none",            S("four",   {5,5,5,1,1}), 0)
check("small straight",       S("small",  {3,1,5,2,4}), 15)
check("small not large",      S("small",  {2,3,4,5,6}), 0)
check("large straight",       S("large",  {6,5,4,3,2}), 20)
check("large not small",      S("large",  {1,2,3,4,5}), 0)
check("full house",           S("full",   {2,2,3,3,3}), 13)
check("full house not yatzy", S("full",   {4,4,4,4,4}), 0)
check("full house not 4+1",   S("full",   {4,4,4,4,1}), 0)
check("chance",               S("chance", {1,2,3,4,6}), 16)
check("yatzy",                S("yatzy",  {6,6,6,6,6}), 50)
check("yatzy none",           S("yatzy",  {6,6,6,6,5}), 0)
check("IsYatzy",              R.IsYatzy({2,2,2,2,2}), true)
check("valid dice",           R.IsValidDice({1,2,3,4,5}), true)
check("invalid dice 7",       R.IsValidDice({1,2,3,4,7}), false)
check("invalid dice count",   R.IsValidDice({1,2,3,4}), false)

---------------------------------------------------------------------------
-- Score sheet totals and bonus
---------------------------------------------------------------------------
local exact63 = { ones = 3, twos = 6, threes = 9, fours = 12, fives = 15, sixes = 18 }
check("upper sum 63",  R.UpperSum(exact63), 63)
check("bonus at 63",   R.Bonus(exact63), 50)
check("total with bonus", R.Total(exact63), 113)
local only62 = { ones = 2, twos = 6, threes = 9, fours = 12, fives = 15, sixes = 18 }
check("no bonus at 62", R.Bonus(only62), 0)
check("struck field counts as 0", R.Total({ yatzy = 0, chance = 20 }), 20)
check("15 categories", #R.CATEGORIES, 15)

---------------------------------------------------------------------------
-- Turn flow
---------------------------------------------------------------------------
local g = R.NewGame({ "You", "Computer" })
check("starts active", g.status, "active")
check("player 1 starts", R.CurrentPlayer(g), 1)
check("round 1", R.Round(g), 1)
check("can't hold before rolling", (R.SetHeld(g, 1, true)), false)
check("can't score before rolling", (R.ScoreCategory(g, "chance")), nil)

check("roll 1", (R.Roll(g, fixedRng({6,6,2,3,4}))), true)
check("dice after roll 1", table.concat(g.dice, ","), "6,6,2,3,4")
R.SetHeld(g, 1, true); R.SetHeld(g, 2, true)
check("roll 2 keeps held dice", (R.Roll(g, fixedRng({6,1,5}))), true)
check("dice after roll 2", table.concat(g.dice, ","), "6,6,6,1,5")
R.SetHeld(g, 3, true)
R.Roll(g, fixedRng({6,6}))
check("dice after roll 3", table.concat(g.dice, ","), "6,6,6,6,6")
check("no 4th roll", (R.Roll(g, fixedRng({1,1,1,1,1}))), false)
check("can't hold after 3rd roll", (R.SetHeld(g, 1, false)), false)

check("score yatzy", R.ScoreCategory(g, "yatzy"), 50)
check("sheet written", g.sheets[1].yatzy, 50)
check("next player's turn", R.CurrentPlayer(g), 2)
check("dice reset", g.rollsUsed, 0)
check("held reset", g.held[1], false)

R.Roll(g, fixedRng({1,2,3,4,6}))
check("strike out (0)", R.ScoreCategory(g, "yatzy"), 0)
check("struck field stored as 0", g.sheets[2].yatzy, 0)
check("round 2", R.Round(g), 2)

R.Roll(g, fixedRng({1,1,1,1,1}))
check("category can't be used twice", (R.ScoreCategory(g, "yatzy")), nil)

-- Play the rest of the game: each player fills the categories in order.
local function playOut(game)
    while game.status == "active" do
        R.Roll(game, fixedRng({2,2,3,3,3}))
        for _, cat in ipairs(R.CATEGORIES) do
            if game.sheets[R.CurrentPlayer(game)][cat.id] == nil then
                R.ScoreCategory(game, cat.id)
                break
            end
        end
    end
end
playOut(g)
check("game over after 30 turns", g.status, "over")
check("both sheets full", R.IsSheetFull(g.sheets[1]) and R.IsSheetFull(g.sheets[2]), true)
check("no rolling after game over", (R.Roll(g)), false)
check("player 1 wins (had the Yatzy)", R.Winners(g)[1], 1)
check("one winner", #R.Winners(g), 1)

---------------------------------------------------------------------------
-- Turns arriving from other players (guild sync)
---------------------------------------------------------------------------
local n = R.NewGame({ "Anna", "Bo", "You" })
check("turn 1 is Anna's", R.PlayerForTurn(n, 1), 1)
check("turn 4 is Anna's again", R.PlayerForTurn(n, 4), 1)
check("reject wrong turn number", (R.ApplyTurn(n, 2, "chance", {1,2,3,4,5}, 15)), false)
check("reject wrong points", (R.ApplyTurn(n, 1, "chance", {1,2,3,4,5}, 99)), false)
check("reject bad dice", (R.ApplyTurn(n, 1, "chance", {1,2,3,4,9}, 19)), false)
check("reject unknown category", (R.ApplyTurn(n, 1, "bogus", {1,2,3,4,5}, 15)), false)
check("accept valid turn", (R.ApplyTurn(n, 1, "small", {1,2,3,4,5}, 15)), true)
check("Anna's sheet updated", n.sheets[1].small, 15)
check("now Bo's turn", R.CurrentPlayer(n), 2)
check("reject replayed turn", (R.ApplyTurn(n, 1, "small", {1,2,3,4,5}, 15)), false)
check("accept struck field", (R.ApplyTurn(n, 2, "yatzy", {1,2,3,4,6}, 0)), true)

-- History and skipped turns (players who left)
check("history records turns", n.history[1].cat, "small")
check("history keeps dice", n.history[1].dice, "12345")
check("Cid's turn now", R.CurrentPlayer(n), 3)
check("skip turn", R.SkipTurn(n), true)
check("skip strikes first empty field", n.sheets[3].ones, 0)
check("skip recorded as 00000", n.history[3].dice, "00000")
check("dice from string", table.concat(R.DiceFromString("61523")), "61523")
check("bad dice string", R.DiceFromString("123"), nil)

-- Shared win
local tie = R.NewGame({ "A", "B" })
playOut(tie)
check("equal play gives shared win", #R.Winners(tie), 2)

---------------------------------------------------------------------------
print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
