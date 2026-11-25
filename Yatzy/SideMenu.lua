-- SideMenu.lua
-- In a game, the "Games" button slides a panel out from the left over the table:
-- "New game" (opens the start screen's game choice) and your games, grouped like the
-- start screen, each with its game icon (click to switch).

local _, Yatzy = ...
local Menu = {}
Yatzy.SideMenu = Menu

local WIDTH = 250
local SLIDE_TIME = 0.2
local ROW_H, ROW_GAP, HEADER_H = 36, 4, 20
local MAX_ROWS = 10

function Menu:Create(parent)
    local Style, UI = Yatzy.Style, Yatzy.UI

    -- Dark backdrop over the game; clicking it closes the menu
    local cover = CreateFrame("Button", nil, parent)
    cover:SetAllPoints()
    cover:SetFrameLevel(parent:GetFrameLevel() + 70)
    local dim = cover:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints()
    dim:SetColorTexture(0, 0, 0, 0.45)
    cover:SetScript("OnClick", function() Menu:Close() end)
    cover:Hide()
    self.cover, self.dim = cover, dim

    local panel = CreateFrame("Frame", nil, cover)
    panel:SetWidth(WIDTH)
    panel:EnableMouse(true)
    Style.LeatherPanel(panel, { border = 3 })
    for _, side in ipairs({ "TOP", "BOTTOM", "RIGHT" }) do Style.EdgeShade(panel, side, 20, 0.5) end
    self.panel = panel

    local title = panel:CreateFontString(nil, "OVERLAY")
    Style.Font(title, "title", 18, Style.TITLE)
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Your Games")

    -- New game: goes to the start screen with this game's "vs Guild / vs Computer" panel open
    -- (the main menu itself is the Home button in the title bar)
    local newGame = UI.MakeButton(panel, "New game", 200, 32, "secondary")
    newGame:SetPoint("TOP", 0, -42)
    newGame:SetScript("OnClick", function()
        local current = Yatzy.Play.game
        Menu:CloseNow()
        UI:ShowStart()
        local type = current and UI:GameType(current) or "yatzy"
        for _, card in ipairs(UI.gameCards or {}) do
            if card.info.id == type then UI:ChooseGame(card) end
        end
    end)
    self.newGame = newGame

    local list = CreateFrame("Frame", nil, panel)
    list:SetPoint("TOPLEFT", 12, -84)
    list:SetPoint("BOTTOMRIGHT", -12, 12)
    if list.SetClipsChildren then list:SetClipsChildren(true) end
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) Menu:Scroll(-delta) end)
    self.list = list
    self.offset = 0

    -- Group headers, like on the start screen ("Your turn" + a thin gold line)
    self.headers = {}
    for i = 1, 4 do
        local h = CreateFrame("Frame", nil, list)
        h:SetHeight(HEADER_H)
        h.text = h:CreateFontString(nil, "OVERLAY")
        Style.Font(h.text, "display", 11, Style.TITLE)
        h.text:SetPoint("BOTTOMLEFT", 2, 4)
        local line = h:CreateTexture(nil, "ARTWORK")
        line:SetPoint("LEFT", h.text, "RIGHT", 6, 0)
        line:SetPoint("RIGHT", h, "RIGHT")
        Style.ThinLine(line, 1, true)
        line:SetColorTexture(0.80, 0.66, 0.40, 0.45)
        h:Hide()
        self.headers[i] = h
    end

    self.rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(ROW_H)
        Style.LeatherPanel(row, { color = { 0.24, 0.19, 0.16 }, border = 1 })
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta) Menu:Scroll(-delta) end)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.85, 0.4, 0.10)
        row.current = row:CreateTexture(nil, "ARTWORK", nil, 2)
        row.current:SetPoint("TOPLEFT", 1, -1); row.current:SetPoint("BOTTOMLEFT", 1, 1); row.current:SetWidth(3)
        row.current:SetColorTexture(1, 0.82, 0.3, 1)
        -- game icon (Yatzy dice / backgammon checkers)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("LEFT", 7, 0)
        row.names = row:CreateFontString(nil, "OVERLAY")
        Style.Font(row.names, "display", 11, Style.TEXT)
        row.names:SetPoint("TOPLEFT", 37, -6)
        row.names:SetPoint("RIGHT", -6, 0)
        row.names:SetJustifyH("LEFT")
        row.names:SetWordWrap(false)
        row.meta = row:CreateFontString(nil, "OVERLAY")
        Style.Font(row.meta, "display", 9, { 0.70, 0.64, 0.52 })
        row.meta:SetPoint("BOTTOMLEFT", 37, 6)
        row.meta:SetPoint("RIGHT", -6, 0)
        row.meta:SetJustifyH("LEFT")
        row.meta:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
            local g = self.game
            Menu:Close()
            if g and (g.status == "active" or g.status == "over") then UI:ShowGame(g.id) else UI:ShowStart() end
        end)
        row:Hide()
        self.rows[i] = row
    end

    self.animator = CreateFrame("Frame", nil, cover)
    self.x = -WIDTH
    self:Place()
end

function Menu:Place()
    local p = self.panel
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", self.cover, "TOPLEFT", self.x, 0)
    p:SetPoint("BOTTOMLEFT", self.cover, "BOTTOMLEFT", self.x, 0)
    self.dim:SetAlpha(0.45 * (1 + self.x / WIDTH))
end

function Menu:IsOpen()
    return self.cover and self.cover:IsShown() and self.target == 0
end

function Menu:Toggle()
    if self:IsOpen() then self:Close() else self:Open() end
end

function Menu:Open()
    if not self.cover then self:Create(Yatzy.UI.game) end
    self:Refresh()
    self.cover:Show()
    self:SlideTo(0)
end

function Menu:Close()
    if not self.cover or not self.cover:IsShown() then return end
    self:SlideTo(-WIDTH)
end

-- Close without animation (e.g. when leaving the game screen)
function Menu:CloseNow()
    if not self.cover then return end
    self.animator:SetScript("OnUpdate", nil)
    self.x, self.target = -WIDTH, -WIDTH
    self:Place()
    self.cover:Hide()
end

function Menu:SlideTo(target)
    self.target, self.from, self.t = target, self.x, 0
    self.animator:SetScript("OnUpdate", function(_, elapsed)
        Menu.t = math.min(1, Menu.t + elapsed / SLIDE_TIME)
        local e = 1 - (1 - Menu.t) ^ 3
        Menu.x = Menu.from + (Menu.target - Menu.from) * e
        Menu:Place()
        if Menu.t >= 1 then
            Menu.animator:SetScript("OnUpdate", nil)
            if Menu.target < 0 then Menu.cover:Hide() end
        end
    end)
end

function Menu:Scroll(delta)
    self.offset = math.max(0, (self.offset or 0) + delta)
    self:Refresh()
end

-- Same groups and texts as the start screen's list: header, then that group's games
function Menu:Refresh()
    local Games, UI, Style = Yatzy.Games, Yatzy.UI, Yatzy.Style
    local GROUPS = { { "invite", "Invitations" }, { "myturn", "Your turn" },
                     { "waiting", "Waiting for others" }, { "over", "Finished" } }
    local byGroup = {}
    for _, g in ipairs(Games:Sorted()) do
        local key = UI:GroupOf(g)
        byGroup[key] = byGroup[key] or {}
        table.insert(byGroup[key], g)
    end
    local entries = {}
    for _, group in ipairs(GROUPS) do
        if byGroup[group[1]] then
            entries[#entries + 1] = { header = group[2] }
            for _, g in ipairs(byGroup[group[1]]) do entries[#entries + 1] = { game = g } end
        end
    end
    local height = self.list:GetHeight() or 0
    self.offset = math.min(self.offset or 0, UI.MaxScroll(entries, height, HEADER_H, ROW_H + ROW_GAP))
    local y, h, r = 0, 0, 0
    for i = 1 + self.offset, #entries do
        local e = entries[i]
        local need = e.header and HEADER_H or (ROW_H + ROW_GAP)
        if -y + need > height then break end
        if e.header then
            if h >= #self.headers then break end
            h = h + 1
            local hd = self.headers[h]
            hd:ClearAllPoints()
            hd:SetPoint("TOPLEFT", 0, y)
            hd:SetPoint("RIGHT", self.list, "RIGHT")
            hd.text:SetText(e.header)
            hd:Show()
        else
            if r >= MAX_ROWS then break end
            r = r + 1
            local row, g = self.rows[r], e.game
            row.game = g
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, y)
            row:SetPoint("RIGHT", self.list, "RIGHT")
            row.icon:SetTexture(Style.TEX.ui.gameIcon[UI:GameType(g)] or Style.TEX.ui.gameIcon.yatzy)
            row.names:SetText(UI:RowTitle(g))
            row.meta:SetText(UI:RowStatus(g))
            row.current:SetShown(Yatzy.Play.game == g)
            if Games:IsMyTurn(g) or Games:IsInvite(g) then
                row.meta:SetTextColor(1, 0.82, 0.25)
            else
                row.meta:SetTextColor(0.70, 0.64, 0.52)
            end
            row:Show()
        end
        y = y - need
    end
    for i = h + 1, #self.headers do self.headers[i]:Hide() end
    for i = r + 1, MAX_ROWS do self.rows[i]:Hide(); self.rows[i].game = nil end
end
