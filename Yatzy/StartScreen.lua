-- StartScreen.lua
-- The start screen ("hub"): wide buttons for each game on the left (Yatzy, Backgammon),
-- a small panel that asks "vs Guild or vs Computer", your stats, and on the right
-- the list of your games, grouped: Invitations, Your turn, Waiting for others, Finished.

local _, Yatzy = ...
local UI = Yatzy.UI
local Style = Yatzy.Style
local Rules = Yatzy.Rules
local GOLD = Style.TITLE
local DIM = { 0.70, 0.64, 0.52 }

local CARD_W, CARD_H = 236, 52
local ROW_H, ROW_GAP, HEADER_H = 40, 4, 22
local MAX_ROWS, MAX_HEADERS = 10, 4

-- The games of the hub. `ready = false`: shown, but "coming soon".
UI.GAMES = {
    { id = "yatzy", name = "Yatzy", sub = "Dice  ·  1-6 players", ready = true },
    { id = "backgammon", name = "Backgammon", sub = "Board game  ·  2 players", ready = true },
}
local function gameInfo(id)
    for _, info in ipairs(UI.GAMES) do if info.id == id then return info end end
    return UI.GAMES[1]
end

-- Which game a saved game is (everything before the hub was Yatzy)
function UI:GameType(g) return g.game or "yatzy" end

---------------------------------------------------------------------------
-- Texts for the games list
---------------------------------------------------------------------------

local function others(g)
    local Games, Guild = Yatzy.Games, Yatzy.Guild
    local names = {}
    if g.kind == "guild" and (g.status == "pending" or g.status == "cancelled") then
        local me = Guild:MyName()
        for i, name in ipairs(g.invited) do
            if g.answers:sub(i, i) ~= "N" and not Guild:SameName(name, me) then names[#names + 1] = Guild:DisplayName(name) end
        end
    elseif g.players then
        for seat = 1, #g.players do
            if seat ~= g.me then names[#names + 1] = Games:PlayerName(g, seat) end
        end
    end
    return names
end

-- "Yatzy vs Gulki Warr, Father Ghouliath"
function UI:RowTitle(g)
    local names = others(g)
    local game = gameInfo(self:GameType(g)).name
    if #names == 0 then return game end
    return game .. " vs " .. table.concat(names, ", ")
end

-- The second line: what is going on, spelled out
function UI:RowStatus(g)
    local Games, Guild = Yatzy.Games, Yatzy.Guild
    if g.status == "pending" then
        if Games:IsInvite(g) then
            return (g.fast and "Fast game  ·  " or "") .. "Invitation from " .. Guild:DisplayName(g.creator)
        end
        local waiting, declined = {}, {}
        for i, name in ipairs(g.invited) do
            local a = g.answers:sub(i, i)
            if a == "?" then waiting[#waiting + 1] = Guild:DisplayName(name)
            elseif a == "N" then declined[#declined + 1] = Guild:DisplayName(name) end
        end
        local text = (g.fast and "Fast  ·  " or "") .. "Waiting for " .. table.concat(waiting, ", ") .. " to answer"
        if #declined > 0 then text = text .. "  ·  " .. table.concat(declined, ", ") .. " declined" end
        return text
    end
    if g.status == "cancelled" then return "Cancelled: not enough players accepted" end
    if g.status ~= "active" then
        local _, result = Games:Describe(g)
        return "Finished  ·  " .. result
    end
    if g.game == "backgammon" then
        local turn, whose = Games:Describe(g)
        return turn .. "  ·  " .. whose
    end
    local round = ("Round %d/%d"):format(Rules.Round(g), Rules.NUM_TURNS)
    -- fast games: "Fast · Round 3/15 · Gulki's turn · 7 min left"
    local fast, timeLeft = "", ""
    local left = Yatzy.Fast and Yatzy.Fast:TimeLeft(g)
    if left then
        fast = "Fast  ·  "
        timeLeft = left > 60 and ("  ·  %d min left"):format(math.ceil(left / 60)) or "  ·  less than a minute left"
    end
    if Games:IsMyTurn(g) then return fast .. round .. "  ·  Your turn" .. timeLeft end
    return fast .. round .. "  ·  " .. Games:PlayerName(g, Rules.CurrentPlayer(g)) .. "'s turn" .. timeLeft
end

-- Which group of the list a game belongs to
local GROUPS = {
    { key = "invite", title = "Invitations" },
    { key = "myturn", title = "Your turn" },
    { key = "waiting", title = "Waiting for others" },
    { key = "over", title = "Finished" },
}
function UI:GroupOf(g)
    local Games = Yatzy.Games
    if Games:IsInvite(g) then return "invite" end
    if g.status == "pending" then return "waiting" end
    if g.status ~= "active" then return "over" end
    if Games:IsMyTurn(g) then return "myturn" end
    return "waiting"
end

---------------------------------------------------------------------------
-- Building the screen
---------------------------------------------------------------------------

local function createGameCard(parent, info)
    local card = Style.Button(parent, "", CARD_W, CARD_H, "secondary")
    card.info = info
    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetTexture(Style.TEX.ui.gameIcon[info.id])
    icon:SetTexCoord(0, 1, 0, 1)
    card.icon = icon

    local name = card:CreateFontString(nil, "OVERLAY")
    Style.Font(name, "display", 16, Style.TEXT)
    name:SetShadowColor(0, 0, 0, 0.9); name:SetShadowOffset(0, -1)
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -3)
    name:SetText(info.name)
    card.name = name
    local sub = card:CreateFontString(nil, "OVERLAY")
    Style.Font(sub, "display", 9, DIM)
    sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    sub:SetText(info.ready and info.sub or "Coming soon")
    card.sub = sub
    if not info.ready then
        icon:SetDesaturated(true)
        icon:SetAlpha(0.7)
        name:SetTextColor(0.75, 0.70, 0.62)
    end

    -- Gold frame while its panel is open
    local sel = {}
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                         { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local t = card:CreateTexture(nil, "OVERLAY", nil, 6)
        t:SetColorTexture(1, 0.82, 0.35, 0.95)
        t:SetPoint(e[1], -1, e[1]:find("TOP") and 1 or -1)
        t:SetPoint(e[2], e[2]:find("RIGHT") and 1 or -1, e[2]:find("TOP") and 1 or -1)
        if e[3] then t:SetHeight(2) else t:SetWidth(2) end
        t:Hide()
        sel[#sel + 1] = t
    end
    card.selected = sel
    card:SetScript("OnClick", function(self) UI:ChooseGame(self) end)
    return card
end

-- The small panel next to a game card: vs Guild / vs Computer
local function createModePanel(s)
    local cover = CreateFrame("Button", nil, s)           -- click anywhere else: close
    cover:SetAllPoints(s)
    cover:SetFrameLevel(s:GetFrameLevel() + 40)
    cover:SetScript("OnClick", function() UI:CloseModePanel() end)
    cover:Hide()

    local p = CreateFrame("Frame", nil, cover)
    p:SetSize(204, 132)
    p:SetFrameLevel(cover:GetFrameLevel() + 5)
    p:EnableMouse(true)
    Style.LeatherPanel(p, { color = { 0.22, 0.17, 0.14 }, border = 2, stitch = 5 })

    p.title = p:CreateFontString(nil, "OVERLAY")
    Style.Font(p.title, "display", 13, GOLD)
    p.title:SetPoint("TOP", 0, -14)

    p.guild = UI.MakeButton(p, "vs Guild", 170, 44)
    p.guild:SetPoint("TOP", p.title, "BOTTOM", 0, -8)
    p.guild:SetMotionScriptsWhileDisabled(true)
    p.guild:SetScript("OnClick", function()
        local id = p.card and p.card.info.id
        UI:CloseModePanel()
        Yatzy.InviteDialog:Open(id)
    end)
    p.guild:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Play vs Guild")
        if p.card and p.card.info.noGuildYet then
            GameTooltip:AddLine("Coming soon. For now you can play against the computer.", 1, 1, 1, true)
        elseif Yatzy.Guild:InGuild() then
            local bg = p.card and p.card.info.id == "backgammon"
            GameTooltip:AddLine((bg and "Invite one guild member." or "Invite 1-5 guild members.")
                .. " You take turns whenever you're online, like Wordfeud.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Join a guild to play against guild members.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    p.guild:SetScript("OnLeave", function() GameTooltip:Hide() end)

    p.computer = UI.MakeButton(p, "vs Computer", 140, 26, "secondary")   -- narrower than vs Guild
    p.computer:SetPoint("TOP", p.guild, "BOTTOM", 0, -8)
    p.computer:SetScript("OnClick", function()
        local id = p.card and p.card.info.id
        UI:CloseModePanel()
        local g
        if id == "backgammon" then g = Yatzy.Games:NewBGVsComputer() else g = Yatzy.Games:NewVsComputer() end
        if g then
            UI:ShowGame(g.id)
            UI:RefreshStart()
        else
            Yatzy:Print(Yatzy.Games:FullText())
        end
    end)

    p.soon = p:CreateFontString(nil, "OVERLAY")
    Style.Font(p.soon, "display", 11, Style.TEXT)
    p.soon:SetPoint("TOPLEFT", 16, -40)
    p.soon:SetPoint("RIGHT", -16, 0)
    p.soon:SetJustifyH("LEFT")
    p.soon:SetSpacing(3)
    p.soon:SetText("Backgammon is on its way. It will open here, vs guild members or vs the computer.")

    p.cover = cover
    return p
end

function UI:CreateStartScreen(parent)
    local s = CreateFrame("Frame", nil, parent)
    s:SetAllPoints()
    self.start = s

    local left = CreateFrame("Frame", nil, s)
    left:SetPoint("TOPLEFT", 10, -10)
    left:SetPoint("BOTTOMLEFT", 10, 10)
    left:SetWidth(CARD_W)

    -- Soft light behind the title, dark edges (like the prototype's vignette)
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do Style.EdgeShade(s, side, 60, 0.55) end

    -- The name
    local logo = left:CreateFontString(nil, "OVERLAY")
    Style.Font(logo, "title", 34, GOLD)
    logo:SetShadowColor(0.16, 0.10, 0.03, 1)
    logo:SetShadowOffset(2, -3)
    logo:SetPoint("TOP", 0, -16)
    logo:SetText(Yatzy.DISPLAY_NAME)
    self.logo = logo

    -- One wide card per game
    self.gameCards = {}
    local prev
    for i, info in ipairs(UI.GAMES) do
        local card = createGameCard(left, info)
        if prev then card:SetPoint("TOP", prev, "BOTTOM", 0, -8)
        else card:SetPoint("TOP", logo, "BOTTOM", 0, -16) end
        self.gameCards[i] = card
        prev = card
    end
    self.modePanel = createModePanel(s)

    -- Your stats, under the game cards
    local card = Yatzy.Stats:CreateCard(left)
    card:SetPoint("TOP", prev, "BOTTOM", 0, -14)
    self.startLeft, self.startNewGame = left, prev

    -- Right: your games, with "Clear list" above them
    local clear = UI.MakeButton(s, "Clear list", 92, 22, "secondary")
    clear:SetPoint("TOPRIGHT", -10, -8)
    clear:SetScript("OnClick", function() UI:ClearList() end)
    UI.Tooltip(clear, "Clear list", "Remove every game from the list. You're asked first.")
    self.clearButton = clear

    local right = CreateFrame("Frame", nil, s)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 14, -26)
    right:SetPoint("BOTTOMRIGHT", -10, 24)           -- leaves a line under the list for "made by ... v0.x"
    right:EnableMouseWheel(true)
    right:SetScript("OnMouseWheel", function(_, delta) UI:ScrollList(-delta) end)
    self.listArea = right
    self.listOffset = 0

    self.emptyText = right:CreateFontString(nil, "OVERLAY")
    Style.Font(self.emptyText, "display", 12, DIM)
    self.emptyText:SetPoint("TOPLEFT", 4, -14)
    self.emptyText:SetPoint("RIGHT", -10, 0)
    self.emptyText:SetJustifyH("LEFT")
    self.emptyText:SetSpacing(4)
    self.emptyText:SetText("No games yet.\nPick a game on the left to start one, vs guild members or vs the computer.")

    self.moreText = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.moreText:SetPoint("BOTTOMRIGHT", 0, -2)

    -- Addon version, small, bottom-right, with the maker's name to its left
    local version = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    version:SetPoint("BOTTOMRIGHT", -12, 4)
    version:SetText("v" .. Yatzy.version)
    local maker = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    maker:SetPoint("RIGHT", version, "LEFT", -10, 0)
    maker:SetText("made by Herm Berm")
    self.makerText = maker

    -- Group headers ("Your turn" + a thin gold line)
    self.headers = {}
    for i = 1, MAX_HEADERS do
        local h = CreateFrame("Frame", nil, right)
        h:SetHeight(HEADER_H)
        h.text = h:CreateFontString(nil, "OVERLAY")
        Style.Font(h.text, "display", 12, GOLD)
        h.text:SetPoint("BOTTOMLEFT", 2, 5)
        h.count = h:CreateFontString(nil, "OVERLAY")
        Style.Font(h.count, "display", 10, DIM)
        h.count:SetPoint("LEFT", h.text, "RIGHT", 6, 0)
        local line = h:CreateTexture(nil, "ARTWORK")
        line:SetPoint("LEFT", h.count, "RIGHT", 8, 0)
        line:SetPoint("RIGHT", h, "RIGHT")
        Style.ThinLine(line, 1, true)
        line:SetColorTexture(0.80, 0.66, 0.40, 0.45)
        h:Hide()
        self.headers[i] = h
    end

    self.rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, right)
        row:SetHeight(ROW_H)
        Style.LeatherPanel(row, { color = { 0.24, 0.19, 0.16 }, border = 1, stitch = 4 })
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta) UI:ScrollList(-delta) end)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.85, 0.4, 0.08)

        -- game icon
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(28, 28)
        row.icon:SetPoint("LEFT", 7, 0)

        row.names = row:CreateFontString(nil, "OVERLAY")
        Style.Font(row.names, "display", 12, Style.TEXT)
        row.names:SetJustifyH("LEFT")
        row.names:SetWordWrap(false)
        row.meta = row:CreateFontString(nil, "OVERLAY")
        Style.Font(row.meta, "display", 9, DIM)
        row.meta:SetJustifyH("LEFT")
        row.meta:SetWordWrap(false)

        -- Bin icon: remove the game / leave the game
        row.trash = CreateFrame("Button", nil, row)
        row.trash:SetSize(18, 18)
        row.trash:SetPoint("RIGHT", -10, 0)
        local trashTex = row.trash:CreateTexture(nil, "ARTWORK")
        trashTex:SetAllPoints()
        trashTex:SetTexture(Style.TEX.ui.trash)
        local trashHl = row.trash:CreateTexture(nil, "HIGHLIGHT")
        trashHl:SetAllPoints()
        trashHl:SetTexture(Style.TEX.ui.trash)
        trashHl:SetBlendMode("ADD")
        trashHl:SetAlpha(0.5)
        row.trash:SetScript("OnClick", function() UI:RemoveGame(row.game) end)
        row.trash:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(UI:RemoveLabel(row.game))
            GameTooltip:Show()
        end)
        row.trash:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- My invitation, some have accepted, others haven't answered: start without them
        row.startNow = UI.MakeButton(row, "Start now", 92, 22, "secondary")
        row.startNow:SetPoint("RIGHT", row.trash, "LEFT", -8, 0)
        row.startNow:SetScript("OnClick", function()
            local g = row.game
            local names, missing = Yatzy.Guild:StartNowPlayers(g)
            UI:Confirm(("Start now with %s?\n\n%s %s answered and won't be in this game."):format(
                table.concat(names, ", "), table.concat(missing, ", "), #missing == 1 and "hasn't" or "haven't"),
                function()
                    Yatzy.Guild:StartNow(g)
                    UI:RefreshStart()
                end)
        end)
        row.startNow:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Start now")
            GameTooltip:AddLine("Start the game with the players who have accepted. The others are told "
                .. "they didn't make it. Unanswered invitations also run out by themselves after 7 days.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row.startNow:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Invitations: Accept / Decline (instead of the bin)
        row.accept = UI.MakeButton(row, "Accept", 70, 22)
        row.accept:SetPoint("RIGHT", -8, 0)
        row.accept:SetScript("OnClick", function()
            Yatzy.Guild:Answer(row.game, true)
            UI:RefreshStart()
        end)
        row.decline = UI.MakeButton(row, "Decline", 70, 22, "secondary")
        row.decline:SetPoint("RIGHT", row.accept, "LEFT", -6, 0)
        row.decline:SetScript("OnClick", function()
            local g = row.game
            UI:Confirm("Decline the invitation from " .. Yatzy.Guild:DisplayName(g.creator) .. "?", function()
                Yatzy.Guild:Answer(g, false)
                UI:RefreshStart()
            end)
        end)

        row:SetScript("OnClick", function(self, button)
            local g = self.game
            if not g then return end
            if button == "RightButton" then
                UI:RemoveGame(g)
            elseif g.status == "active" or g.status == "over" then
                UI:ShowGame(g.id)
            end
        end)
        row:SetScript("OnEnter", function(self)
            local g = self.game
            if not g then return end
            local tip
            if g.status == "over" then tip = "Left-click to see the score sheet. Right-click to remove it."
            elseif g.status == "cancelled" then tip = "Right-click to remove it."
            elseif g.status == "pending" then tip = "The game starts when everyone has answered."
            elseif g.kind == "guild" then tip = "Left-click to open. Right-click to leave the game."
            else tip = "Left-click to open. Right-click to delete it." end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(UI:RowTitle(g))
            GameTooltip:AddLine(UI:RowStatus(g), 0.85, 0.80, 0.70, true)
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Hide()
        self.rows[i] = row
    end
end

---------------------------------------------------------------------------
-- Choosing a game: the vs Guild / vs Computer panel
---------------------------------------------------------------------------

function UI:ChooseGame(card)
    local p = self.modePanel
    if p.cover:IsShown() and p.card == card then self:CloseModePanel(); return end
    self:CloseModePanel()
    p.card = card
    local info = card.info
    p.title:SetText(info.ready and ("Play " .. info.name) or info.name)
    -- List full: say why instead of showing buttons that can't start anything
    local full = info.ready and not Yatzy.Games:CanCreate()
    local open = info.ready and not full
    p.guild:SetShown(open)
    p.computer:SetShown(open)
    p.soon:SetShown(not open)
    p.soon:SetText(full and Yatzy.Games:FullText()
        or "Backgammon is on its way. It will open here, vs guild members or vs the computer.")
    p.guild:SetEnabled(Yatzy.Guild:InGuild() and not info.noGuildYet)
    p:SetHeight(open and 132 or (full and 120 or 104))
    p:ClearAllPoints()
    p:SetPoint("LEFT", card, "RIGHT", 12, 0)
    p:SetClampedToScreen(true)
    for _, t in ipairs(card.selected) do t:Show() end
    p.cover:Show()
end

function UI:CloseModePanel()
    local p = self.modePanel
    if not p then return end
    p.cover:Hide()
    if p.card then for _, t in ipairs(p.card.selected) do t:Hide() end end
    p.card = nil
end

---------------------------------------------------------------------------
-- Removing games, confirmations
---------------------------------------------------------------------------

-- What the bin icon does for this game
function UI:RemoveLabel(g)
    if not g then return "" end
    if Yatzy.Games:IsInvite(g) then return "Decline the invitation" end
    if g.kind == "guild" and g.status == "pending" then return "Withdraw from this game" end
    if g.kind == "guild" and g.status == "active" then
        return g.game == "backgammon" and "Give up the game" or "Leave the game"
    end
    return "Remove from the list"
end

function UI:RemoveGame(g)
    if not g then return end
    local Guild = Yatzy.Guild
    local function done() UI:RefreshStart() end
    if Yatzy.Games:IsInvite(g) then
        UI:Confirm("Decline the invitation from " .. Guild:DisplayName(g.creator) .. "?", function() Guild:Answer(g, false); done() end)
    elseif g.kind == "guild" and (g.status == "pending" or g.status == "active") then
        local text = g.status == "active" and "Leave this game? Your remaining turns will be struck out."
            or "Withdraw from this game? The others are told you're not playing."
        if g.status == "active" and g.game == "backgammon" then
            text = "Give up this game? " .. Yatzy.Games:PlayerName(g, 3 - g.me) .. " wins."
        end
        UI:Confirm(text, function() Guild:Leave(g); done() end)
    elseif g.kind == "computer" and g.status == "active" then
        UI:Confirm("Delete this game against the computer?", function() Yatzy.Games:Remove(g.id); done() end)
    else
        Yatzy.Games:Remove(g.id)          -- finished or cancelled: no need to ask
        done()
    end
end

-- "Replay" on a game-over panel: a new round with the same players. Against the computer it
-- starts at once. With guild members they all get an invitation to accept or decline. If
-- somebody already started the replay (their invitation reached me), I just go to it. A full
-- list loses its oldest game, after a question.
function UI:ReplayGame(g)
    if not g then return end
    local Games = Yatzy.Games
    local function show(new)
        if new.status == "active" then
            UI:ShowGame(new.id)
        else                                  -- an invitation: back to the list in the main window
            if g.game == "backgammon" and Yatzy.BGBoard.window then Yatzy.BGBoard.window:Hide() end
            UI:ShowStart()
            if Yatzy.mainWindow and not Yatzy.mainWindow:IsShown() then Yatzy.mainWindow:Show() end
        end
        UI:RefreshStart()
    end
    local existing = Games:ReplayTarget(g)
    if existing then show(existing); return end
    local function go()
        local new, why = Games:Replay(g)
        if not new then
            Yatzy:Print(why == "nobody" and "Replay: nobody is left to invite." or Games:FullText())
            return
        end
        if new.kind == "guild" then
            local names = {}
            for i, name in ipairs(new.invited) do
                if i > 1 or not Yatzy.Guild:SameName(name, Yatzy.Guild:MyName()) then names[#names + 1] = Yatzy.Guild:DisplayName(name) end
            end
            Yatzy:Print("Replay: invitation sent to " .. table.concat(names, ", ") .. ". They can accept or decline.")
        end
        show(new)
    end
    if Games:CanCreate() then
        go()
    else
        local old = Games:Oldest()
        UI:Confirm(("You have %d games going, the most you can have. Replay removes your oldest one%s and starts the new round. Continue?")
            :format(Games:CountActive(), old and (" (" .. UI:RowTitle(old) .. ")") or ""), go)
    end
end

-- "Clear list": every game leaves the list, after a question that says what happens.
-- Games vs the computer and finished games are removed, invitations declined, and
-- running or waiting guild games left (the other players are told, as with the bin icon).
function UI:ClearList()
    local Games, Guild = Yatzy.Games, Yatzy.Guild
    local list = Games:Sorted()
    if #list == 0 then return end
    local guildRunning = 0
    for _, g in ipairs(list) do
        if g.kind == "guild" and (g.status == "active" or g.status == "pending") then guildRunning = guildRunning + 1 end
    end
    local text = ("Remove all %d game%s from the list?"):format(#list, #list == 1 and "" or "s")
    if guildRunning > 0 then
        text = text .. ("\n\nYou also leave %d guild game%s that %s still going on (invitations are declined, and the other players are told)."):format(
            guildRunning, guildRunning == 1 and "" or "s", guildRunning == 1 and "is" or "are")
    end
    UI:Confirm(text, function()
        for _, g in ipairs(list) do
            if Games:IsInvite(g) then
                Guild:Answer(g, false)
            elseif g.kind == "guild" and (g.status == "pending" or g.status == "active") then
                Guild:Leave(g)
            else
                Games:Remove(g.id)
            end
        end
        local BGPlay = Yatzy.BGPlay
        if BGPlay.game and BGPlay.game.hidden then BGPlay:Close() end
        UI.listOffset = 0
        UI:RefreshStart()
    end)
end

-- Yes/No question (WoW's standard popup)
function UI:Confirm(text, onYes)
    StaticPopupDialogs["YATZY_CONFIRM"] = {
        text = text, button1 = YES or "Yes", button2 = NO or "No",
        OnAccept = onYes, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    local dialog = StaticPopup_Show("YATZY_CONFIRM")
    -- Our windows are DIALOG strata and come to the front when clicked, so WoW's popup
    -- (also DIALOG) could end up behind them: lift it one strata higher
    if dialog then
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:Raise()
    end
end

---------------------------------------------------------------------------
-- Filling the list
---------------------------------------------------------------------------

-- How far a list can scroll: 0 when everything fits, otherwise just far enough that
-- the last entry shows (entries = headers and rows, with their own heights)
function UI.MaxScroll(entries, room, headerH, rowH)
    local total = 0
    for _, e in ipairs(entries) do total = total + (e.header and headerH or rowH) end
    local offset = 0
    while offset < #entries and total > room do
        total = total - (entries[offset + 1].header and headerH or rowH)
        offset = offset + 1
    end
    return offset
end

function UI:ScrollList(delta)
    self.listOffset = math.max(0, (self.listOffset or 0) + delta)
    self:RefreshStart()
end

function UI:RefreshStart()
    local card = self.modePanel and self.modePanel.card
    if type(card) == "table" and card.info then
        self.modePanel.guild:SetEnabled(Yatzy.Guild:InGuild() and not card.info.noGuildYet)
    end
    -- Stats card: as much as fits between the game cards and the bottom edge
    local top, bottom = self.startNewGame:GetBottom(), self.startLeft:GetBottom()
    Yatzy.Stats:Refresh(top and bottom and (top - bottom - 14 - 4) or nil)

    -- Entries in order: a header for each group that has games, then its games
    local games = Yatzy.Games:Sorted()
    local byGroup = {}
    for _, g in ipairs(games) do
        local key = self:GroupOf(g)
        byGroup[key] = byGroup[key] or {}
        table.insert(byGroup[key], g)
    end
    local entries = {}
    for _, group in ipairs(GROUPS) do
        local list = byGroup[group.key]
        if list then
            entries[#entries + 1] = { header = group.title, count = #list }
            for _, g in ipairs(list) do entries[#entries + 1] = { game = g } end
        end
    end
    self.emptyText:SetShown(#games == 0)
    if self.clearButton then self.clearButton:SetShown(#games > 0) end

    -- As many entries as fit, starting at the scroll position
    local height = self.listArea:GetHeight() or 0
    -- small window: the maker's name would sit on top of the list, so it steps aside
    if self.makerText then self.makerText:SetShown((self.listArea:GetWidth() or 0) >= 330) end
    self.listOffset = math.min(self.listOffset or 0, UI.MaxScroll(entries, height - 12, HEADER_H, ROW_H + ROW_GAP))
    local y, h, r = 0, 0, 0
    local shown = 0
    local width = self.listArea:GetWidth() or 400
    local narrow = width < 330
    for i = 1 + self.listOffset, #entries do
        local e = entries[i]
        local need = e.header and HEADER_H or (ROW_H + ROW_GAP)
        if -y + need > height - 12 then break end
        if e.header then
            if h >= MAX_HEADERS then break end
            h = h + 1
            local hd = self.headers[h]
            hd:ClearAllPoints()
            hd:SetPoint("TOPLEFT", 0, y)
            hd:SetPoint("RIGHT", self.listArea, "RIGHT")
            hd.text:SetText(e.header)
            hd.count:SetText(e.count > 1 and ("(" .. e.count .. ")") or "")
            hd:Show()
        else
            if r >= MAX_ROWS then break end
            r = r + 1
            self:FillRow(self.rows[r], e.game, y, narrow)
        end
        y = y - need
        shown = i
    end
    for i = h + 1, MAX_HEADERS do self.headers[i]:Hide() end
    for i = r + 1, MAX_ROWS do self.rows[i]:Hide(); self.rows[i].game = nil end

    local above, below = self.listOffset, #entries - shown
    if below > 0 or above > 0 then
        -- (plain text: WoW's fonts have no arrow symbols)
        self.moreText:SetText(below > 0 and ("%d more below - scroll"):format(below) or "Scroll up for more")
    else
        self.moreText:SetText("")
    end
end

function UI:FillRow(row, g, y, narrow)
    row.game = g
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, y)
    row:SetPoint("RIGHT", self.listArea, "RIGHT")
    -- One broken game must not hide the others: catch and report errors per row
    local ok, err = pcall(function()
        local invite = Yatzy.Games:IsInvite(g)
        local canStart = Yatzy.Guild:CanStartNow(g)
        row.icon:SetTexture(Style.TEX.ui.gameIcon[self:GameType(g)] or Style.TEX.ui.gameIcon.yatzy)
        local reserve = invite and (narrow and 84 or 160) or (canStart and 136 or 36)
        for _, fs in ipairs({ row.names, row.meta }) do
            fs:ClearAllPoints()
            fs:SetPoint(fs == row.names and "TOPLEFT" or "BOTTOMLEFT", 44, fs == row.names and -7 or 8)
            fs:SetPoint("RIGHT", row, "RIGHT", -reserve, 0)
        end
        row.names:SetText(self:RowTitle(g))
        row.meta:SetText(self:RowStatus(g))
        if Yatzy.Games:IsMyTurn(g) or invite then
            row.meta:SetTextColor(1, 0.82, 0.35)
        else
            row.meta:SetTextColor(DIM[1], DIM[2], DIM[3])
        end
        row.accept:SetShown(invite)
        row.decline:SetShown(invite and not narrow)
        row.trash:SetShown(not invite)
        row.startNow:SetShown(canStart)
    end)
    if not ok then
        row.names:SetText("(unreadable game)")
        row.meta:SetText(tostring(err))
        Yatzy:Print("|cffff5555error|r showing a game: " .. tostring(err))
    end
    row:Show()
end
