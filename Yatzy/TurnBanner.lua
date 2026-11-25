-- TurnBanner.lua
-- A small box at the top of the screen while it's your turn in a guild game that isn't
-- on screen (the window is closed, or shows another game). Click it to open that game.
-- Fast games show their time left in the corner. Drag it to move it; the x hides it
-- until the next turn.

local _, Yatzy = ...
local Banner = {}
Yatzy.TurnBanner = Banner

local W, H = 270, 46

local function Games() return Yatzy.Games end
local function Rules() return Yatzy.Rules end

function Banner:Create()
    local Style, UI = Yatzy.Style, Yatzy.UI
    local f = CreateFrame("Button", "YatzyTurnBanner", UIParent)
    f:SetSize(W, H)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    local saved = Yatzy.db.banner or {}
    f:SetPoint(saved.point or "TOP", UIParent, saved.relativePoint or "TOP", saved.x or 0, saved.y or -120)
    Style.LeatherPanel(f, { color = { 0.24, 0.18, 0.14 }, border = 2, stitch = 5 })

    -- soft gold light that breathes, so it's noticed without being loud
    local glow = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    glow:SetTexture(Style.TEX.ui.softGlow)
    glow:SetTexCoord(0, 1, 0, 1)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.72, 0.25)
    glow:SetPoint("TOPLEFT", -30, 18); glow:SetPoint("BOTTOMRIGHT", 30, -18)
    f.glow = glow

    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 3, -3); hl:SetPoint("BOTTOMRIGHT", -3, 3)
    hl:SetColorTexture(1, 0.85, 0.5, 0.10)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(32, 32)
    f.icon:SetPoint("LEFT", 8, 0)

    f.title = f:CreateFontString(nil, "OVERLAY")
    Style.Font(f.title, "title", 16, Style.TITLE)
    f.title:SetShadowOffset(1, -1)
    f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, 1)
    f.title:SetText("Your turn!")

    f.sub = f:CreateFontString(nil, "OVERLAY")
    Style.Font(f.sub, "display", 10, Style.TEXT)
    f.sub:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 8, 1)
    f.sub:SetPoint("RIGHT", -10, 0)
    f.sub:SetJustifyH("LEFT")
    f.sub:SetWordWrap(false)

    -- fast games: time left, small, top-right (next to the x); same colour as the game screen's timer
    f.timer = f:CreateFontString(nil, "OVERLAY")
    Style.Font(f.timer, "display", 11, { 0.82, 0.76, 0.62 })
    f.timer:SetShadowColor(0, 0, 0, 0.9); f.timer:SetShadowOffset(0, -1)
    f.timer:SetPoint("TOPRIGHT", -24, -6)

    local close = CreateFrame("Button", nil, f)
    close:SetSize(16, 16)
    close:SetPoint("TOPRIGHT", -4, -4)
    close.text = close:CreateFontString(nil, "OVERLAY")
    Style.Font(close.text, "display", 11, { 0.8, 0.72, 0.6 })
    close.text:SetPoint("CENTER", 0, 1)
    close.text:SetText("x")
    local chl = close:CreateTexture(nil, "HIGHLIGHT")
    chl:SetAllPoints(); chl:SetColorTexture(1, 0.85, 0.5, 0.15)
    close:SetScript("OnClick", function()
        Banner.dismissed = Banner.key          -- hidden until the next turn somewhere
        f:Hide()
    end)
    UI.Tooltip(close, "Hide", "Hide this until your next turn.")

    f:SetScript("OnClick", function() Banner:OpenGame() end)
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        Yatzy.db.banner = { point = point, relativePoint = relativePoint, x = x, y = y }
    end)
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Your turn")
        GameTooltip:AddLine("Click to open the game. Drag to move this box.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:SetScript("OnUpdate", function(self, elapsed)
        self.t = (self.t or 0) + elapsed
        self.glow:SetAlpha(0.35 + 0.25 * math.sin(self.t * 2.4))
    end)
    f:Hide()
    self.frame = f
end

-- Guild games where it's my turn and that aren't on screen right now.
-- The most urgent first: fast games by time left, then the longest-waiting.
function Banner:Waiting()
    local list = {}
    local Play = Yatzy.Play
    for _, g in ipairs(Games():Ongoing()) do
        if g.kind == "guild" and Games():IsMyTurn(g) and not Play:IsShowing(g) and not Yatzy.BGPlay:IsShowing(g) then
            list[#list + 1] = g
        end
    end
    local Fast = Yatzy.Fast
    table.sort(list, function(a, b)
        local la, lb = Fast:TimeLeft(a), Fast:TimeLeft(b)
        if la and lb then return la < lb end
        if la or lb then return la ~= nil end
        return (a.lastActivity or 0) < (b.lastActivity or 0)
    end)
    return list
end

function Banner:Update()
    if not self.frame then return end
    local f = self.frame
    local list = self:Waiting()
    local keys = {}
    for _, g in ipairs(list) do keys[#keys + 1] = g.id .. ":" .. g.turn end
    self.key = table.concat(keys, ",")
    local UI = Yatzy.UI
    local window = Yatzy.mainWindow
    local onStart = window and window:IsShown() and UI.start and UI.start:IsShown()   -- the list shows it there
    local hideNow = #list == 0 or onStart or self.dismissed == self.key
        or Yatzy.db.options.turnAlert == false
        or (Yatzy.inCombat and Yatzy.db.options.hideInCombat ~= false)
    if hideNow then f:Hide(); return end

    local g = list[1]
    self.game = g
    f.icon:SetTexture(Yatzy.Style.TEX.ui.gameIcon[UI:GameType(g)] or Yatzy.Style.TEX.ui.gameIcon.yatzy)
    local others = {}
    for seat = 1, #g.players do
        if seat ~= g.me then others[#others + 1] = Games():PlayerName(g, seat) end
    end
    local sub = "vs " .. table.concat(others, ", ")
    if #list > 1 then sub = sub .. ("  ·  +%d more"):format(#list - 1) end
    Yatzy.Style.SetText(f.sub, sub)
    local left = Yatzy.Fast:TimeLeft(g)
    if left then Yatzy.Style.SetText(f.timer, Yatzy.Fast:Format(left)) else f.timer:SetText("") end
    if not f:IsShown() then f.t = 0; f:Show() end
end

function Banner:OpenGame()
    local g = self.game
    if not g then return end
    -- backgammon opens in its own window
    if g.game ~= "backgammon" and not Yatzy.mainWindow:IsShown() then Yatzy:ToggleMainWindow() end
    Yatzy.UI:ShowGame(g.id)
    self.frame:Hide()
end

function Banner:Init()
    self:Create()
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(1, function() Banner:Update() end)
    end
end
