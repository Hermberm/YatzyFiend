-- Simulates guild games between several players, each running their own copy of
-- the addon, connected by a fake message server that behaves like WoW: Forever
-- (see tests/wowmock.lua: realm strings differ per client, names can have spaces,
-- whispering "Name-Realm" fails). Run from C:\Yatzy:
--   luajit tests/sim_guild.lua

local Mock = dofile("tests/wowmock.lua")
math.randomseed(7)

-- Since 0.10 the turn order is random. Most checks here are written for "the creator
-- starts", so every client keeps the invitation order; step 19 tests the random order.
do
    local newClient = Mock.NewClient
    Mock.NewClient = function(...)
        local c = newClient(...)
        c.realShuffle = c.ns.Guild.ShuffleFor
        c.ns.Guild.ShuffleFor = function() end
        return c
    end
end

local passed, failed = 0, 0
local function check(name, cond)
    if cond then passed = passed + 1 else failed = failed + 1; print("FAIL  " .. name) end
end

local bus = Mock.NewBus()
local anna = Mock.NewClient(bus, "Anna", "CAMWOWEU4Realm6PvP", "Berm")       -- roster: "Anna Berm"
local bo = Mock.NewClient(bus, "Bo", "CAMWOWEU5Realm6PvP", "Ghouliath")      -- roster: "Bo Ghouliath"
Mock.Pump(bus)

local function game(client, id) return client.ns.Games:Get(id) end
-- the name `who` has in `client`'s guild roster
local function R(client, who) return Mock.RosterName(client, who.short) end

-- Play one full turn as `client`, through the UI code (window open on that game).
local function playTurn(client, id)
    local ns = client.ns
    if not ns.mainWindow:IsShown() then ns:ToggleMainWindow() end
    ns.UI:ShowGame(id)
    Mock.Pump(bus)
    local g = game(client, id)
    assert(ns.Games:IsMyTurn(g), client.short .. " expected its turn")
    ns.Play:Roll(); Mock.Pump(bus)
    ns.Play:ToggleHold(1)
    ns.Play:Roll(); Mock.Pump(bus)
    for _, cat in ipairs(ns.Rules.CATEGORIES) do
        if ns.Rules.CanScore(g, cat.id) then ns.Play:Score(cat.id); break end
    end
    Mock.Pump(bus)
end

local function sameSheets(a, b, id)
    local ga, gb = game(a, id), game(b, id)
    if not ga or not gb or ga.turn ~= gb.turn then return false end
    for seat = 1, #ga.players do
        for _, cat in ipairs(anna.ns.Rules.CATEGORIES) do
            if ga.sheets[seat][cat.id] ~= gb.sheets[seat][cat.id] then return false end
        end
    end
    return true
end

---------------------------------------------------------------------------
print("0. Names and who has Yatzy")
check("Anna learned her roster name (with surname)", anna.ns.Guild:MyName() == "Anna Berm-CAMWOWEU4Realm6PvP")
check("roster name and game name are the same player", anna.ns.Guild:SameName("Bo Ghouliath-CAMWOWEU4Realm6PvP", "Bo-CAMWOWEU5Realm6PvP"))
check("different first names are different players", not anna.ns.Guild:SameName("Bo Ghouliath-X", "Boris Ghouliath-X"))
check("Anna knows Bo has Yatzy (presence at login)", anna.ns.Guild:VersionOf(R(anna, bo)) == anna.ns.version)

---------------------------------------------------------------------------
print("1. Invite and accept (both online)")
local g = anna.ns.Guild:CreateGame({ R(anna, bo) })
local id = g.id
Mock.Pump(bus)
local bg = game(bo, id)
check("Bo received the invitation", bg ~= nil)
check("Bo hasn't answered yet", bg and bo.ns.Games:IsInvite(bg))
check("Bo got a raid-warning notice", (bo.warnings or 0) >= 1)
check("Anna's game waits for answers", g.status == "pending")
bo.ns.Guild:Answer(bg, true)
Mock.Pump(bus)
check("game started for Anna", g.status == "active")
check("game started for Bo", bg.status == "active")
check("Anna is seat 1, Bo seat 2", g.me == 1 and bg.me == 2)

---------------------------------------------------------------------------
print("2. Take turns while both online (with live rolls)")
for _ = 1, 3 do
    playTurn(anna, id)
    playTurn(bo, id)
end
check("both copies agree after 6 turns", sameSheets(anna, bo, id))
check("turn 7 is Anna's", g.turn == 7 and anna.ns.Games:IsMyTurn(g))

---------------------------------------------------------------------------
print("3. Bo offline: Anna plays; Bo catches up when he logs in")
Mock.SetOnline(bus, "Bo", false)
Mock.Pump(bus)
playTurn(anna, id)
check("Bo did not get the turn while offline", bg.turn == 7)
Mock.SetOnline(bus, "Bo", true)
Mock.Pump(bus)
check("Bo caught up after coming online", bg.turn == 8)
check("copies agree after catch-up", sameSheets(anna, bo, id))

---------------------------------------------------------------------------
print("4. Three players; a turn reaches Cid through Bo after Anna logs off")
local cid = Mock.NewClient(bus, "Cid", "CAMWOWEU4Realm6PvP")
Mock.Pump(bus)
local g3 = anna.ns.Guild:CreateGame({ R(anna, bo), R(anna, cid) })
local id3 = g3.id
Mock.Pump(bus)
bo.ns.Guild:Answer(game(bo, id3), true)
Mock.Pump(bus)
cid.ns.Guild:Answer(game(cid, id3), true)
Mock.Pump(bus)
check("3-player game active for all", g3.status == "active" and game(bo, id3).status == "active" and game(cid, id3).status == "active")

Mock.SetOnline(bus, "Cid", false); Mock.Pump(bus)
playTurn(anna, id3)                                   -- Anna plays, Bo gets it, Cid is offline
Mock.SetOnline(bus, "Anna", false); Mock.Pump(bus)
Mock.SetOnline(bus, "Cid", true); Mock.Pump(bus)
check("Cid got Anna's turn from Bo", game(cid, id3).turn == 2)
playTurn(bo, id3)
playTurn(cid, id3)
Mock.SetOnline(bus, "Anna", true); Mock.Pump(bus)
check("Anna caught up on Bo's and Cid's turns", g3.turn == 4)
check("all three copies agree", sameSheets(anna, bo, id3) and sameSheets(anna, cid, id3))

---------------------------------------------------------------------------
print("5. Cid leaves; the game finishes for Anna and Bo")
cid.ns.Guild:Leave(game(cid, id3))
Mock.Pump(bus)
check("Anna knows Cid left", anna.ns.Guild:HasLeft(g3, 3))
local guard = 0
while g3.status == "active" do
    guard = guard + 1
    assert(guard < 100, "game did not finish")
    if anna.ns.Games:IsMyTurn(g3) then playTurn(anna, id3) else playTurn(bo, id3) end
end
check("game over for Anna", g3.status == "over")
check("game over for Bo", game(bo, id3).status == "over")
check("Anna and Bo agree on the final sheets", sameSheets(anna, bo, id3))
check("Cid's sheet is full of strikes", anna.ns.Rules.IsSheetFull(g3.sheets[3]))
check("stats recorded for Anna", anna.ns.db.stats.guild.played >= 1)
do
    local vs = anna.ns.db.stats.vs or {}
    local n = 0
    for _, r in pairs(vs) do n = n + 1; check("head-to-head adds up", r.won + r.lost <= r.played and r.played >= 1) end
    check("Anna has a head-to-head record", n >= 1)
end

---------------------------------------------------------------------------
print("6. Declined invitation cancels a 2-player game")
local g4 = bo.ns.Guild:CreateGame({ R(bo, anna) })
Mock.Pump(bus)
anna.ns.Guild:Answer(game(anna, g4.id), false)
Mock.Pump(bus)
check("Bo's game is cancelled", g4.status == "cancelled")
check("Anna's copy is hidden", game(anna, g4.id).hidden == true)

---------------------------------------------------------------------------
print("7. Invitation to someone offline arrives when they log in")
Mock.SetOnline(bus, "Cid", false); Mock.Pump(bus)
local g5 = anna.ns.Guild:CreateGame({ R(anna, cid) })
Mock.Pump(bus)
check("Cid has no invitation while offline", game(cid, g5.id) == nil)
Mock.SetOnline(bus, "Cid", true); Mock.Pump(bus)
check("Cid got the invitation after logging in", game(cid, g5.id) ~= nil and cid.ns.Games:IsInvite(game(cid, g5.id)))

---------------------------------------------------------------------------
print("8. Bin icon: decline an invitation, withdraw from a waiting game")
local g6 = anna.ns.Guild:CreateGame({ R(anna, bo), R(anna, cid) })
Mock.Pump(bus)
cid.ns.UI:RemoveGame(game(cid, g6.id))                 -- Cid declines with the bin
Mock.Pump(bus)
check("Cid's invitation is gone from his list", game(cid, g6.id).hidden == true)
anna.ns.UI:RemoveGame(g6)                              -- Anna (creator) withdraws while waiting for Bo
Mock.Pump(bus)
bo.ns.Guild:Answer(game(bo, g6.id), true)
Mock.Pump(bus)
check("game cancelled: only Bo would be left", game(bo, g6.id).status == "cancelled")
check("Anna's own list no longer shows it", g6.hidden == true)
anna.ns:ToggleMainWindow(); anna.ns:ToggleMainWindow()
anna.ns.UI:ShowStart()
check("Anna's start screen title for Bo's view says You", bo.ns.Games:Title(game(bo, g6.id)):find("You") ~= nil)

---------------------------------------------------------------------------
print("9. Invite list: only players with Yatzy, other versions greyed out")
local dan = Mock.NewClient(bus, "Dan", "CAMWOWEU4Realm6PvP", "Oldie")
dan.ns.version = "0.4.0"                               -- Dan runs an older version
local eve = { short = "Eve" }                           -- Eve is in the guild but has no addon
bus.members[#bus.members + 1] = { short = "Eve", online = true }
Mock.Pump(bus)
anna.ns:ToggleMainWindow(); Mock.Pump(bus)
anna.ns.InviteDialog:Open()
Mock.Pump(bus)
local seen = {}
for _, m in ipairs(anna.ns.InviteDialog:Candidates()) do seen[anna.ns.Guild:Key(m.name)] = m end
check("Bo listed (has Yatzy)", seen.bo ~= nil and seen.bo.compatible)
check("Cid listed (has Yatzy)", seen.cid ~= nil and seen.cid.compatible)
check("Dan listed but marked as another version", seen.dan ~= nil and not seen.dan.compatible and seen.dan.version == "0.4.0")
check("Eve (no addon) not listed", seen.eve == nil)
anna.ns.InviteDialog:Close()

---------------------------------------------------------------------------
print("10. A Yatzy while my window is closed pops up on the screen (once)")
if anna.ns.mainWindow:IsShown() then anna.ns:ToggleMainWindow() end
check("it's Bo's turn in game 1", bo.ns.Games:IsMyTurn(bg))
if not bo.ns.mainWindow:IsShown() then bo.ns:ToggleMainWindow() end
bo.ns.UI:ShowGame(id); Mock.Pump(bus)               -- Bo has the game open (to be able to score)
bg.dice, bg.held, bg.rollsUsed = { 6, 6, 6, 6, 6 }, { false, false, false, false, false }, 1
bo.ns.Guild:SendLiveRoll(bg)
Mock.Pump(bus)
local sc = anna.ns.Board.screenCelebration
check("Anna sees the big YATZY! on screen", sc ~= nil and sc._shown)
local shownTurn = g.yatzyShown
for _ = 1, 100 do if sc and sc._scripts.OnUpdate then sc._scripts.OnUpdate(sc, 0.1) end end
check("the popup goes away by itself", sc and not sc._shown)
bo.ns.Play:Score("yatzy")                      -- Bo writes the 50; the turn reaches Anna
Mock.Pump(bus)
check("Bo's Yatzy turn reached Anna", g.sheets[2].yatzy == 50)
check("no second popup for the same turn", g.yatzyShown == shownTurn and not sc._shown)

---------------------------------------------------------------------------
print("11. No false YATZY! when someone scores right after their roll (bug from 0.7.x)")
playTurn(anna, id)                                   -- Anna's turn, then it's Bo's again
anna.ns:ToggleMainWindow(); Mock.Pump(bus)
if not anna.ns.mainWindow:IsShown() then anna.ns:ToggleMainWindow() end
anna.ns.UI:ShowGame(id); Mock.Pump(bus)              -- Anna is watching the game
bo.ns.UI:ShowGame(id); Mock.Pump(bus)
check("it's Bo's turn again", bo.ns.Games:IsMyTurn(bg))
local before = g.yatzyShown
bg.dice, bg.held, bg.rollsUsed = { 2, 3, 3, 5, 6 }, { false, false, false, false, false }, 3
bo.ns.Guild:SendLiveRoll(bg)                         -- Bo's last roll (not a Yatzy) ...
for _, cat in ipairs(bo.ns.Rules.CATEGORIES) do       -- ... and he scores immediately
    if bo.ns.Rules.CanScore(bg, cat.id) then bo.ns.Play:Score(cat.id); break end
end
Mock.Pump(bus)
check("no YATZY! popup for Anna", g.yatzyShown == before and not anna.ns.Board.celebration._shown)
check("the turn still arrived", sameSheets(anna, bo, id))

---------------------------------------------------------------------------
print("12. Saved dice show up for the others right away, not only with the next roll")
playTurn(anna, id)                                   -- Bo's turn again
bo.ns.UI:ShowGame(id); anna.ns.UI:ShowGame(id); Mock.Pump(bus)
bo.ns.Play:Roll(); Mock.Pump(bus)
bo.ns.Play:ToggleHold(2); bo.ns.Play:ToggleHold(4); Mock.Pump(bus)
check("Anna sees Bo's saved dice before his next roll", g.held[2] and g.held[4] and not g.held[1])
local beforeMsgs = bus.sent
bo.ns.Play:ToggleHold(4); bo.ns.Play:ToggleHold(4); bo.ns.Play:ToggleHold(4); Mock.Pump(bus)
check("quick clicks go as one message", bus.sent - beforeMsgs == 1)
check("putting a die back shows too", not g.held[4])
bo.ns.Play:Roll(); Mock.Pump(bus)
check("the roll keeps the saved die", g.held[2] and g.dice[2] == bg.dice[2] and g.rollsUsed == 2)

---------------------------------------------------------------------------
print("13. A Yatzy in a guild game is announced in guild chat, by the roller only, once")
do
    local yatzy = { dice = { 6, 6, 6, 6, 6 }, turn = bg.turn, seat = bg.me, rollNo = 1 }
    bo.ns.Play:AfterRoll(bg, false, yatzy)
    bo.ns.Play:AfterRoll(bg, false, yatzy)                 -- same turn again: no second post
    anna.ns.Play:AfterRoll(g, true, { dice = yatzy.dice, turn = g.turn, seat = yatzy.seat, rollNo = 1 })
    check("Bo posted one line in guild chat", #bo.guildChat == 1 and bo.guildChat[1] == "GUILD: YATZYYY")
    check("Anna (watching) posted nothing", #anna.guildChat == 0)
    bo.ns.db.options.announceYatzy = false
    bg.yatzyAnnounced = nil
    bo.ns.Play:AfterRoll(bg, false, yatzy)
    check("setting off: nothing posted", #bo.guildChat == 1)
    bo.ns.db.options.announceYatzy = true
    local solo = bo.ns.Games:NewVsComputer()
    bo.ns.Play:AfterRoll(solo, false, { dice = yatzy.dice, turn = solo.turn, seat = solo.me, rollNo = 1 })
    check("vs the computer: nothing posted", #bo.guildChat == 1)
end

---------------------------------------------------------------------------
print("14. Six players (long names), everyone gets the game, turns go round")
do
    local fia = Mock.NewClient(bus, "Fiaberenika", "CAMWOWEU5Realm6PvP", "Illoyaladvisor")
    local gus = Mock.NewClient(bus, "Gustavsson", "CAMWOWEU4Realm6PvP", "Fatherghouliath")
    local hal = Mock.NewClient(bus, "Halvardsen", "CAMWOWEU5Realm6PvP", "Warrwarrwarr")
    Mock.Pump(bus)
    local others = { bo, cid, fia, gus, hal }
    local names = {}
    for i, c in ipairs(others) do names[i] = R(anna, c) end
    local g6p = anna.ns.Guild:CreateGame(names)
    local id6 = g6p.id
    local msgLen = #("S:*:" .. table.concat({ anna.ns.Guild:StateMessage(g6p) }, ":"))
    check(("the invitation fits in one message (%d of 250 characters)"):format(msgLen), msgLen <= 250)
    Mock.Pump(bus)
    local all = true
    for _, c in ipairs(others) do
        local cg = game(c, id6)
        if not cg then all = false else c.ns.Guild:Answer(cg, true) end
        Mock.Pump(bus)
    end
    check("all five invited players got the invitation", all)
    check("the 6-player game started", g6p.status == "active" and #g6p.players == 6)
    -- one full round: every player plays a turn
    local everyone = { anna, bo, cid, fia, gus, hal }
    for _, c in ipairs(everyone) do playTurn(c, id6) end
    local agree = true
    for _, c in ipairs(others) do
        local cg = game(c, id6)
        if not cg or cg.turn ~= g6p.turn then agree = false end
    end
    check("after one round all six copies are on the same turn", agree and g6p.turn == 7)
    check("the sheet is wider for 6 players", anna.ns.Sheet:WidthFor(g6p) == 406)
end

---------------------------------------------------------------------------
print("15. Removed games stay removed; the login notice only counts ongoing games")
do
    -- Anna removes the first game (Bo still has it and syncs it back when they meet)
    anna.ns.Games:Remove(id)
    Mock.SetOnline(bus, "Bo", false); Mock.Pump(bus)
    Mock.SetOnline(bus, "Bo", true); Mock.Pump(bus)
    check("a removed game doesn't come back from Bo", game(anna, id) == nil)
    -- Anna leaves the 3-player game: hidden, not counted
    local left = game(anna, id3)
    if left and left.status == "active" then anna.ns.Guild:Leave(left) end
    Mock.Pump(bus)
    -- Count what the login notice would mention
    local ongoing = anna.ns.Games:Ongoing()
    local hiddenCounted = false
    for _, og in ipairs(ongoing) do if og.hidden or og.id == id then hiddenCounted = true end end
    check("left and removed games are not 'ongoing'", not hiddenCounted)
    anna.chat = ""
    for _, og in ipairs(ongoing) do og.alertedTurn = nil end
    anna.ns.Guild:LoginSummary()
    local mineNow = 0
    for _, og in ipairs(ongoing) do if anna.ns.Games:IsMyTurn(og) then mineNow = mineNow + 1 end end
    if mineNow == 1 then
        check("one game: just 'Your turn vs ...'", anna.chat:find("Your turn vs ", 1, true) ~= nil and not anna.chat:find("games", 1, true))
    elseif mineNow > 1 then
        check("several games: count plus who", anna.chat:find(("Your turn in %d games: vs "):format(mineNow), 1, true) ~= nil)
    else
        check("no game waiting: no turn notice", not anna.chat:find("Your turn", 1, true))
    end
    anna.chat = ""
    anna.ns.Guild:LoginSummary()
    check("not told twice about the same turn", not anna.chat:find("Your turn", 1, true))
end

---------------------------------------------------------------------------
print("16. Full names everywhere, first names in the score sheet columns")
do
    local g6 = game(anna, id3) or g3
    local boSeat
    for seat, n in ipairs(g6.players) do if anna.ns.Guild:SameName(n, R(anna, bo)) then boSeat = seat end end
    check("full name in the game ('Bo Ghouliath')", anna.ns.Games:PlayerName(g6, boSeat) == "Bo Ghouliath")
    check("first name on the sheet ('Bo')", anna.ns.Games:PlayerName(g6, boSeat, true) == "Bo")
    check("invite list shows the full name", anna.ns.Guild:Short(R(anna, bo)) == "Bo Ghouliath")
end

---------------------------------------------------------------------------
print("17. Everyone is told when someone accepts, declines, withdraws or leaves")
do
    Mock.SetOnline(bus, "Bo", true); Mock.SetOnline(bus, "Cid", true); Mock.Pump(bus)
    -- three players: Bo declines, Cid accepts -> the game starts with Anna and Cid
    local g = anna.ns.Guild:CreateGame({ R(anna, bo), R(anna, cid) })
    local gid = g.id
    Mock.Pump(bus)
    anna.chat, cid.chat = "", ""
    bo.ns.Guild:Answer(game(bo, gid), false); Mock.Pump(bus)
    check("Anna is told Bo declined", anna.chat:find("Bo Ghouliath declined.", 1, true) ~= nil)
    check("...and who she's still waiting for", anna.chat:find("Still waiting for Cid", 1, true) ~= nil)
    check("Cid (invited too) is told as well", cid.chat:find("Bo Ghouliath declined.", 1, true) ~= nil)
    check("Bo isn't told about his own answer", not (bo.chat or ""):find("Bo Ghouliath declined", 1, true))
    anna.chat = ""
    cid.ns.Guild:Answer(game(cid, gid), true); Mock.Pump(bus)
    check("Anna is told Cid accepted", anna.chat:find("Cid accepted.", 1, true) ~= nil)
    check("...and that the game started without Bo", anna.chat:find("The game has started: You, Cid.", 1, true) ~= nil)
    check("the game is running for both", game(anna, gid).status == "active" and game(cid, gid).status == "active")
    -- Cid leaves: Anna is told her turns are skipped
    anna.chat = ""
    cid.ns.Guild:Leave(game(cid, gid)); Mock.Pump(bus)
    check("Anna is told Cid left", anna.chat:find("Cid left the game; their turns are skipped.", 1, true) ~= nil)

    -- two players: Bo declines -> cancelled, and Anna is told why
    local g2 = anna.ns.Guild:CreateGame({ R(anna, bo) })
    Mock.Pump(bus)
    anna.chat = ""
    bo.ns.Guild:Answer(game(bo, g2.id), false); Mock.Pump(bus)
    check("a 2-player game is cancelled when the other declines", game(anna, g2.id).status == "cancelled")
    check("Anna is told it's cancelled", anna.chat:find("The game is cancelled: not enough players accepted.", 1, true) ~= nil)

    -- the creator withdraws before the others answered: the others are told
    local g3w = anna.ns.Guild:CreateGame({ R(anna, bo), R(anna, cid) })
    Mock.Pump(bus)
    bo.chat = ""
    anna.ns.Guild:Leave(g3w); Mock.Pump(bus)
    check("Bo is told Anna withdrew", (bo.chat or ""):find("Anna Berm withdrew from the game.", 1, true) ~= nil)
end

---------------------------------------------------------------------------
print("18. Start now / invitations that run out: everyone ends up with the creator's player list")
do
    local function seats(c, gid)
        local cg = game(c, gid)
        return cg and cg.players and #cg.players or 0
    end
    -- a) Bo accepts, Cid doesn't answer, Anna starts now
    local g = anna.ns.Guild:CreateGame({ R(anna, bo), R(anna, cid) })
    local gid = g.id
    Mock.Pump(bus)
    check("Start now isn't offered before anyone accepted", not anna.ns.Guild:CanStartNow(g))
    bo.ns.Guild:Answer(game(bo, gid), true); Mock.Pump(bus)
    check("Start now is offered to the creator once someone accepted", anna.ns.Guild:CanStartNow(g))
    check("...but not to the others", not bo.ns.Guild:CanStartNow(game(bo, gid)))
    bo.chat, cid.chat = "", ""
    anna.ns.Guild:StartNow(g); Mock.Pump(bus)
    check("the game starts with Anna and Bo", g.status == "active" and seats(anna, gid) == 2 and seats(bo, gid) == 2)
    check("Bo is told Cid didn't answer in time", bo.chat:find("Cid didn't answer in time", 1, true) ~= nil)
    check("Cid's invitation is gone and he is told", game(cid, gid).hidden == true
        and cid.chat:find("started the game without you", 1, true) ~= nil and not cid.ns.Games:IsInvite(game(cid, gid)))
    check("Cid can't accept afterwards", (function() cid.ns.Guild:Answer(game(cid, gid), true); Mock.Pump(bus)
        return seats(anna, gid) == 2 and game(anna, gid).answers:sub(3, 3) == "X" end)())

    -- b) the race: Cid accepts at the same moment as Anna starts without him
    local r = anna.ns.Guild:CreateGame({ R(anna, bo), R(anna, cid) })
    local rid = r.id
    Mock.Pump(bus)
    bo.ns.Guild:Answer(game(bo, rid), true); Mock.Pump(bus)
    cid.ns.Guild:Answer(game(cid, rid), true)          -- not delivered yet...
    anna.ns.Guild:StartNow(r)                          -- ...when Anna starts
    Mock.Pump(bus)
    check("after the race every copy has the same two players",
        seats(anna, rid) == 2 and seats(bo, rid) == 2 and game(anna, rid).answers == game(bo, rid).answers
        and game(cid, rid).answers == game(anna, rid).answers)
    check("Cid is out on his own copy too (not a third player)", game(cid, rid).hidden == true
        and not cid.ns.Games:IsMyTurn(game(cid, rid)))
    playTurn(anna, rid)
    check("play goes on normally after the race", game(bo, rid).turn == 2 and bo.ns.Games:IsMyTurn(game(bo, rid)))
    check("...and Cid's copy follows without him", game(cid, rid).turn == 2 and not cid.ns.Games:IsMyTurn(game(cid, rid)))

    -- c) nobody answers for 7 days: the invitation runs out
    local e = anna.ns.Guild:CreateGame({ R(anna, bo) })
    Mock.Pump(bus)
    e.created = e.created - 8 * 86400
    anna.chat = ""
    anna.ns.Guild:CloseExpired(); Mock.Pump(bus)
    check("an old unanswered invitation runs out (cancelled: nobody accepted)", e.status == "cancelled")
    check("Anna is told", anna.chat:find("ran out after 7 days", 1, true) ~= nil)
    check("Bo's invitation is gone", not bo.ns.Games:IsInvite(game(bo, e.id)))
end

---------------------------------------------------------------------------
print("19. Random turn order: different from game to game, the same on every copy")
do
    for _, c in ipairs({ anna, bo, cid }) do c.ns.Guild.ShuffleFor = c.realShuffle end
    local firstSeats, agree = {}, true
    for _ = 1, 12 do
        local g = anna.ns.Guild:CreateGame({ R(anna, bo), R(anna, cid) })
        Mock.Pump(bus)
        bo.ns.Guild:Answer(game(bo, g.id), true)
        cid.ns.Guild:Answer(game(cid, g.id), true)
        Mock.Pump(bus)
        local ga, gb, gc = game(anna, g.id), game(bo, g.id), game(cid, g.id)
        -- the same order everywhere: each copy's "me" points at a different seat, and
        -- the first player is the same person on all three
        local first = function(c, cg) return c.ns.Guild:FirstName(cg.players[1]) end
        if not (ga.me ~= gb.me and gb.me ~= gc.me and ga.me ~= gc.me
                and first(anna, ga) == first(bo, gb) and first(bo, gb) == first(cid, gc)) then agree = false end
        firstSeats[first(anna, ga)] = true
        for _, c in ipairs({ anna, bo, cid }) do
            local cg = game(c, g.id)
            if cg then c.ns.Guild:Leave(cg) end
        end
        Mock.Pump(bus)
    end
    local starters = 0
    for _ in pairs(firstSeats) do starters = starters + 1 end
    check("all copies agree on the order", agree)
    check("different players start different games (" .. starters .. " of 3 started)", starters >= 2)
end

---------------------------------------------------------------------------
print("20. Fast games: time limit, the computer plays a late turn, poke, invitations run out")
do
    for _, c in ipairs({ anna, bo, cid }) do c.ns.Guild.ShuffleFor = function() end end   -- Anna, Bo, Cid in that order
    Mock.SetOnline(bus, "Bo", true); Mock.SetOnline(bus, "Cid", true); Mock.Pump(bus)
    local function tickAll(...) for _, c in ipairs({ ... }) do c.ns.Fast:Tick() end; Mock.Pump(bus) end
    local g = anna.ns.Guild:CreateGame({ R(anna, bo), R(anna, cid) }, { fast = true })
    local id = g.id
    Mock.Pump(bus)
    check("the invitation says it's a fast game", game(bo, id).fast == true and game(cid, id).fast == true)
    bo.ns.Guild:Answer(game(bo, id), true); cid.ns.Guild:Answer(game(cid, id), true); Mock.Pump(bus)
    check("fast game started", g.status == "active" and anna.ns.Fast:TimeLeft(g) > 590)

    -- a) Anna is online but doesn't play: her own client plays for her at the deadline
    anna.chat = ""
    bus.time = bus.time + 601
    check("Anna's buttons are locked when her time is up", anna.ns.Fast:TimeUp(g))
    tickAll(bo, cid)
    check("the others wait (Anna's own client goes first)", g.turn == 1 and game(bo, id).turn == 1)
    tickAll(anna)
    check("the computer played Anna's turn, on every copy",
        g.turn == 2 and game(bo, id).turn == 2 and game(cid, id).turn == 2)
    check("Anna is told", anna.chat:find("Time's up for you", 1, true) ~= nil)
    check("the others are told too", (bo.chat or ""):find("Time's up for Anna", 1, true) ~= nil)

    -- b) Bo is offline: Cid (next online after Bo) plays Bo's turn, 15 s after the deadline
    Mock.SetOnline(bus, "Bo", false); Mock.Pump(bus)
    bus.time = bus.time + 601
    tickAll(anna, cid)
    check("nobody plays before the 15 s grace", g.turn == 2)
    bus.time = bus.time + 20
    tickAll(anna, cid)
    check("Cid played Bo's turn for him", g.turn == 3 and game(cid, id).turn == 3)
    Mock.SetOnline(bus, "Bo", true); Mock.Pump(bus)
    check("Bo catches up when he logs in", game(bo, id).turn == 3)
    local same = true
    for seat = 1, 3 do
        for k, v in pairs(g.sheets[seat]) do if game(bo, id).sheets[seat][k] ~= v or game(cid, id).sheets[seat][k] ~= v then same = false end end
    end
    check("the computer turns are identical on every copy", same)

    -- c) poke: reaches only the player whose turn it is, once per turn
    cid.chat, bo.chat = "", ""
    check("Anna can poke Cid", anna.ns.Fast:CanPoke(g))
    anna.ns.Fast:Poke(g); Mock.Pump(bus)
    check("Cid is poked", cid.chat:find("Anna Berm poked you", 1, true) ~= nil)
    check("Bo (not his turn) isn't", not bo.chat:find("poked you", 1, true))
    check("Anna can't poke twice in the same turn", not anna.ns.Fast:CanPoke(g))
    check("Cid can't poke himself", not cid.ns.Fast:CanPoke(game(cid, id)))

    -- d) a playing player's own turn just goes on: no timeout
    playTurn(cid, id)
    check("a normal turn resets the clock", g.turn == 4 and anna.ns.Fast:TimeLeft(g) > 590)

    -- e) a fast invitation nobody answers runs out after 5 minutes
    local e = anna.ns.Guild:CreateGame({ R(anna, bo) }, { fast = true })
    Mock.Pump(bus)
    bus.time = bus.time + 301
    tickAll(anna)
    check("an unanswered fast invitation runs out after 5 minutes", e.status == "cancelled")
end

---------------------------------------------------------------------------
print("21. The 'Your turn!' box at the top of the screen")
do
    local g = anna.ns.Guild:CreateGame({ R(anna, bo) })
    Mock.Pump(bus)
    bo.ns.Guild:Answer(game(bo, g.id), true); Mock.Pump(bus)
    local B = anna.ns.TurnBanner
    if anna.ns.mainWindow:IsShown() then anna.ns:ToggleMainWindow() end
    B:Update()
    check("shown while it's my turn and the window is closed", B.frame:IsShown())
    check("it points at a game where it's my turn", B.game and anna.ns.Games:IsMyTurn(B.game))
    local opened = B.game
    B:OpenGame(); B:Update()
    check("clicking it opens that game", anna.ns.Play:IsShowing(opened))
    check("...and the box no longer points at it (only other waiting games, if any)",
        not B.frame:IsShown() or B.game ~= opened)
    anna.ns:ToggleMainWindow(); B:Update()
    check("closing the window brings it back", B.frame:IsShown())
    B.dismissed = B.key; B:Update()
    check("the x hides it until the next turn", not B.frame:IsShown())
end

---------------------------------------------------------------------------
print("22. Backgammon vs a guild member: invite, opening roll, turns, live moves, catch-up, fast, giving up")
do
    Mock.SetOnline(bus, "Anna", true); Mock.SetOnline(bus, "Bo", true); Mock.Pump(bus)
    -- run the board's animations (flying checkers, rolling dice) until they're done
    local function settle(c)
        local B = c.ns.BGBoard
        for _ = 1, 2000 do
            local busy = B.board and B:Busy()
            if busy then B.board:GetScript("OnUpdate")(B.board, 0.1) end
            local hadTimers = #c.timers > 0
            Mock.Pump(bus)
            if not busy and not hadTimers then return end
        end
        error("board never settled")
    end
    -- one whole turn as `c`, through the window: roll, move checker by checker, Done
    local function bgTurn(c, gid, keepOpen)
        local ns = c.ns
        ns.UI:ShowGame(gid); settle(c)
        local gg = game(c, gid)
        assert(ns.Games:IsMyTurn(gg), c.short .. " expected its backgammon turn")
        if not gg.dice then ns.BGPlay:Roll(); settle(c) end
        while #ns.BG.Legal(gg) > 0 do
            local m = ns.BG.Legal(gg)[1]
            ns.BGPlay:Move({ { from = m.from, to = m.to } }); settle(c)
        end
        ns.BGPlay:Done(); settle(c)
        if not keepOpen then ns.BGBoard.window:Hide() end
    end
    local function sameBoard(a, b, gid)
        local ga, gb = game(a, gid), game(b, gid)
        return ga and gb and ga.turn == gb.turn and a.ns.BG.BoardKey(ga.board) == b.ns.BG.BoardKey(gb.board)
    end

    check("versions before 0.10 can't read backgammon messages (one-letter kinds only)",
        ("BS:*:r1:Anna:Anna,Bo:Y?:NN:0"):match("^(%a):([^:]*):?(.*)$") == nil)

    -- a) invitation and start
    local g = anna.ns.Guild:CreateGame({ R(anna, bo) }, { game = "backgammon" })
    local gid = g.id
    check("backgammon invitation needs exactly one other player",
        anna.ns.Guild:CreateGame({ R(anna, bo), R(anna, cid) }, { game = "backgammon" }) == nil)
    bo.chat = ""
    Mock.Pump(bus)
    local b = game(bo, gid)
    check("Bo got a backgammon invitation", b and b.game == "backgammon" and bo.ns.Games:IsInvite(b))
    check("...and was told which game", bo.chat:find("game of Backgammon", 1, true) ~= nil)
    check("Cid (not invited) has no copy", game(cid, gid) == nil)
    bo.ns.Guild:Answer(b, true); Mock.Pump(bus)
    check("started on both copies", g.status == "active" and b.status == "active")
    check("2 seats, each knows its own", g.me ~= b.me and #g.players == 2)
    check("the same opening roll on both copies", g.opening[1] == b.opening[1] and g.opening[2] == b.opening[2]
        and g.first == b.first and g.opening[1] ~= g.opening[2])
    check("games list title", anna.ns.UI:RowTitle(g) == "Backgammon vs Bo Ghouliath")

    -- b) turns while both online; the other one sees the moves live, before Done
    local function current() return anna.ns.Games:IsMyTurn(g) and anna or bo end
    local first = current()
    local other = first == anna and bo or anna
    other.ns.UI:ShowGame(gid); settle(other)             -- the other player watches
    local fg = game(first, gid)
    first.ns.UI:ShowGame(gid); settle(first)
    local m = first.ns.BG.Legal(fg)[1]
    first.ns.BGPlay:Move({ { from = m.from, to = m.to } }); settle(first); settle(other)
    check("the watching player sees the first move live",
        #game(other, gid).moves == 1 and sameBoard(first, other, gid))
    first.ns.BGPlay:Undo(); settle(first); settle(other)
    check("...and the undo too", #game(other, gid).moves == 0 and sameBoard(first, other, gid))
    bgTurn(first, gid, true)
    settle(other)
    check("after Done: the turn arrived, boards agree", g.turn == 2 and b.turn == 2 and sameBoard(anna, bo, gid))
    other.ns.BGBoard.window:Hide()
    for _ = 1, 4 do
        bgTurn(current(), gid)
        Mock.Pump(bus)
    end
    check("6 turns later both copies agree", g.turn == 6 and sameBoard(anna, bo, gid))

    -- c) Bo offline: Anna plays her turn; Bo catches up when he logs in
    if not anna.ns.Games:IsMyTurn(g) then bgTurn(bo, gid); Mock.Pump(bus) end
    Mock.SetOnline(bus, "Bo", false); Mock.Pump(bus)
    local before = b.turn
    bgTurn(anna, gid)
    check("Bo didn't get it while offline", b.turn == before)
    Mock.SetOnline(bus, "Bo", true); Mock.Pump(bus)
    check("Bo caught up", sameBoard(anna, bo, gid))
    bo.chat = ""
    check("and it's his turn", bo.ns.Games:IsMyTurn(b))

    -- d) play to the end: both copies end the same way, with stats
    local guard = 0
    while g.status == "active" and guard < 800 do
        guard = guard + 1
        bgTurn(current(), gid)
        Mock.Pump(bus)
    end
    check("the game ended", g.status == "over" and b.status == "over")
    check("the same winner on both copies", g.winner == b.winner and g.winner ~= nil)
    check("stats recorded as a guild game", anna.ns.db.stats.backgammon.guild.played >= 1)

    -- e) fast backgammon: the computer plays a late turn, the same on both copies
    local f = anna.ns.Guild:CreateGame({ R(anna, bo) }, { game = "backgammon", fast = true })
    Mock.Pump(bus)
    bo.ns.Guild:Answer(game(bo, f.id), true); Mock.Pump(bus)
    local fb = game(bo, f.id)
    check("fast backgammon started", f.status == "active" and fb.fast == true)
    local late = anna.ns.Games:IsMyTurn(f) and anna or bo
    local watcher = late == anna and bo or anna
    Mock.SetOnline(bus, late.short, false); Mock.Pump(bus)
    bus.time = bus.time + 601 + 20
    watcher.ns.Fast:Tick(); Mock.Pump(bus)
    check("the other player's client played the late turn", game(watcher, f.id).turn == 2)
    Mock.SetOnline(bus, late.short, true); Mock.Pump(bus)
    check("identical on both copies after catch-up", sameBoard(anna, bo, f.id))
    check("poke works in backgammon", watcher.ns.Fast:CanPoke(game(watcher, f.id)) == false
        and late.ns.Fast:CanPoke(game(late, f.id)))

    -- f) giving up: the other player wins
    anna.chat = ""
    bo.ns.Guild:Leave(fb); Mock.Pump(bus)
    check("Bo gave up: Anna wins on her copy", f.status == "over" and f.winner == f.me)
    check("Anna is told", anna.chat:find("gave up: you win", 1, true) ~= nil)
    check("Bo's copy agrees", fb.status == "over" and fb.winner == f.me)

    -- g) Auto finish: after the checkers have passed each other, both tick it and the game plays itself
    local h = anna.ns.Guild:CreateGame({ R(anna, bo) }, { game = "backgammon" })
    Mock.Pump(bus)
    bo.ns.Guild:Answer(game(bo, h.id), true); Mock.Pump(bus)
    local hb = game(bo, h.id)
    local function aiTurn(c)
        local ns = c.ns
        ns.UI:ShowGame(h.id); settle(c)
        local gg = game(c, h.id)
        if not gg.dice then ns.BGPlay:Roll(); settle(c) end
        for _, mv in ipairs(ns.BGAI.ChooseMoves(gg.board, ns.BG.CurrentPlayer(gg), gg.dice)) do
            ns.BGPlay:Move({ { from = mv.from, to = mv.to } }); settle(c)
        end
        ns.BGPlay:Done(); settle(c)
    end
    local turns = 0
    while h.status == "active" and anna.ns.BG.Contact(h.board) and turns < 300 do
        turns = turns + 1
        aiTurn(anna.ns.Games:IsMyTurn(h) and anna or bo)
        Mock.Pump(bus)
    end
    check("the checkers passed each other before the game ended", h.status == "active" and not anna.ns.BG.Contact(h.board))
    anna.ns.UI:ShowGame(h.id); settle(anna)
    bo.ns.UI:ShowGame(h.id); settle(bo)
    check("the Auto finish box shows for both", anna.ns.BGBoard.autoBox:IsShown() and bo.ns.BGBoard.autoBox:IsShown())
    check("not on yet", not anna.ns.BGPlay:AutoOn(h) and not bo.ns.BGPlay:AutoOn(hb))
    anna.ns.BGPlay:SetAuto(h, true); settle(anna); settle(bo)
    check("Bo learns that Anna ticked it", hb.auto and hb.auto[h.me] == true)
    check("one tick is not enough in a guild game", not bo.ns.BGPlay:AutoOn(hb) and h.status == "active")
    bo.ns.BGPlay:SetAuto(hb, true)
    check("both ticked: faster", bo.ns.BGPlay:Speed(hb) == 2)
    for _ = 1, 400 do
        settle(anna); settle(bo)
        if h.status ~= "active" then break end
    end
    check("the game played itself to the end on both copies", h.status == "over" and hb.status == "over")
    check("with the same winner", h.winner ~= nil and h.winner == hb.winner)
    check("the choice is cleared afterwards", h.auto == nil and hb.auto == nil)
end

---------------------------------------------------------------------------
print("23. Guild mailmen: a turn and an invitation reach a player who is never online together with the sender")
do
    Mock.SetOnline(bus, "Anna", true); Mock.SetOnline(bus, "Bo", true); Mock.Pump(bus)
    local dee = Mock.NewClient(bus, "Dee", "CAMWOWEU4Realm6PvP")       -- a mailman: not in the game
    local eve = Mock.NewClient(bus, "Eve", "CAMWOWEU4Realm6PvP")       -- turned the setting off
    eve.ns.db.options.helpDeliver = false
    Mock.Pump(bus)
    local function parcels(c) local n = 0; for _ in pairs(c.ns.db.mail or {}) do n = n + 1 end; return n end

    local m = anna.ns.Guild:CreateGame({ R(anna, bo) })
    Mock.Pump(bus)
    bo.ns.Guild:Answer(game(bo, m.id), true)
    Mock.Pump(bus)
    check("the mailman keeps a parcel for the game", dee.ns.db.mail and dee.ns.db.mail[m.id] ~= nil)
    check("the mailman has both answers", dee.ns.db.mail[m.id].answers == "YY")
    check("Dee has no game of her own", game(dee, m.id) == nil)
    check("the one who turned it off keeps nothing", parcels(eve) == 0)

    playTurn(anna, m.id); playTurn(bo, m.id)                    -- turns 1 and 2, everyone online
    Mock.SetOnline(bus, "Bo", false); Mock.Pump(bus)
    playTurn(anna, m.id)                                        -- turn 3: Bo is offline
    check("the parcel holds three turns", dee.ns.db.mail[m.id].count == 3)
    Mock.SetOnline(bus, "Anna", false); Mock.Pump(bus)         -- the author logs off
    Mock.SetOnline(bus, "Bo", true); Mock.Pump(bus)
    check("without help Bo would still be waiting", game(bo, m.id).turn == 3)
    bo.ns.Mail:Ask(); Mock.Pump(bus)
    check("Bo got Anna's turn from the mailman", game(bo, m.id).turn == 4)
    Mock.SetOnline(bus, "Anna", true); Mock.Pump(bus)
    check("Anna's copy agrees afterwards", sameSheets(anna, bo, m.id))
    check("the turn Bo got is the real one", game(bo, m.id).sheets[1][game(bo, m.id).history[3].cat] ~= nil)

    -- An invitation to someone who is offline while the sender is gone
    Mock.SetOnline(bus, "Bo", false); Mock.Pump(bus)
    local inv = anna.ns.Guild:CreateGame({ R(anna, bo) })
    Mock.Pump(bus)
    Mock.SetOnline(bus, "Anna", false); Mock.Pump(bus)
    Mock.SetOnline(bus, "Bo", true); Mock.Pump(bus)
    check("no invitation yet", game(bo, inv.id) == nil)
    bo.ns.Mail:Ask(); Mock.Pump(bus)
    check("the mailman delivered the invitation", game(bo, inv.id) ~= nil and bo.ns.Games:IsInvite(game(bo, inv.id)))
    bo.ns.Guild:Answer(game(bo, inv.id), true); Mock.Pump(bus)
    check("Dee heard Bo's answer", dee.ns.db.mail[inv.id].answers == "YY")
    Mock.SetOnline(bus, "Anna", true); Mock.Pump(bus)
    check("Anna learns the answer when she is back", inv.status == "active")

    -- Someone who isn't in the game can't send turns without the mailman marker, nor invent games
    local before = game(bo, m.id).turn
    eve.ns.Comm:Send("*", "T", m.id, "99", "a111111", "")
    Mock.Pump(bus)
    check("turns from an outsider without the marker are ignored", game(bo, m.id).turn == before)
    check("a mailman cannot invent a turn", (function()
        dee.ns.Comm:Send("*", "T", m.id, tostring(before), "zzzzzzzz", "M")
        Mock.Pump(bus)
        return game(bo, m.id).turn == before
    end)())

    -- A backgammon game goes the same way
    Mock.SetOnline(bus, "Bo", false); Mock.Pump(bus)
    local b = anna.ns.Guild:CreateGame({ R(anna, bo) }, { game = "backgammon" })
    Mock.Pump(bus)
    check("the mailman keeps a backgammon parcel too", dee.ns.db.mail[b.id] and dee.ns.db.mail[b.id].game == "backgammon")
    anna.ns.Comm:Send("*", "BT", b.id, "1", "62nhmk;41"); Mock.Pump(bus)
    check("backgammon turns are stored by number", dee.ns.db.mail[b.id].count == 2 and dee.ns.db.mail[b.id].turns[1] == "62nhmk")
    -- A long game: all of it travels in several messages that each fit in one
    local long = {}
    for i = 1, 60 do long[i] = "55abcdefghijkl" end
    anna.ns.Comm:Send("*", "BT", b.id, "3", table.concat(long, ";", 1, 12)); Mock.Pump(bus)
    for i = 0, 3 do anna.ns.Comm:Send("*", "BT", b.id, tostring(15 + i * 12), table.concat(long, ";", 1, 12)) end
    Mock.Pump(bus)
    dee.ns.Mail:SendTurns(b.id, "Bo", 1, dee.ns.db.mail[b.id].count); Mock.Pump(bus)
    check("a long parcel is sent without a 'message too long' error", not (dee.chat or ""):find("too long", 1, true))
end

---------------------------------------------------------------------------
print("24. Replay: a new round with the same players; the first one to press it starts it")
do
    for _, who in ipairs({ "Anna", "Bo", "Cid" }) do Mock.SetOnline(bus, who, true) end
    Mock.Pump(bus)
    local function playOut(id0)
        local ga = game(anna, id0)
        local guard = 0
        while ga.status == "active" do
            guard = guard + 1
            assert(guard < 100, "game did not finish")
            if anna.ns.Games:IsMyTurn(ga) then playTurn(anna, id0) else playTurn(bo, id0) end
        end
    end
    local function alive(c, oldId)
        local n, ids = 0, {}
        for _, x in ipairs(c.ns.Games:All()) do
            if x.replayOf == oldId and not x.hidden and x.status ~= "cancelled" then n = n + 1; ids[#ids + 1] = x.id end
        end
        return n, ids[1]
    end

    -- Cid left game 3 before it ended: only Bo is invited to the replay
    local old = g3
    local names = anna.ns.Games:ReplayNames(old)
    check("the replay invites those who played to the end (not Cid, who left)", #names == 1 and bo.ns.Guild:SameName(names[1], R(anna, bo)))
    local new, how = anna.ns.Games:Replay(old)
    Mock.Pump(bus)
    check("Anna's replay is a new waiting game", how == "new" and new and new.status == "pending" and new.replayOf == old.id)
    local theirs = game(bo, new.id)
    check("Bo got an invitation he can accept or decline", theirs and bo.ns.Games:IsInvite(theirs))
    check("Cid did not", game(cid, new.id) == nil)
    check("Bo's finished game knows the replay has started", game(bo, id3).replayed == new.id)
    local again, how2 = bo.ns.Games:Replay(game(bo, id3))
    check("Bo pressing Replay afterwards starts nothing new", how2 == "existing" and again.id == new.id)
    check("still only one replay", alive(anna, old.id) == 1 and alive(bo, old.id) == 1)
    bo.ns.Guild:Answer(theirs, true); Mock.Pump(bus)
    check("Bo accepts: the new round starts for both", new.status == "active" and theirs.status == "active")
    check("a fresh game with empty score sheets", new.turn == 1 and anna.ns.Rules.Total(new.sheets[1]) == 0)

    -- Declined: nobody has started a live replay any more, the button starts a new one
    local dec = anna.ns.Games:Replay(game(anna, id3))             -- existing (the active one)
    check("an active replay is the one the button goes to", dec.id == new.id)

    -- Two players press Replay at the same moment: only one game survives, the earlier one
    local g7 = anna.ns.Guild:CreateGame({ R(anna, bo) })
    Mock.Pump(bus)
    bo.ns.Guild:Answer(game(bo, g7.id), true); Mock.Pump(bus)
    playOut(g7.id)
    check("a 2-player game is over", g7.status == "over" and game(bo, g7.id).status == "over")
    local a1 = anna.ns.Games:Replay(g7)
    local b1 = bo.ns.Games:Replay(game(bo, g7.id))               -- before Anna's invitation arrives
    Mock.Pump(bus)
    local na, ia = alive(anna, g7.id)
    local nb, ib = alive(bo, g7.id)
    check("exactly one replay game is left on each side", na == 1 and nb == 1)
    local earlier = a1.id < b1.id and a1.id or b1.id
    check("both sides keep the same one (the earlier)", ia == ib and ia == earlier)

    -- Against the computer it starts at once; a full list loses its oldest game
    local done = { kind = "computer", status = "over", id = "x-over1" }      -- (a finished game)
    local c1, how3 = anna.ns.Games:Replay(done)
    check("computer replay: a new running game at once", how3 == "new" and c1.kind == "computer" and c1.status == "active")
    local _, how4 = anna.ns.Games:Replay(done)
    check("pressing it twice makes no second game", how4 == "existing")
    local fillers = {}
    while anna.ns.Games:CanCreate() do fillers[#fillers + 1] = anna.ns.Games:NewVsComputer() end
    local oldest = anna.ns.Games:Oldest()
    local done2 = { kind = "computer", game = "backgammon", status = "over", id = "x-over2" }
    local c2 = anna.ns.Games:Replay(done2)
    check("full list: the new game is made", c2 ~= nil and c2.status == "active" and c2.game == "backgammon")
    local gone = oldest and anna.ns.Games:Get(oldest.id)
    check("the oldest game was removed (a guild game is left) to make room", oldest ~= nil and (gone == nil or gone.hidden == true))
    check("the list is still within the limit", anna.ns.Games:CountActive() <= 10)
    for _, x in ipairs(fillers) do anna.ns.Games:Remove(x.id) end
    anna.ns.Games:Remove(c1.id); anna.ns.Games:Remove(c2.id)
end

---------------------------------------------------------------------------
print("25. A lost turn message (combat in an instance) is found by the regular state check")
do
    for _, who in ipairs({ "Anna", "Bo" }) do Mock.SetOnline(bus, who, true) end
    Mock.Pump(bus)
    local s = anna.ns.Guild:CreateGame({ R(anna, bo) })
    Mock.Pump(bus)
    bo.ns.Guild:Answer(game(bo, s.id), true); Mock.Pump(bus)
    local sb = game(bo, s.id)
    check("(game running for both)", s.status == "active" and sb.status == "active")

    -- Bo's client misses Anna's turn (he is still online in the guild roster)
    bo.online = false
    playTurn(anna, s.id)
    bo.online = true
    check("Bo missed the turn: both wait for each other", s.turn == 2 and sb.turn == 1)
    check("Anna is waiting for Bo, who is online", not anna.ns.Games:IsMyTurn(s))
    anna.ns.Guild:Heartbeat(); Mock.Pump(bus)
    check("Anna's state check brings Bo up to date", sb.turn == 2 and sameSheets(anna, bo, s.id))

    -- The other way round: Bo plays, Anna misses it; Bo's turn is over so the check comes from Anna,
    -- who still thinks it's Bo's turn
    anna.online = false
    playTurn(bo, s.id)
    anna.online = true
    check("Anna missed Bo's turn", s.turn == 2 and sb.turn == 3)
    anna.ns.Guild:Heartbeat(); Mock.Pump(bus)
    check("the one who is behind asks, and gets the turn", s.turn == 3 and sameSheets(anna, bo, s.id))

    -- Messages hidden in combat ("secret" values) are skipped without errors, then recovered
    local secret = true
    bo.env.issecretvalue = function() return secret end
    bo.chat = ""
    playTurn(anna, s.id)
    check("a hidden message is skipped quietly", sb.turn == 3 and not (bo.chat or ""):find("error", 1, true))
    secret = false
    bo.ns.Guild:Heartbeat(true); Mock.Pump(bus)                   -- after combat: Bo checks every game
    check("after combat Bo gets the turn", sb.turn == 4 and sameSheets(anna, bo, s.id))
    bo.env.issecretvalue = nil

    -- The game refuses a message for a while (throttled): it is sent again, in order
    local refusals = 2
    local real = anna.env.C_ChatInfo.SendAddonMessage
    anna.env.C_ChatInfo.SendAddonMessage = function(...)
        if refusals > 0 then refusals = refusals - 1; return 3 end   -- a result code other than 0 = not sent
        return real(...)
    end
    playTurn(bo, s.id); playTurn(anna, s.id)
    anna.env.C_ChatInfo.SendAddonMessage = real
    check("a refused message is tried again and arrives", s.turn == 6 and sb.turn == 6 and sameSheets(anna, bo, s.id))

    -- Equal copies: a state check gets no answer (no endless back and forth)
    local before = bus.sent
    local checks = anna.ns.Guild:Heartbeat(); Mock.Pump(bus)
    check("in sync: one message per game checked, nobody answers", checks >= 1 and bus.sent - before == checks)
end

check("no whisper was ever needed", bus.failed == 0)
print(("%d passed, %d failed  (%d addon messages sent, %d failed)"):format(passed, failed, bus.sent or 0, bus.failed))
if failed > 0 then os.exit(1) end
