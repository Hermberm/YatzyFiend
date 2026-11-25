-- UI.lua
-- The main window: title bar, resize handles, start screen, and the layout that
-- places the dice table (Board.lua) and the score sheet (Sheet.lua) side by side.
--
-- Resizing changes the window's size only; dice, text and the sheet keep their size.

local _, Yatzy = ...
local Rules = Yatzy.Rules
local UI = {}
Yatzy.UI = UI

local DEFAULT_W, DEFAULT_H = 780, 460
local MIN_W, MIN_H = 420, 270          -- the score sheet scrolls when the window is shorter than it
local MAX_W, MAX_H = 1600, 1000
local TITLE_H = 30
local BORDER = 6                       -- metal frame thickness
local MIN_TABLE_W = 350                -- the table never gets narrower than this next to the sheet
UI.SHEET_W = 250

local Style = Yatzy.Style
local GOLD = Style.TITLE

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function savePosition(frame)
    local saved = Yatzy.db.window
    local point, _, relativePoint, x, y = frame:GetPoint()
    saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
    saved.width, saved.height = frame:GetWidth(), frame:GetHeight()
end

local function restorePosition(frame)
    local saved = Yatzy.db.window
    frame:ClearAllPoints()
    frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    frame:SetSize(saved.width or DEFAULT_W, saved.height or DEFAULT_H)
end

-- kind: "primary" (red, default) or "secondary" (dark leather)
function UI.MakeButton(parent, text, width, height, kind)
    return Style.Button(parent, text, width, height, kind)
end

function UI.Tooltip(frame, title, line)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(type(title) == "function" and title() or title)   -- a function: text that changes
        if line then GameTooltip:AddLine(line, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- An invisible strip on the window edge that resizes the window when dragged.
local function addResizeHandle(window, sizingPoint, setPoints)
    local h = CreateFrame("Frame", nil, window)
    setPoints(h)
    -- Well above everything inside the window (the score sheet sits at about +42, its tab at +47),
    -- so the handles always get the mouse.
    h:SetFrameLevel(window:GetFrameLevel() + 100)
    h:EnableMouse(true)
    h:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then window:StartSizing(sizingPoint) end
    end)
    h:SetScript("OnMouseUp", function()
        window:StopMovingOrSizing()
        savePosition(window)
    end)
    return h
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

function Yatzy:CreateMainWindow()
    if self.mainWindow then return end

    local f = CreateFrame("Frame", "YatzyMainWindow", UIParent, "BackdropTemplate")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)              -- comes in front of the backgammon window when clicked
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:EnableMouse(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    else
        f:SetMinResize(MIN_W, MIN_H)
        f:SetMaxResize(MAX_W, MAX_H)
    end
    restorePosition(f)

    -- Window: dark leather inside a bevelled bronze frame with slightly rounded corners
    -- (the leather stays inside the frame, so nothing pokes out past the round corners)
    local fill = Style.Fill(f, Style.TEX.leather, { 0.26, 0.21, 0.18 })
    fill:ClearAllPoints()
    fill:SetPoint("TOPLEFT", BORDER, -BORDER)
    fill:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    Style.WindowFrame(f, BORDER)

    -- Title bar: leather strip with a stitched seam (drag here to move the window)
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", BORDER, -BORDER)
    bar:SetPoint("TOPRIGHT", -BORDER, -BORDER)
    bar:SetHeight(TITLE_H)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() f:StartMoving() end)
    bar:SetScript("OnDragStop", function() f:StopMovingOrSizing(); savePosition(f) end)
    Style.Fill(bar, Style.TEX.leather, Style.LEATHER_DARK)
    local seam = bar:CreateTexture(nil, "ARTWORK")
    seam:SetTexture(Style.TEX.stitchH, "REPEAT", "REPEAT")
    seam:SetHorizTile(true)
    seam:SetPoint("BOTTOMLEFT", 8, 4); seam:SetPoint("BOTTOMRIGHT", -8, 4); seam:SetHeight(2)
    local barLine = bar:CreateTexture(nil, "BORDER")
    barLine:SetPoint("BOTTOMLEFT"); barLine:SetPoint("BOTTOMRIGHT"); barLine:SetHeight(2)
    Style.Tile(barLine, Style.TEX.metal, Style.BRONZE)

    -- Red name plaque in the middle with the full title
    local plaque = CreateFrame("Frame", nil, bar)
    plaque:SetSize(220, 26)
    plaque:SetPoint("CENTER", 0, 1)
    Style.Image(plaque, Style.TEX.ui.plaque)
    local title = plaque:CreateFontString(nil, "OVERLAY")
    Style.Font(title, "title", 16, GOLD)
    title:SetShadowOffset(1, -1)
    title:SetPoint("CENTER", 0, 0)
    title:SetText(Yatzy.DISPLAY_NAME)

    local close = UI.MakeButton(bar, "X", 22, 22, "secondary")
    close:SetPoint("RIGHT", -4, 1)
    close:SetScript("OnClick", function() f:Hide() end)
    UI.Tooltip(close, "Close", "Your games are saved.")

    -- Sound: a speaker with 1-3 waves for Low/Normal/High, crossed out when off
    local sound = UI.MakeButton(bar, "", 22, 22, "secondary")
    sound:SetPoint("RIGHT", close, "LEFT", -4, 0)
    sound.icon = UI.ButtonIcon(sound, Style.TEX.ui.speaker[2])
    sound:SetScript("OnClick", function(self)
        Yatzy.Sound:NextLevel()                  -- Low -> Normal -> High -> Off
        UI:UpdateSoundButton()
        if GameTooltip.IsOwned and GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
    end)
    UI.Tooltip(sound, function() return "Sound: " .. UI.SOUND_NAMES[Yatzy.Sound:Level()] end,
        "Click to switch between Low, Normal, High and Off. Your own Yatzy sound: see README.")
    UI.soundButton = sound

    -- Settings (a cog): drops down a short list of options under the button
    local settings = UI.MakeButton(bar, "", 22, 22, "secondary")
    settings.icon = UI.ButtonIcon(settings, Style.TEX.ui.gear)
    settings:SetPoint("RIGHT", sound, "LEFT", -4, 0)
    UI.Tooltip(settings, "Settings", "Combat, fading, notices, Escape key and sound.")
    UI.settingsButton = settings
    Yatzy.Settings:AttachToButton(settings, f)

    -- The title plaque steps aside when the window is too narrow for it and the buttons
    bar:SetScript("OnSizeChanged", function(_, w) plaque:SetShown((w or 0) >= 720) end)
    UI.plaque = plaque

    local menu = UI.MakeButton(bar, "Games", 70, 22, "secondary")
    menu:SetPoint("LEFT", 4 + 28 + 4, 1)            -- the Home button sits to its left
    menu:SetScript("OnClick", function() Yatzy.SideMenu:Toggle() end)
    UI.Tooltip(menu, "Games", "Your games: switch game, start a new one.")
    UI.menuButton = menu

    -- Home: straight back to the main menu (start screen)
    local home = UI.MakeButton(bar, "", 28, 22, "secondary")
    home:SetPoint("RIGHT", menu, "LEFT", -4, 0)
    local homeIcon = home:CreateTexture(nil, "OVERLAY")
    homeIcon:SetTexture(Style.TEX.ui.home)
    homeIcon:SetSize(16, 16)
    homeIcon:SetPoint("CENTER", 0, 0)
    home:SetScript("OnClick", function() UI:ShowStart() end)
    UI.Tooltip(home, "Main menu", "Back to the start screen.")
    UI.homeButton = home

    -- Resize handles on the edges and bottom corners
    addResizeHandle(f, "LEFT", function(h) h:SetPoint("TOPLEFT", 0, -TITLE_H - BORDER); h:SetPoint("BOTTOMLEFT", 0, 14); h:SetWidth(BORDER) end)
    addResizeHandle(f, "RIGHT", function(h) h:SetPoint("TOPRIGHT", 0, -TITLE_H - BORDER); h:SetPoint("BOTTOMRIGHT", 0, 22); h:SetWidth(BORDER) end)
    addResizeHandle(f, "BOTTOM", function(h) h:SetPoint("BOTTOMLEFT", 14, 0); h:SetPoint("BOTTOMRIGHT", -22, 0); h:SetHeight(BORDER) end)
    addResizeHandle(f, "BOTTOMLEFT", function(h) h:SetPoint("BOTTOMLEFT"); h:SetSize(14, 14) end)
    local grip = addResizeHandle(f, "BOTTOMRIGHT", function(h) h:SetPoint("BOTTOMRIGHT", -1, 1); h:SetSize(20, 20) end)
    local gripTex = grip:CreateTexture(nil, "OVERLAY")
    gripTex:SetAllPoints()
    gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")

    -- Content area under the title bar
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", BORDER, -(BORDER + TITLE_H))
    body:SetPoint("BOTTOMRIGHT", -BORDER, BORDER)
    UI.body = body

    UI:CreateStartScreen(body)
    UI.game = CreateFrame("Frame", nil, body)
    UI.game:SetAllPoints()
    if UI.game.SetClipsChildren then UI.game:SetClipsChildren(true) end   -- the sheet slides out of view
    Yatzy.Board:Create(UI.game)
    Yatzy.Sheet:Create(UI.game)

    f:SetScript("OnSizeChanged", function() UI:Layout() end)
    f:SetScript("OnShow", function()
        Yatzy:PlayUISound("IG_CHARACTER_INFO_OPEN")
        Yatzy.Play:OnWindowShown()
        UI:Refresh()
    end)
    f:SetScript("OnHide", function() Yatzy:PlayUISound("IG_CHARACTER_INFO_CLOSE") end)

    f:Hide()
    self.mainWindow = f
    UI:ApplyEscape()          -- Escape closes the window (unless turned off in Settings)

    -- Whole-window size (scale): Ctrl + mouse wheel over the title bar. Saved.
    f:SetScale(Yatzy.db.window.scale or 1)
    Style.UpdateThinLines()
    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", function(_, delta)
        if IsControlKeyDown and IsControlKeyDown() then UI:SetWindowScale((Yatzy.db.window.scale or 1) + delta * 0.05) end
    end)
    UI.Tooltip(bar, Yatzy.DISPLAY_NAME, "Drag to move. Ctrl + mouse wheel to make the window smaller or bigger.")

    -- Fade the window while the mouse is elsewhere (you're playing WoW), full when you point at it
    UI:SetupFade(f)

    UI:UpdateSoundButton()
    if Yatzy.Sheet:IsDetached() then Yatzy.Sheet:ApplyDetached() end   -- remembered from last time
    UI:ShowStart()
end

local MIN_SCALE, MAX_SCALE = 0.5, 1.2
UI.MIN_SCALE, UI.MAX_SCALE = MIN_SCALE, MAX_SCALE

-- Each window has its own size: `which` = "bg" for the backgammon window, else the main one.
-- Returns the window frame (may be nil before it's built) and its saved table.
function UI:ScaleTarget(which)
    if which == "bg" then
        Yatzy.db.bgWindow = Yatzy.db.bgWindow or {}
        return Yatzy.BGBoard and Yatzy.BGBoard.window, Yatzy.db.bgWindow
    end
    return Yatzy.mainWindow, Yatzy.db.window
end

function UI:WindowScale(which)
    local _, saved = self:ScaleTarget(which)
    return saved.scale or 1
end

-- `quiet`: no chat line (the Settings row shows the size itself)
function UI:SetWindowScale(scale, quiet, which)
    scale = math.max(MIN_SCALE, math.min(MAX_SCALE, math.floor(scale * 20 + 0.5) / 20))
    local f, saved = self:ScaleTarget(which)
    saved.scale = scale
    if not f then return end
    -- keep the window's top-left corner where it is on screen while scaling
    local left, top = f:GetLeft(), f:GetTop()
    local old = f:GetScale()
    if old and math.abs(old - scale) < 0.001 then return end      -- already at that size (e.g. the max): say nothing
    f:SetScale(scale)
    if left and top then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / scale, top * old / scale)
        local point, _, relativePoint, x, y = f:GetPoint()
        saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
    end
    Style.UpdateThinLines()          -- hairlines stay one whole screen pixel at the new size
    if not quiet then
        Yatzy:Print(("%s size %d%%."):format(which == "bg" and "Backgammon window" or "Window", scale * 100))
    end
    if Yatzy.Settings.panels then Yatzy.Settings:RefreshAll() end    -- the -/+ row in Settings
end

-- Fading: the window is faded only while the mouse is outside it AND your character is
-- moving or in combat (see UI:ShouldFade); pointing at the window makes it solid again.
local FADE_SPEED = 3          -- alpha per second
local function mouseOver(frame)
    if frame.IsMouseOver then return frame:IsMouseOver() end
    return MouseIsOver and MouseIsOver(frame)
end
-- Fade when the character moves in any way (keys, autorun, click-to-move, /follow,
-- falling, swimming, knockbacks) or is in combat - but never on a flight path.
--
-- In combat the client hands addons "secret" values for things like the player's speed:
-- comparing one is an error (0.9.1 spammed errors in combat). So: combat is decided from
-- the combat events / InCombatLockdown (always allowed) and answers "fade" right away,
-- before any movement value is read; secret values are skipped; and every check runs
-- protected, so an unreadable value can never cause an error.
local function readable(v)
    return not (issecretvalue and issecretvalue(v))
end

local function check(fn, ...)
    if not fn then return false end
    local ok, v = pcall(fn, ...)
    if not ok or not readable(v) then return false end
    return v
end

function UI:ShouldFade()
    if Yatzy.inCombat or check(InCombatLockdown) then return true end
    if check(UnitOnTaxi, "player") then return false end
    local ok, moving = pcall(function()
        local speed = check(GetUnitSpeed, "player")
        if type(speed) == "number" and speed > 0 then return true end
        return check(IsPlayerMoving) or check(IsFalling)
    end)
    return (ok and moving) and true or false
end

-- One shared fade for every Yatzy window (the game window and the detached score sheet):
-- they fade together, and pointing at any of them makes all of them solid.
UI.fadeFrames = {}
UI.fadeAlpha = 1

-- How see-through the window gets (Settings: the button next to the fade tick box)
UI.FADE_LEVELS = { "low", "medium", "high" }
UI.FADE_ALPHA = { low = 0.45, medium = 0.28, high = 0.14 }

function UI:FadeLevel()
    local level = Yatzy.db.options.fadeLevel
    return UI.FADE_ALPHA[level] and level or "low"
end

-- Next level (Low -> Medium -> High -> Low). The window shows the new level for a moment.
function UI:NextFadeLevel()
    local current = UI:FadeLevel()
    for i, l in ipairs(UI.FADE_LEVELS) do
        if l == current then Yatzy.db.options.fadeLevel = UI.FADE_LEVELS[i % #UI.FADE_LEVELS + 1]; break end
    end
    UI.fadePreviewUntil = (GetTime and GetTime() or 0) + 1.5
    return Yatzy.db.options.fadeLevel
end

function UI:FadeTarget()
    local opts = Yatzy.db.options
    if opts.fade == false then return 1 end
    local alpha = UI.FADE_ALPHA[UI:FadeLevel()]
    if GetTime and GetTime() < (UI.fadePreviewUntil or 0) then return alpha end    -- just changed the level
    if UI.keepVisible or not UI:ShouldFade() then return 1 end
    for _, frame in ipairs(UI.fadeFrames) do
        if frame:IsShown() and mouseOver(frame) then return 1 end
    end
    return alpha
end

function UI:FadeStep(elapsed)
    local target = UI:FadeTarget()
    if UI.fadeAlpha ~= target then
        local step = FADE_SPEED * elapsed
        UI.fadeAlpha = UI.fadeAlpha < target and math.min(target, UI.fadeAlpha + step)
            or math.max(target, UI.fadeAlpha - step)
    end
    for _, frame in ipairs(UI.fadeFrames) do frame:SetAlpha(UI.fadeAlpha) end
    -- The paper of the score sheet ignores its parents' opacity (see Sheet.lua), so it
    -- gets the fade itself. Without this it stayed fully solid while everything else faded.
    local paper = Yatzy.Sheet and Yatzy.Sheet.paper
    if paper then paper:SetAlpha(UI.fadeAlpha) end
end

function UI:SetupFade(f)
    table.insert(UI.fadeFrames, f)
    if not UI.fadeDriver then
        -- the main window drives the fade (the sheet window is only shown together with it)
        UI.fadeDriver = true
        f:HookScript("OnUpdate", function(_, elapsed) UI:FadeStep(elapsed) end)
        f:HookScript("OnShow", function() UI.fadeAlpha = 1; UI:FadeStep(0) end)
    end
    f:HookScript("OnShow", function(frame) frame:SetAlpha(UI.fadeAlpha) end)
end

function Yatzy:ToggleMainWindow()
    local frame = self.mainWindow
    if not frame then return end
    self.hiddenByCombat = false
    frame:SetShown(not frame:IsShown())
end

function Yatzy:ResetWindowPosition()
    local saved = self.db.window
    saved.point, saved.relativePoint, saved.x, saved.y = "CENTER", "CENTER", 0, 0
    saved.width, saved.height = DEFAULT_W, DEFAULT_H
    saved.scale = 1
    if self.mainWindow then
        self.mainWindow:SetScale(1)
        restorePosition(self.mainWindow)
    end
    -- the backgammon window too: normal size, back near the middle
    local bg = self.db.bgWindow
    if bg then
        bg.point, bg.relativePoint, bg.x, bg.y, bg.scale = "CENTER", "CENTER", 60, -20, 1
        local f = self.BGBoard and self.BGBoard.window
        if f then
            f:SetScale(1)
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "CENTER", 60, -20)
        end
    end
end

-- WoW closes every frame listed in UISpecialFrames when Escape is pressed.
-- Setting off: the window only closes with the X or the minimap button.
function UI:ApplyEscape()
    local name = "YatzyMainWindow"
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == name then table.remove(UISpecialFrames, i) end
    end
    if Yatzy.db.options.escCloses ~= false then tinsert(UISpecialFrames, name) end
end

UI.SOUND_NAMES = { low = "Low", normal = "Normal", high = "High", off = "Off" }
local SOUND_WAVES = { off = 0, low = 1, normal = 2, high = 3 }   -- waves on the speaker icon

-- A small picture in the middle of a square title-bar button
function UI.ButtonIcon(button, texture)
    local icon = button:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(texture)
    icon:SetSize(18, 18)            -- as big as the 22 px button allows, so it reads at small window sizes
    icon:SetPoint("CENTER")
    return icon
end

function UI:UpdateSoundButton()
    local level = Yatzy.Sound:Level()
    self.soundButton.icon:SetTexture(Yatzy.Style.TEX.ui.speaker[SOUND_WAVES[level] or 2])
    if Yatzy.Settings.instances then Yatzy.Settings:RefreshAll() end
end

-- The start screen (game choice, games list) is in StartScreen.lua.

---------------------------------------------------------------------------
-- Screens and layout
---------------------------------------------------------------------------

function UI:ShowStart()
    Yatzy.SideMenu:CloseNow()
    Yatzy.Play:Close()
    self.game:Hide()
    self.start:Show()
    self.menuButton:Hide()
    self.homeButton:Hide()
    self:RefreshStart()
end

function UI:ShowGame(id)
    local g = Yatzy.Games:Get(id)
    if not g or not (g.status == "active" or g.status == "over") or not g.players then return end
    -- Backgammon opens in its own window; this window stays as it is
    if g.game == "backgammon" then
        Yatzy.SideMenu:CloseNow()
        Yatzy.BGPlay:Open(g)
        return
    end
    self.start:Hide()
    self.game:Show()
    self.menuButton:Show()
    self.homeButton:Show()
    Yatzy.Sheet:SetWidthFor(g)        -- wider sheet for 5-6 players
    self:Layout()
    Yatzy.Play:Open(g)
end

function UI:Refresh()
    if self.start:IsShown() then
        self:RefreshStart()
    else
        Yatzy.Play:Refresh()
    end
end

-- Place the table and the sheet. In a narrow window the sheet folds in automatically;
-- opened anyway, it lies OVER the table instead of squeezing it.
function UI:Layout(animate)
    local body = self.body
    local width = body:GetWidth()
    if not width or width == 0 then return end
    if self.start:IsShown() then self:RefreshStart() end   -- the number of list rows depends on the height

    -- Score sheet in its own window: the table gets the whole width
    if Yatzy.Sheet:IsDetached() then
        Yatzy.Sheet:Place(self.game)
        Yatzy.Board:Place(self.game, nil)
        Yatzy.Board:Relayout()
        return
    end

    -- Docked sheet: as wide as it likes when there's room; in a smaller window it gets
    -- narrower (thinner columns) so table and sheet both stay visible. Only when even the
    -- narrowest sheet doesn't fit next to the table does it fold in.
    local Sheet = Yatzy.Sheet
    local g = Sheet.widthGame or Sheet.game
    local preferred, smallest = Sheet:WidthFor(g), Sheet:MinDockedWidth(g)
    local room = width - MIN_TABLE_W
    local narrow = room < smallest
    UI.SHEET_W = narrow and preferred or math.max(smallest, math.min(preferred, room))
    Sheet.frame:SetWidth(UI.SHEET_W)
    if narrow ~= self.narrow then
        self.narrow = narrow
        self.sheetOpen = (not narrow) and Yatzy.db.options.sheetOpen
    end
    if self.sheetOpen == nil then self.sheetOpen = Yatzy.db.options.sheetOpen end

    -- In a wide window the table always ends at the sheet's left edge, so it grows and
    -- shrinks as the sheet slides; in a narrow window the sheet slides over the table.
    Yatzy.Sheet:Place(self.game, self.sheetOpen, narrow, animate)
    Yatzy.Board:Place(self.game, not narrow and Yatzy.Sheet.frame or nil)
    Yatzy.Board:Relayout()
end

-- Fold tab clicked.
function UI:ToggleSheet()
    self.sheetOpen = not self.sheetOpen
    if not self.narrow then
        Yatzy.db.options.sheetOpen = self.sheetOpen     -- remember the choice only in a wide window
    end
    self:Layout(true)
    Yatzy.Play:Refresh()
end

-- After writing a score in a narrow window, slide the sheet away again.
function UI:AfterScore()
    if self.narrow and self.sheetOpen then
        self.sheetOpen = false
        self:Layout(true)
    end
end
