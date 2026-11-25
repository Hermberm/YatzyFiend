-- Smoke test: loads the whole addon against a fake ("mock") WoW API and plays
-- a full game vs the computer through the UI code paths.
-- It can't show what things LOOK like, but it catches crashes, typos and nil errors.
-- Run from C:\Yatzy with:  luajit tests/smoke_ui.lua

---------------------------------------------------------------------------
-- Fake WoW API
---------------------------------------------------------------------------
local timers = {}
local allFrames = {}

local function newObject(kind)
    local o = { _shown = true, _scripts = {}, _w = 600, _h = 400, _kind = kind, _scroll = 0, _text = "", _checked = false }
    local methods = {
        GetWidth = function(self) return self._w end,
        GetHeight = function(self) return self._h end,
        SetSize = function(self, w, h) self._w, self._h = w, h end,
        SetWidth = function(self, w) self._w = w end,
        SetHeight = function(self, h) self._h = h end,
        Show = function(self)
            local was = self._shown; self._shown = true
            if not was and self._scripts.OnShow then self._scripts.OnShow(self) end
        end,
        Hide = function(self)
            local was = self._shown; self._shown = false
            if was and self._scripts.OnHide then self._scripts.OnHide(self) end
        end,
        SetShown = function(self, v) if v then self:Show() else self:Hide() end end,
        IsShown = function(self) return self._shown end,
        IsVisible = function(self)
            if not self._shown then return false end
            local p = rawget(self, "_parent")
            return p == nil or p:IsVisible()
        end,
        SetParent = function(self, p) rawset(self, "_parent", p) end,
        GetParent = function(self) return rawget(self, "_parent") end,
        SetScript = function(self, name, fn) self._scripts[name] = fn end,
        HookScript = function(self, name, fn)
            local old = self._scripts[name]
            self._scripts[name] = function(...) if old then old(...) end fn(...) end
        end,
        GetScript = function(self, name) return self._scripts[name] end,
        GetCenter = function() return 100, 100 end,
        GetLeft = function() return 0 end,
        GetBottom = function() return 0 end,
        GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
        GetFrameLevel = function() return 1 end,
        GetStringWidth = function() return 20 end,
        GetText = function(self) return self._text end,
        SetText = function(self, t) self._text = t end,
        IsEnabled = function(self) return self._enabled ~= false end,
        SetEnabled = function(self, v) self._enabled = v end,
        Enable = function(self) self._enabled = true end,
        Disable = function(self) self._enabled = false end,
        Click = function(self, button) if self._scripts.OnClick then self._scripts.OnClick(self, button or "LeftButton") end end,
        CreateTexture = function() return newObject("Texture") end,
        CreateMaskTexture = function() return newObject("MaskTexture") end,
        GetVerticalScroll = function(self) return self._scroll or 0 end,
        SetVerticalScroll = function(self, v) self._scroll = v end,
        GetFont = function() return "font" end,
        GetChecked = function(self) return self._checked end,
        SetChecked = function(self, v) self._checked = v end,
        CreateFontString = function() return newObject("FontString") end,
        CreateAnimationGroup = function() return newObject("AnimationGroup") end,
        CreateAnimation = function() return newObject("Animation") end,
    }
    return setmetatable(o, { __index = function(_, k)
        return methods[k] or function() end      -- every other method: do nothing
    end })
end

CreateFrame = function(kind, name, parent)
    local f = newObject(kind)
    f._parent = parent
    if name then _G[name] = f end
    allFrames[#allFrames + 1] = f
    return f
end
UIParent = newObject("Frame")
Minimap = newObject("Frame")
GameTooltip = newObject("Frame")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) print("[chat] " .. msg) end }
RaidWarningFrame = newObject("Frame")
RaidNotice_AddMessage = function(_, msg) print("[raid warning] " .. msg) end
ChatTypeInfo = { RAID_WARNING = {} }
UISpecialFrames = {}
SlashCmdList = {}
SOUNDKIT = setmetatable({}, { __index = function() return 1 end })
PlaySound = function() end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
tinsert = table.insert
strlower = string.lower
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
unpack = unpack or table.unpack
time = os.time
UnitName = function() return "Tester" end
GetCursorPosition = function() return 0, 0 end
C_Timer = { After = function(delay, fn) timers[#timers + 1] = fn end }

---------------------------------------------------------------------------
-- Load the addon in .toc order
---------------------------------------------------------------------------
local ns = {}
local files = {}
for line in io.lines("Yatzy/Yatzy.toc") do
    if line:match("%.lua%s*$") then files[#files + 1] = line:match("^%s*(.-)%s*$") end
end
for _, file in ipairs(files) do
    assert(loadfile("Yatzy/" .. file))("Yatzy", ns)
end

-- Fire ADDON_LOADED on the addon's event frame
for _, f in ipairs(allFrames) do
    if f._scripts.OnEvent then f._scripts.OnEvent(f, "ADDON_LOADED", "Yatzy") end
end
assert(ns.db and ns.mainWindow, "addon did not initialise")

-- Run pending timers and OnUpdate animations until things settle
local function pump()
    for _ = 1, 500 do
        local busy = false
        local board = ns.Board.frame
        if board._scripts.OnUpdate then board._scripts.OnUpdate(board, 0.1); busy = true end
        if #timers > 0 then
            local run = timers; timers = {}
            for _, fn in ipairs(run) do fn() end
            busy = true
        end
        if not busy then return end
    end
    error("pump: things never settled")
end

---------------------------------------------------------------------------
-- Play
---------------------------------------------------------------------------
local Rules, Games, Play = ns.Rules, ns.Games, ns.Play

-- Who starts a game vs the computer is a coin toss (0.10). Most checks below expect you to
-- start, so the toss is fixed here; the computer-first case is tested on its own.
local realRandom = math.random
local coin = 1
math.random = function(a, b)
    if a == 1 and b == 2 then return coin end
    if b then return realRandom(a, b) end
    if a then return realRandom(a) end
    return realRandom()
end

do  -- the computer starts: it plays its first turn by itself, then it's your turn
    coin = 2
    local cg = Games:NewVsComputer()
    coin = 1
    assert(cg.me == 2 and cg.computer == 1, "computer has the first seat")
    ns:ToggleMainWindow()
    ns.UI:ShowGame(cg.id)
    pump()
    assert(cg.turn == 2 and Games:IsMyTurn(cg), "computer played first, now it's your turn")
    -- totals are secret until the game is over
    local totalCell
    for _, row in ipairs(ns.Sheet.rows) do
        if row.def.kind == "total" then totalCell = row.cells[cg.computer] end
    end
    assert(totalCell.text:GetText() == "–", "the computer's total is hidden (a dash) while the game runs")
    ns:ToggleMainWindow()
    Games:Remove(cg.id)
end

ns:ToggleMainWindow()                 -- open the window
assert(ns.mainWindow:IsShown(), "window should be open")
SlashCmdList.YATZY("help")

local g = Games:NewVsComputer()
ns.UI:ShowGame(g.id)
pump()

local myTurns, guard = 0, 0
while g.status == "active" do
    guard = guard + 1
    assert(guard < 500, "game did not finish")
    if Games:IsMyTurn(g) then
        Play:Roll(); pump()
        Play:ToggleHold(1); Play:ToggleHold(2)
        Play:Roll(); pump()
        Play:Roll(); pump()
        -- write into the best open category (like a player would)
        local best, bestPts
        for _, cat in ipairs(Rules.CATEGORIES) do
            if g.sheets[g.me][cat.id] == nil then
                local pts = Rules.Score(cat.id, g.dice)
                if not bestPts or pts > bestPts then best, bestPts = cat.id, pts end
            end
        end
        -- hover + click the sheet cell, through the sheet code
        for _, row in ipairs(ns.Sheet.rows) do
            if row.def.kind == "cat" and row.def.cat.id == best then
                local cell = row.cells[g.me]
                ns.Sheet:OnCellEnter(cell)
                ns.Sheet:OnCellLeave(cell)
                ns.Sheet:OnCellClick(cell)
            end
        end
        myTurns = myTurns + 1
    end
    pump()
end

assert(myTurns == 15, "expected 15 turns for me, got " .. myTurns)
assert(Rules.IsSheetFull(g.sheets[1]) and Rules.IsSheetFull(g.sheets[2]), "sheets should be full")
assert(ns.db.stats.solo.played == 1, "stats should record one game")
assert(ns.db.stats.solo.counted == 1 and ns.db.stats.solo.total > 0, "final score saved for the average")
local col = ns.Stats:Column(ns.db.stats.solo)
assert(col.played == "1" and col.avg == tostring(ns.db.stats.solo.total), "stats card numbers")
ns.UI:ShowStart()
ns.Stats:Refresh(300)                      -- the mock can't measure positions: give it room
assert(ns.Stats.card:IsShown(), "stats card on the main menu")
ns.Stats:Refresh(40)
assert(not ns.Stats.card:IsShown(), "stats card hides when there's no room")

-- Window closed during the computer's turn: it should finish instantly and alert
local g2 = Games:NewVsComputer()
ns.UI:ShowGame(g2.id)
Play:Roll(); pump()
for _, cat in ipairs(Rules.CATEGORIES) do
    if Rules.CanScore(g2, cat.id) then Play:Score(cat.id); break end
end
ns:ToggleMainWindow()                 -- close
pump()
assert(Games:IsMyTurn(g2), "computer should have finished its turn while the window was closed")

-- Resize: narrow window folds the sheet; wide restores it
ns:ToggleMainWindow(); pump()
ns.UI.body._w = 450; ns.UI:Layout()
assert(ns.UI.sheetOpen == false, "narrow window should fold the sheet")
ns.UI:ToggleSheet()
assert(ns.UI.sheetOpen == true, "tab should open the sheet over the table")
ns.UI.body._w = 900; ns.UI:Layout()
assert(ns.UI.sheetOpen == true, "wide window restores the sheet")
-- a bit smaller: the sheet gets narrower instead of folding in
ns.UI.body._w = 560; ns.UI:Layout()
assert(ns.UI.sheetOpen == true and not ns.UI.narrow, "medium window: table and sheet both shown")
assert(ns.UI.SHEET_W < ns.Sheet:WidthFor(ns.Sheet.widthGame or ns.Sheet.game), "the sheet got narrower")
ns.UI.body._w = 900; ns.UI:Layout()

-- Small table: dice must never end up on top of each other
-- (a die turned any way fits in a circle 1.42 x its size: further apart = no overlap)
do
    local g3 = Games:NewVsComputer()
    ns.UI:ShowGame(g3.id)
    -- the user's usual size (table about 490 x 290), and the smallest table
    for _, size in ipairs({ { 490, 290, full = true }, { 420, 230 }, { 400, 200 } }) do
        ns.Board.frame._w, ns.Board.frame._h = size[1], size[2]
        ns.Board:Relayout()
        if size.full then assert(ns.Board.dieSize == 64, "full-size dice at the usual window size") end
        local need = ns.Board.dieSize * 1.42
        for _ = 1, 30 do
            g3.rollsUsed = 0; g3.held = { false, false, false, false, false }
            Play:Roll(); pump()
            -- a second roll with two dice saved
            g3.held = { true, false, true, false, false }
            Play:Roll(); pump()
            local pos = ns.Board.positions[g3.id]
            local onTable = { 2, 4, 5 }
            for a = 1, #onTable do for b = a + 1, #onTable do
                local p, q = pos[onTable[a]], pos[onTable[b]]
                local d = math.sqrt((p.x - q.x) ^ 2 + (p.y - q.y) ^ 2)
                assert(d >= need - 1, ("dice overlap on a %dx%d table (%.0f < %.0f)"):format(size[1], size[2], d, need))
            end end
        end
    end
    ns.Board.frame._w, ns.Board.frame._h = 600, 400
    ns.Board:Relayout()
end

-- 3rd roll: the dice first lie still (saved ones in the tray), only then glide into the row
do
    local g5 = Games:NewVsComputer()
    ns.UI:ShowGame(g5.id)
    Play:Roll(); pump()
    Play:Roll(); pump()
    g5.held = { true, false, false, false, false }
    Play:Roll()
    local board, phases = ns.Board, {}
    for _ = 1, 200 do
        local fn = board.frame._scripts.OnUpdate
        if not fn or not board.animating then break end
        local ph = board.animating.phase or "throw"
        if phases[#phases] ~= ph then phases[#phases + 1] = ph end
        fn(board.frame, 0.05)
    end
    pump()
    assert(table.concat(phases, ",") == "throw,rest,lineup", "3rd roll: throw, pause, then line up (got " .. table.concat(phases, ",") .. ")")
end

-- Side menu, sound button, celebration, window scale and fold animation
do
    -- run a frame's OnUpdate animation until it stops
    local function runAnim(frame)
        for _ = 1, 200 do
            local fn = frame and frame._scripts.OnUpdate
            if not fn then return end
            fn(frame, 0.05)
        end
    end
    local g4 = Games:NewVsComputer()
    ns.UI:ShowGame(g4.id)
    ns.SideMenu:Open(); runAnim(ns.SideMenu.animator)
    assert(ns.SideMenu:IsOpen(), "side menu should open")
    ns.SideMenu:Close(); runAnim(ns.SideMenu.animator)
    assert(not ns.SideMenu.cover:IsShown(), "side menu should close")
    local levels = {}
    for i = 1, 4 do levels[i] = ns.Sound:NextLevel() end
    assert(levels[1] == "normal" and levels[2] == "high" and levels[3] == "off" and levels[4] == "low",
        "sound button cycles Low -> Normal -> High -> Off -> Low")
    -- Settings (title-bar button): the combat toggle is saved and the panel drops down
    local panel = ns.Settings.panels[1]
    ns.UI.settingsButton:Click()
    assert(panel:IsShown(), "settings drop down")
    local combat = panel.rows[1]
    combat:SetChecked(false); combat:Click()
    assert(ns.db.options.hideInCombat == false, "hide-in-combat toggle saved")
    combat:SetChecked(true); combat:Click()
    assert(ns.db.options.hideInCombat == true, "hide-in-combat back on")
    -- Escape setting: the window leaves / rejoins WoW's Escape list
    local function escListed()
        for _, n in ipairs(UISpecialFrames) do if n == "YatzyMainWindow" then return true end end
        return false
    end
    assert(escListed(), "Escape closes the window by default")
    local esc
    for _, row in ipairs(panel.rows) do if row.opt.key == "escCloses" then esc = row end end
    esc:SetChecked(false); esc:Click()
    assert(ns.db.options.escCloses == false and not escListed(), "Escape setting off")
    esc:SetChecked(true); esc:Click()
    assert(escListed(), "Escape setting back on")
    ns.UI.settingsButton:Click()
    -- Roll button: big "Roll dice" with the rolls left underneath
    assert(ns.Board.rollButton.sub, "roll button has a small second line")
    ns.Board:Celebrate("Five of a kind!"); runAnim(ns.Board.celebration)
    ns.UI:ToggleSheet(); runAnim(ns.Sheet.animator)
    ns.UI:ToggleSheet(); runAnim(ns.Sheet.animator)
    assert(ns.Sheet.slide == 0, "sheet slides back in")
    ns.UI:SetWindowScale(0.7)
    assert(ns.db.window.scale == 0.7, "window scale saved")
    ns.UI:SetWindowScale(1)
end

-- Short window: the sheet scrolls
ns.Sheet.scroll._h = 200
ns.Sheet:ScrollBy(60)
assert(ns.Sheet.scroll:GetVerticalScroll() == 60, "sheet should scroll when it doesn't fit")
assert(ns.Sheet.stickyTop:IsShown() and ns.Sheet.stickyBottom:IsShown(), "names and Total pinned while scrolled")
assert(ns.Sheet.stickyTop.texts[1]:GetText() ~= "", "pinned names are filled in")
ns.Sheet:ScrollBy(-1000)
assert(not ns.Sheet.stickyTop:IsShown() and ns.Sheet.stickyBottom:IsShown(), "at the top: real names, Total still pinned")
ns.Sheet:ScrollBy(1000)
assert(ns.Sheet.stickyTop:IsShown() and not ns.Sheet.stickyBottom:IsShown(), "at the bottom: real Total, names pinned")
ns.Sheet:ScrollBy(-999)
assert(ns.Sheet.scroll:GetVerticalScroll() == 0, "scrolling stops at the top")

ns.UI:ShowStart()
ns.UI:RefreshStart()

-- 0.9.1: small table = smaller tray and Roll button
do
    local Board = ns.Board
    local g = Games:NewVsComputer()
    ns.UI:ShowGame(g.id)
    Board.frame._w, Board.frame._h = 700, 400
    Board:Relayout()
    assert(not Board.compact and Board.tray:GetHeight() == 56, "normal size on a big table")
    Board.frame._w, Board.frame._h = 400, 230
    Board:Relayout()
    assert(Board.compact and Board.tray:GetHeight() == 40 and Board.rollButton:GetHeight() == 40,
        "compact tray and button on a small table")
    assert(Board.tray:GetWidth() + Board.rollButton:GetWidth() + 16 + 24 <= 400, "bottom row fits")
    local x0, x1, y0, y1 = Board:Area()
    assert(y1 > y0, "room for the dice on the small table")
    Board.frame._w, Board.frame._h = 600, 400
    Board:Relayout()
end

-- 0.9.0 features --------------------------------------------------------
do
    local Rules, Sheet, Board = ns.Rules, ns.Sheet, ns.Board
    local g = Games:NewVsComputer()
    ns.UI:ShowGame(g.id)
    if not ns.mainWindow:IsShown() then ns:ToggleMainWindow() end
    pump()

    -- Roll button flashes when my turn starts in the open game (once per turn)
    g.flashedTurn = nil
    Play:FlashMyTurn(g)
    assert(Board.rollButton.flash:IsShown(), "Roll button flashes on my turn")
    Board:StopFlash()
    Play:FlashMyTurn(g)
    assert(not Board.rollButton.flash:IsShown(), "only once per turn")

    -- Strike-out confirmation: a 0-field while another field would score
    Play:Roll(); pump()
    g.dice = { 1, 2, 3, 3, 5 }                  -- Yatzy = 0, Threes = 6
    local yatzyCell
    for _, row in ipairs(Sheet.rows) do
        if row.def.kind == "cat" and row.def.cat.id == "yatzy" then yatzyCell = row.cells[g.me] end
    end
    Sheet:Refresh(g)
    local before = g.turn
    yatzyCell:Click()
    assert(g.turn == before and Sheet.confirm and Sheet.confirm:IsShown(), "asks before striking out Yatzy")
    Sheet.confirm.cover:Click()
    assert(not Sheet.confirm:IsShown() and g.turn == before, "clicking elsewhere cancels")
    yatzyCell:Click()
    Sheet:CloseConfirm()
    -- when nothing scores, no question
    g.dice = { 1, 2, 3, 4, 6 }
    local saved = {}
    for _, cat in ipairs(Rules.CATEGORIES) do
        if Rules.CanScore(g, cat.id) and Rules.Score(cat.id, g.dice) > 0 and cat.id ~= "yatzy" then
            saved[cat.id] = true; g.sheets[g.me][cat.id] = 0
        end
    end
    assert(not Sheet:WouldWaste(yatzyCell), "no question when every open field gives 0")
    for id in pairs(saved) do g.sheets[g.me][id] = nil end

    -- A die put back from the tray never lands on another die
    g.dice = { 1, 2, 3, 4, 5 }; g.rollsUsed = 1; g.held = { false, false, false, false, false }
    local pos = Board.positions[g.id]
    pos[2] = { x = pos[1].x + 5, y = pos[1].y, r = 0 }       -- die 2's old spot is taken by die 1
    Board:Refresh(g)
    local d = math.sqrt((pos[1].x - pos[2].x) ^ 2 + (pos[1].y - pos[2].y) ^ 2)
    assert(d >= Board.dieSize * 1.4, "a die back from the tray gets a free spot")

    -- Detached score sheet: own window, follows the main window, docks back
    Sheet:SetDetached(true)
    assert(Sheet.window and Sheet.window:IsShown(), "detached sheet window shown")
    assert(Sheet.frame:GetParent() == Sheet.window.content, "sheet lives in its own window")
    assert(not Sheet.tab:IsShown(), "no fold tab while detached")
    -- wider window = wider score columns; never narrower than the minimum for the players
    ns.db.sheetWindow.width = 600
    Sheet:FitWindow()
    assert(Sheet.window:GetWidth() == 600, "detached sheet keeps the width you dragged it to")
    Sheet.scroll._w = 560; Sheet:Layout()
    assert(Sheet.colW > 60, "wide detached sheet: wider score columns (" .. tostring(Sheet.colW) .. ")")
    ns.db.sheetWindow.width = 50
    Sheet:FitWindow()
    assert(Sheet.window:GetWidth() >= Sheet:MinWindowWidth(g), "never narrower than the minimum")
    ns.db.sheetWindow.width = nil
    Sheet:FitWindow()
    -- one shared fade: both windows have the same opacity; pointing at either keeps both solid
    local saveFade = ns.UI.ShouldFade
    ns.UI.ShouldFade = function() return true end
    ns.mainWindow.IsMouseOver = function() return false end
    Sheet.window.IsMouseOver = function() return false end
    for _ = 1, 20 do ns.UI:FadeStep(0.1) end
    assert(ns.UI.fadeAlpha < 1, "both fade while moving, mouse away")
    do
        local seen
        Sheet.paper.SetAlpha = function(_, a) seen = a end
        ns.UI:FadeStep(0.1)
        Sheet.paper.SetAlpha = nil
        assert(seen == ns.UI.fadeAlpha and seen < 1, "the paper fades too (it ignores its parents' opacity, so it gets the fade itself)")
    end
    Sheet.window.IsMouseOver = function() return true end
    for _ = 1, 20 do ns.UI:FadeStep(0.1) end
    assert(ns.UI.fadeAlpha == 1, "pointing at the sheet window keeps both solid")
    -- fade strength: Low (default) -> Medium -> High -> Low, each clearer than the one before
    Sheet.window.IsMouseOver = function() return false end
    local alphas = {}
    for i = 1, 3 do
        for _ = 1, 40 do ns.UI:FadeStep(0.1) end
        alphas[i] = ns.UI.fadeAlpha
        ns.UI:NextFadeLevel()
        ns.UI.fadePreviewUntil = 0                -- (skip the 1.5 s preview)
    end
    assert(alphas[1] > alphas[2] and alphas[2] > alphas[3] and alphas[3] > 0, "each fade level is more see-through")
    assert(ns.UI:FadeLevel() == "low", "after three clicks it is back at Low")
    ns.UI:NextFadeLevel()
    assert(ns.UI:FadeTarget() == ns.UI.FADE_ALPHA.medium, "the window shows the new level at once, even with the mouse on it")
    ns.UI.fadePreviewUntil = 0
    ns.db.options.fadeLevel = "low"
    ns.UI.ShouldFade = saveFade
    ns.mainWindow.IsMouseOver, Sheet.window.IsMouseOver = nil, nil
    ns:ToggleMainWindow()
    assert(not Sheet.window:IsShown(), "closing the main window closes the sheet window")
    ns:ToggleMainWindow()
    assert(Sheet.window:IsShown(), "and opens it again")
    ns.UI:ShowStart()
    assert(not Sheet.window:IsShown(), "no sheet window on the start screen")
    ns.UI:ShowGame(g.id)
    Sheet:SetDetached(false)
    assert(not Sheet.window:IsShown() and Sheet.frame:GetParent() == ns.UI.game, "docked back")

    -- Fading: moving in any way or fighting; never on a flight path
    local saveSpeed, saveCombat, saveTaxi = GetUnitSpeed, UnitAffectingCombat, UnitOnTaxi
    GetUnitSpeed = function() return 7 end; UnitAffectingCombat = function() return false end; UnitOnTaxi = function() return false end
    assert(ns.UI:ShouldFade(), "fades while moving (autorun, follow...)")
    UnitOnTaxi = function() return true end
    assert(not ns.UI:ShouldFade(), "no fading on a flight path")
    UnitOnTaxi = function() return false end
    GetUnitSpeed = function() return 0 end
    ns.inCombat = true
    assert(ns.UI:ShouldFade(), "fades in combat while standing still")
    ns.inCombat = false
    assert(not ns.UI:ShouldFade(), "standing still, no combat: solid")
    -- In combat WoW gives "secret" values that error when compared (the 0.9.1 bug)
    local secret = setmetatable({}, { __lt = function() error("attempt to compare a secret number") end,
                                      __le = function() error("attempt to compare a secret number") end })
    local saveSecret = issecretvalue
    GetUnitSpeed = function() return secret end
    UnitOnTaxi = function() return secret end
    issecretvalue = function(v) return v == secret end
    ns.inCombat = true
    assert(ns.UI:ShouldFade(), "combat with secret values: fades, no error")
    ns.inCombat = false
    assert(not ns.UI:ShouldFade(), "secret speed out of combat: no error, counted as not moving")
    issecretvalue = nil                       -- even without the helper: no error
    assert(pcall(ns.UI.ShouldFade, ns.UI), "unreadable values never raise an error")
    issecretvalue = saveSecret
    GetUnitSpeed, UnitAffectingCombat, UnitOnTaxi = saveSpeed, saveCombat, saveTaxi

    -- Turn sound: built-in file unless "Use my own sound files" is on
    local played = {}
    local savePSF = PlaySoundFile
    PlaySoundFile = function(file) played[#played + 1] = file; return true end
    ns.Sound:Play("turn")
    assert(#played == 1 and played[1]:find("YourTurn", 1, true), "built-in turn sound plays")
    savePSF = savePSF; PlaySoundFile = savePSF
end

do  -- game over panel: the winner's line is glowing
    local over = ns.Board.overPanel
    local glowing = 0
    for i, glow in ipairs(over.glows) do if glow:IsShown() then glowing = glowing + 1 end end
    assert(over.lines[1]:GetText():find("—"), "game over lines written (with a proper dash)")
    assert(glowing >= 1 and over.glows[1]:IsShown(), "winner glows on the game over panel")
    -- Replay button on the Yatzy game-over panel: against the computer a new game starts at once
    assert(over.replay:IsShown() and over.replay:GetText() == "Replay", "Replay button on the game over panel")
    local finished
    for _, x in ipairs(ns.Games:All()) do
        if x.kind == "computer" and not x.game and x.status == "over" then finished = x; break end
    end
    assert(finished, "a finished Yatzy game vs the computer")
    ns.UI:ShowGame(finished.id)
    ns.Board.overDismissed, ns.Board.animating = false, false
    ns.Board:Refresh(finished)
    assert(ns.Board.overPanel.replay:IsShown() and ns.Board.overPanel.replay:GetText() == "Replay", "Replay button on the game over panel")
    local before = #ns.Games:All()
    over.replay._scripts.OnClick()
    local new = ns.Games:ReplayTarget(finished)
    assert(new and new.kind == "computer" and new.status == "active" and #ns.Games:All() == before + 1,
        "Replay vs the computer starts a new game")
    assert(ns.Board.game == new, "and opens it")
    ns.UI:ShowGame(finished.id)
    ns.Board.overDismissed, ns.Board.animating = false, false
    ns.Board:Refresh(finished)
    assert(ns.Board.overPanel.replay:GetText() == "Go to replay", "after that the button goes to the replay")
    ns.Games:Remove(new.id); finished.replayed = nil
    ns.UI:ShowGame(finished.id)
end
assert(ns.Board.turnPopup and ns.Board.turnPopup.big:GetText() == "Your turn!", "\"Your turn!\" popup in the title font")

do  -- Backgammon vs the computer: a whole game through the window, board and turn code
    local BG, BGPlay, BGBoard = ns.BG, ns.BGPlay, ns.BGBoard
    local function bgPump()
        for _ = 1, 20000 do
            local busy = false
            local b = BGBoard.board
            if b and BGBoard:Busy() then b._scripts.OnUpdate(b, 0.1); busy = true end
            if #timers > 0 then
                local run = timers; timers = {}
                for _, fn in ipairs(run) do fn() end
                busy = true
            end
            if not busy then return end
        end
        error("bgPump: things never settled")
    end
    local bg = Games:NewBGVsComputer()
    ns.UI:ShowGame(bg.id)
    assert(BGBoard:IsShown() and BGPlay.game == bg, "backgammon opens in its own window")
    assert(ns.UI:RowTitle(bg) == "Backgammon vs Computer", "games list title")
    bgPump()
    local guard, undoTested, myTurns = 0, false, 0
    while bg.status == "active" do
        guard = guard + 1
        assert(guard < 3000, "backgammon game did not finish")
        if Games:IsMyTurn(bg) then
            myTurns = myTurns + 1
            BGPlay:Roll(); bgPump()
            assert(bg.dice, "rolled")
            while true do
                local legal = BG.Legal(bg)
                if #legal == 0 then break end
                local m = legal[1]
                BGBoard:Select(m.from)
                assert(BGBoard.targets[m.to], "a legal move lights up its point")
                BGPlay:Move(BGBoard.targets[m.to]); bgPump()
                if not undoTested then
                    BGPlay:Undo()
                    assert(#bg.moves == 0, "undo takes the move back")
                    undoTested = true
                end
            end
            assert(BG.CanFinish(bg), "Done is allowed when no moves are left")
            BGPlay:Done(); bgPump()
        else
            bgPump()
        end
    end
    assert(myTurns > 5, "played several turns")
    assert(ns.db.stats.backgammon.solo.played == 1, "backgammon stats recorded")
    assert(BGBoard.overPanel:IsShown(), "game over panel")
    assert(BGBoard.overPanel.again:IsShown() and BGBoard.overPanel.again:GetText() == "Replay", "backgammon Replay button")
    do
        local finishedBG, count0 = bg, #Games:All()
        BGBoard.overPanel.again._scripts.OnClick()
        local nb = Games:ReplayTarget(finishedBG)
        assert(nb and nb.game == "backgammon" and nb.status == "active" and #Games:All() == count0 + 1, "backgammon Replay starts a new game")
        Games:Remove(nb.id); finishedBG.replayed = nil
        ns.UI:ShowGame(finishedBG.id)
    end
    local _, result = Games:Describe(bg)
    assert(result == "You won" or result == "Computer won", "finished text: " .. tostring(result))

    -- Window closed during the computer's turn: it finishes at once
    local bg2 = Games:NewBGVsComputer()
    ns.UI:ShowGame(bg2.id)
    bgPump()
    if Games:IsMyTurn(bg2) then
        while #BG.Legal(bg2) > 0 do
            local m = BG.Legal(bg2)[1]
            BGPlay:Move({ { from = m.from, to = m.to } }); bgPump()
        end
        BGPlay:Done()
    end
    BGBoard.window:Hide()
    bgPump()
    assert(Games:IsMyTurn(bg2), "computer finished its turn while the window was closed")
    Games:Remove(bg2.id)
    Games:Remove(bg.id)
    assert(BGPlay.game == nil, "removing the open game closes it")

    -- Doubles: two dice are thrown, glide into place, then two more slide out (2x2)
    local bg3 = Games:NewBGVsComputer()
    ns.UI:ShowGame(bg3.id); bgPump()
    -- get to a turn of mine that isn't rolled yet (turn 1 comes with the opening roll)
    for _ = 1, 10 do
        if Games:IsMyTurn(bg3) and not bg3.dice then break end
        if Games:IsMyTurn(bg3) then
            while #BG.Legal(bg3) > 0 do
                local m = BG.Legal(bg3)[1]
                BGPlay:Move({ { from = m.from, to = m.to } }); bgPump()
            end
            BGPlay:Done()
        end
        bgPump()
    end
    local ranDoubles, ranDiceFirst = false, false
    assert(Games:IsMyTurn(bg3) and not bg3.dice, "my turn, not rolled yet")
    do
        ranDoubles = true
        bg3.dice = { 3, 3 }
        local phases, last = {}, nil
        BGBoard:AnimateRoll(bg3, nil)
        for _ = 1, 200 do
            local r = BGBoard.rolling
            if not r then break end
            if r.phase ~= last then phases[#phases + 1] = r.phase; last = r.phase end
            BGBoard.board._scripts.OnUpdate(BGBoard.board, 0.05)
        end
        assert(table.concat(phases, ",") == "throw,rest,line,bonus", "doubles: throw, rest, line up, bonus dice (got " .. table.concat(phases, ",") .. ")")
        assert(BGBoard.dice[4]:IsShown(), "four dice after doubles")
        -- Undo takes back ALL moves at once
        local played = 0
        while #BG.Legal(bg3) > 0 and played < 2 do
            local m = BG.Legal(bg3)[1]
            BGPlay:Move({ { from = m.from, to = m.to } }); bgPump()
            played = played + 1
        end
        BGPlay:Undo()
        assert(#bg3.moves == 0, "one Undo takes back every move of the turn")
        bg3.dice = nil
    end

    -- Dice-first play: the highest usable die is primary; a click on a lit checker moves it
    ns.db.options.bgDiceFirst = true
    -- roll until two different dice with a move possible (the test needs that case)
    local realRoll = BG.Roll
    BG.Roll = function(g) if g.dice then return false end; g.dice = { 5, 2 }; g.moves = {}; return true end
    if Games:IsMyTurn(bg3) and not bg3.dice then
        BGPlay:Roll(); bgPump()
        BG.Roll = realRoll
        local d1, d2 = bg3.dice[1], bg3.dice[2]
        if d1 ~= d2 and #BG.Legal(bg3) > 0 then
            ranDiceFirst = true
            BGBoard:Refresh()
            local pv = BGBoard:PrimaryValue()
            assert(pv, "a primary die")
            assert(BGBoard.primaryMoves and next(BGBoard.primaryMoves), "checkers that can move with it are lit")
            -- clicking the other die makes it primary (when it can be used)
            local otherIdx = bg3.dice[1] == pv and 2 or 1
            local canOther = false
            for _, m in ipairs(BG.Legal(bg3)) do if m.die == bg3.dice[otherIdx] then canOther = true end end
            BGBoard:OnDieClick(otherIdx)
            if canOther then assert(BGBoard:PrimaryValue() == bg3.dice[otherIdx], "clicking a die switches the primary die") end
            local use = BGBoard:PrimaryValue()
            BGBoard:Refresh()
            local from, to = next(BGBoard.primaryMoves)
            BGBoard.drag = { from = from, x = 0, y = 0, quick = to }   -- a plain click on that checker
            BGBoard:OnMouseUp(); bgPump()
            assert(#bg3.moves == 1 and bg3.moves[1].die == use, "the click moved it by the primary die")
        end
    end
    BG.Roll = realRoll
    ns.db.options.bgDiceFirst = nil
    assert(ranDoubles and ranDiceFirst, "doubles and dice-first checks ran")

    -- A hit: the hit checker waits on its point, then flies to the bar
    do
        assert(Games:IsMyTurn(bg3) and bg3.dice, "my turn with dice, for the hit test")
        local me = BGBoard:Me()
        local them = 3 - me
        local b = BG.NewBoard()
        -- one of their back checkers stands alone 5 pips in front of my 8-point
        local from = me == 1 and 8 or 17
        local to = from + BG.DIR[me] * 5
        local back = me == 1 and 1 or 24
        b.pts[back] = b.pts[back] - BG.SIGN[them]
        b.pts[to] = BG.SIGN[them]
        bg3.board, bg3.moves, bg3.dice = b, {}, { 5, 2 }
        BGBoard:Refresh()
        BGPlay:Move({ { from = from, to = to } })
        assert(BGBoard.hitStay and BGBoard.hitStay.pos == to, "hit checker stays on its point while ours flies")
        assert(BGBoard.hideBar and BGBoard.hideBar.pos == BG.BAR[them], "and isn't drawn on the bar yet")
        local sawBarFlight = false
        for _ = 1, 100 do
            if not BGBoard:Busy() then break end
            local f = BGBoard.flight
            if f and not BGBoard.hitStay and BGBoard.hideBar then
                sawBarFlight = true
                assert(f.mine == (them == me), "the flying checker is theirs")
            end
            BGBoard.board._scripts.OnUpdate(BGBoard.board, 0.05)
        end
        bgPump()
        assert(sawBarFlight, "the hit checker flies to the bar")
        assert(not BGBoard.hitStay and not BGBoard.hideBar, "nothing left hidden after the flight")
        assert(bg3.board.bar[them] == 1, "it is on the bar")
        BGPlay:Undo()
    end

    -- Bearing off: one click on a checker whose only way is the tray moves it; Done and Undo sit
    -- under the dice; "Auto finish" appears once the sides have passed each other
    do
        Games:Remove(bg3.id)
        local bg5 = Games:NewBGVsComputer()
        ns.UI:ShowGame(bg5.id); bgPump()
        assert(not BGBoard.autoBox:IsShown(), "no Auto finish box while the checkers can still meet")
        local me = BGBoard:Me()
        local them = 3 - me
        -- The opening roll: I start, but I throw the dice myself
        bg5.first, bg5.turn, bg5.dice, bg5.moves, bg5.openRolled = me, 1, { 3, 1 }, {}, nil
        BGBoard:Refresh()
        assert(BGBoard:NeedsOpening(bg5) and BGBoard.rollButton:IsShown(), "Roll button before the opening roll")
        assert(not BGBoard.dice[1]:IsShown() and not BGBoard.doneButton:IsShown(), "no dice shown before I throw them")
        BGPlay:Roll(); bgPump()
        assert(bg5.openRolled and not BGBoard:NeedsOpening(bg5) and BGBoard.dice[1]:IsShown(), "the opening roll is thrown by hand")
        assert(bg5.dice[1] == 3 and bg5.dice[2] == 1, "with the dice that were decided")
        local b = BG.NewBoard()
        for i = 1, 24 do b.pts[i] = 0 end
        local home = me == 1 and 1 or 24
        b.pts[home] = BG.SIGN[me] * 15                    -- all mine on my deepest point
        b.pts[12] = BG.SIGN[them] * 15                    -- all theirs far away
        bg5.board, bg5.first, bg5.turn, bg5.dice, bg5.moves = b, me, 3, { 6, 2 }, {}
        bg5.history = {}
        BGBoard:Refresh()
        assert(not BG.Contact(b), "the sides have passed each other")
        assert(BGBoard.autoBox:IsShown(), "Auto finish box appears after the checkers have passed")
        assert(BGBoard.doneButton:IsShown() and BGBoard.undoButton:IsShown(), "Done and Undo show on the board")
        assert(BGBoard.doneButton:GetParent() == BGBoard.board, "Done sits on the board, under the dice")
        local realCursor = BGBoard.Cursor
        BGBoard.Cursor = function() return 466, 385 end   -- on that point
        BGBoard:OnMouseDown("LeftButton")
        BGBoard.Cursor = realCursor
        assert(BGBoard:Busy(), "one click on the last checker bears it off")
        bgPump()
        assert(#bg5.moves == 1 and bg5.board.off[me] == 1, "it is borne off")
        BGPlay:Undo()
        -- Two quick clicks: the second checker can go before the first has landed
        BGPlay:Move({ { from = home, to = BG.OFF[me] } })
        assert(BGBoard:Busy(), "the first checker is flying")
        BGPlay:Move({ { from = home, to = BG.OFF[me] } })
        assert(#bg5.moves == 2 and BGBoard:Busy(), "the second one goes without waiting")
        bgPump()
        assert(bg5.board.off[me] == 2, "both are borne off")
        BGPlay:Undo()
        bg5.dice = nil
        BGBoard:Refresh()
        assert(BGBoard.rollButton:IsShown() and BGBoard.autoBox:IsShown(), "Roll button with the tick box under it")

        -- Auto finish: against the computer my tick is enough; the game then plays itself, faster
        assert(BGPlay:Speed(bg5) == 1, "normal speed before ticking")
        BGPlay:SetAuto(bg5, true)
        assert(BGPlay:Speed(bg5) == 2, "faster once Auto finish is on")
        bgPump()
        assert(bg5.status == "over", "Auto finish plays the game to the end")
        assert(bg5.auto == nil, "the choice is cleared when the game is over")
        assert(ns.db.stats.backgammon.solo.played == 2, "the finished game is counted")
        Games:Remove(bg5.id)
    end

    -- Backgammon numbers on the stats card (guild column), next to Yatzy's
    ns.db.stats.backgammon = ns.db.stats.backgammon or {}
    local savedSolo = ns.db.stats.backgammon.solo
    ns.db.stats.backgammon.guild = { played = 4, won = 3 }
    ns.db.stats.backgammon.solo = { played = 5, won = 2 }
    ns.db.statsOpen = "backgammon"
    ns.Stats:Refresh(300)
    local bgCells, yCells = ns.Stats.byKey.backgammon.cells, ns.Stats.byKey.yatzy.cells
    assert(bgCells.played.value:GetText() == "4" and bgCells.rate.value:GetText() == "75%",
        "backgammon section on the stats card")
    assert(bgCells.computer.value:GetText() == "2 of 5", "and the record against the computer")
    assert(bgCells.played.value:IsShown() and not yCells.played.value:IsShown(), "only one drop-down is open")
    assert(ns.Stats.byKey.yatzy.summary:GetText():find("games", 1, true), "a closed section shows a short summary")
    -- "Game record" is the first drop-down and lists the guild members you play most
    assert(ns.Stats.sections[1].def.key == "record" and ns.Stats.sections[1].name:GetText() == "Game record",
        "Game record is the top drop-down")
    local savedVs = ns.db.stats.vs
    ns.db.stats.vs = { a = { name = "Biggie Icade", played = 9, won = 4, lost = 5 },
                       b = { name = "Gulki Warr", played = 6, won = 3, lost = 3 } }
    ns.Stats:Refresh(300)
    local rec = ns.Stats.byKey.record
    assert(rec.summary:GetText() == "2 players", "closed Game record says how many players")
    ns.Stats:Toggle("record")
    assert(rec.cells.r1.label:GetText() == "Biggie Icade" and rec.cells.r1.value:GetText() == "4 – 5", "most played first")
    assert(rec.cells.r2.value:GetText() == "3 – 3" and not rec.cells.r3.value:IsShown(), "only the players you have met")
    assert(not yCells.played.value:IsShown(), "opening Game record closes the others")
    ns.db.stats.vs = {}
    ns.Stats:Refresh(300)
    assert(rec.cells.none.label:IsShown(), "no rivals yet: says so")
    ns.db.stats.vs = savedVs
    ns.db.statsOpen = "backgammon"
    ns.Stats:Refresh(300)
    ns.Stats:Toggle("yatzy")
    assert(yCells.played.value:IsShown() and not bgCells.played.value:IsShown(), "opening Yatzy closes Backgammon")
    ns.Stats:Toggle("yatzy")
    assert(not yCells.played.value:IsShown() and ns.db.statsOpen == "", "clicking the open one closes it")
    ns.db.statsOpen = "yatzy"
    ns.db.stats.backgammon.guild = nil
    ns.db.stats.backgammon.solo = savedSolo

    -- Ctrl + wheel: the backgammon window has its own size
    local mainScale = ns.UI:WindowScale()
    ns.UI:SetWindowScale(0.8, true, "bg")
    assert(ns.UI:WindowScale("bg") == 0.8 and ns.db.bgWindow.scale == 0.8, "backgammon window size saved")
    assert(ns.UI:WindowScale() == mainScale, "the main window keeps its size")
    ns.UI:SetWindowScale(1, true, "bg")

    -- Clear list: every game leaves the list (after the question)
    StaticPopupDialogs = StaticPopupDialogs or {}
    local savedShow = StaticPopup_Show
    StaticPopup_Show = function(which) StaticPopupDialogs[which].OnAccept() end
    ns.UI:ShowStart()
    assert(#Games:Sorted() > 0, "there are games to clear")
    ns.UI:ClearList()
    assert(#Games:Sorted() == 0, "Clear list empties the list")
    StaticPopup_Show = savedShow

    -- Sound button: the speaker picture follows the level (crossed out when off)
    local shown
    ns.UI.soundButton.icon.SetTexture = function(_, tex) shown = tex end
    local speaker = ns.Style.TEX.ui.speaker
    local savedOn, savedVol = ns.db.options.sound, ns.db.options.soundVolume
    ns.db.options.sound = false; ns.UI:UpdateSoundButton()
    assert(shown == speaker[0], "sound off shows the crossed-out speaker")
    ns.db.options.sound = true
    for level, waves in pairs({ low = 1, normal = 2, high = 3 }) do
        ns.db.options.soundVolume = level; ns.UI:UpdateSoundButton()
        assert(shown == speaker[waves], level .. " shows " .. waves .. " wave(s)")
    end
    ns.db.options.sound, ns.db.options.soundVolume = savedOn, savedVol

    -- Minimap tooltip: our name first, no "click / drag" help lines
    local lines = {}
    GameTooltip.AddLine = function(_, text) lines[#lines + 1] = text end
    ns.minimapButton:GetScript("OnEnter")(ns.minimapButton)
    assert(lines[1] == ns.DISPLAY_NAME, "the minimap tooltip starts with the addon's name")
    assert(not table.concat(lines, "|"):find("Click", 1, true), "no click/drag help in the tooltip")
end
print(("Smoke test OK: full game finished (you %d, computer %d), stats and resizing work.")
    :format(Rules.Total(g.sheets[1]), Rules.Total(g.sheets[2])))
