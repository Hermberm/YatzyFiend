-- InviteDialog.lua
-- "Play vs Guild": pick 1-5 guild members and send them an invitation.
-- Offline members get the invitation the next time you're both online.

local _, Yatzy = ...
local Invite = {}
Yatzy.InviteDialog = Invite

local ROW_H = 22
-- How many you can invite: Yatzy you + 5 = 6 players, backgammon exactly 1
local MAX_PICK = { yatzy = 5, backgammon = 1 }
local HINT = {
    yatzy = "Guild members who have Yatzy. Pick 1-5; offline players get it when you're both online.",
    backgammon = "Pick one guild member who has the addon. Offline players get it when you're both online.",
}

function Invite:Create(parent)
    local Style = Yatzy.Style
    local cover = CreateFrame("Frame", nil, parent)
    cover:SetAllPoints()
    cover:SetFrameLevel(parent:GetFrameLevel() + 60)
    cover:EnableMouse(true)                         -- block clicks to the screen behind
    local dim = cover:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints()
    dim:SetColorTexture(0, 0, 0, 0.55)
    self.cover = cover

    local panel = CreateFrame("Frame", nil, cover)
    panel:SetPoint("TOP", 0, -10)
    panel:SetPoint("BOTTOM", 0, 10)
    panel:SetWidth(340)
    Style.LeatherPanel(panel, { border = 4, stitch = 9 })
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do Style.EdgeShade(panel, side, 24, 0.5) end
    self.panel = panel

    local title = panel:CreateFontString(nil, "OVERLAY")
    Style.Font(title, "title", 20, Style.TITLE)
    title:SetPoint("TOP", 0, -14)
    title:SetText("Invite guild members")
    self.title = title

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
    hint:SetWidth(300)
    hint:SetText(HINT.yatzy)
    self.hint = hint

    local list = CreateFrame("Frame", nil, panel)
    list:SetPoint("TOPLEFT", 18, -60)
    list:SetPoint("BOTTOMRIGHT", -18, 78)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) Invite:Scroll(-delta * 3) end)
    if list.SetClipsChildren then list:SetClipsChildren(true) end
    self.list = list

    self.empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    self.empty:SetPoint("TOP", 0, -20)

    self.rows = {}
    for i = 1, 20 do
        local row = CreateFrame("CheckButton", nil, list, "UICheckButtonTemplate")
        row:SetSize(ROW_H, ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row.label = row:CreateFontString(nil, "OVERLAY")
        Style.Font(row.label, "display", 12, Style.TEXT)
        row.label:SetPoint("LEFT", row, "RIGHT", 4, 0)
        row.status = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.status:SetPoint("RIGHT", list, "RIGHT", -2, 0)
        row.status:SetPoint("TOP", row, "TOP", 0, -5)
        row:SetScript("OnClick", function(self)
            Invite:Toggle(self.member, self:GetChecked())
        end)
        self.rows[i] = row
    end

    -- Fast game: a time limit per turn (remembered for next time)
    local fast = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    fast:SetSize(ROW_H, ROW_H)
    fast:SetPoint("BOTTOMLEFT", 16, 48)
    fast.label = fast:CreateFontString(nil, "OVERLAY")
    Style.Font(fast.label, "display", 12, Style.TEXT)
    fast.label:SetPoint("LEFT", fast, "RIGHT", 4, 0)
    fast.label:SetText("Fast game: 10 minutes per turn")
    fast:SetScript("OnClick", function(self) Yatzy.db.options.fastGames = self:GetChecked() and true or false end)
    Yatzy.UI.Tooltip(fast, "Fast game",
        "Everyone has 10 minutes per turn; when time runs out, the computer plays the turn. "
        .. "You can poke the player whose turn it is. The invitation runs out after 5 minutes.")
    self.fastBox = fast

    local send = Yatzy.UI.MakeButton(panel, "Send invites", 130, 26)
    send:SetPoint("BOTTOMRIGHT", -18, 14)
    send:SetScript("OnClick", function() Invite:Send() end)
    self.sendButton = send

    local cancel = Yatzy.UI.MakeButton(panel, "Cancel", 100, 26, "secondary")
    cancel:SetPoint("BOTTOMLEFT", 18, 14)
    cancel:SetScript("OnClick", function() Invite:Close() end)

    cover:Hide()
end

-- game: "yatzy" (default) or "backgammon"
function Invite:Open(game)
    if not self.cover then self:Create(Yatzy.UI.body) end
    self.game = game == "backgammon" and "backgammon" or "yatzy"
    self.title:SetText(self.game == "backgammon" and "Invite to Backgammon" or "Invite guild members")
    self.hint:SetText(HINT[self.game])
    self.picked = {}
    self.offset = 0
    self.searching = true
    Yatzy.Guild:RequestRoster()
    Yatzy.Guild:AskWhoHasYatzy()              -- everyone online with Yatzy answers with their version
    self.fastBox:SetChecked(Yatzy.db.options.fastGames == true)
    self.cover:Show()
    self:Refresh()
    C_Timer.After(4, function()
        Invite.searching = false
        if Invite.cover:IsShown() then Invite:Refresh() end
    end)
end

-- Guild members known to have Yatzy: same version first, online first.
function Invite:Candidates()
    local Guild = Yatzy.Guild
    local list = {}
    for _, m in ipairs(Guild:Members()) do
        local version = Guild:VersionOf(m.name)
        if version then
            m.version = version
            m.compatible = version == Yatzy.version
            list[#list + 1] = m
        end
    end
    table.sort(list, function(a, b)
        if a.compatible ~= b.compatible then return a.compatible end
        if a.online ~= b.online then return a.online end
        return a.name < b.name
    end)
    return list
end

function Invite:Close()
    if self.cover then self.cover:Hide() end
end

function Invite:Scroll(delta)
    local maxOffset = math.max(0, #(self.members or {}) - self:VisibleRows())
    self.offset = math.max(0, math.min(maxOffset, (self.offset or 0) + delta))
    self:Refresh(true)
end

function Invite:VisibleRows()
    return math.max(1, math.min(#self.rows, math.floor((self.list:GetHeight() or 0) / ROW_H)))
end

function Invite:Toggle(member, checked)
    if not member then return end
    local count = 0
    for _ in pairs(self.picked) do count = count + 1 end
    local max = MAX_PICK[self.game or "yatzy"]
    if checked and count >= max then
        if max == 1 then
            self.picked = {}                    -- only one: picking another replaces the choice
        else
            Yatzy:Print(("You can invite at most %d players to one game."):format(max))
            self:Refresh(true)
            return
        end
    end
    self.picked[member.name] = checked or nil
    self:Refresh(true)
end

function Invite:Refresh(keepList)
    if not keepList then self.members = self:Candidates() end
    local members = self.members
    local visible = self:VisibleRows()
    if #members == 0 then
        self.empty:SetText(self.searching and "Looking for guild members with Yatzy..."
            or "No guild members with Yatzy found yet.\nThey show up here once they're online with the addon.")
    else
        self.empty:SetText("")
    end
    for i, row in ipairs(self.rows) do
        local m = members[i + (self.offset or 0)]
        row.member = m
        if m and i <= visible then
            row.label:SetText(Yatzy.Guild:Short(m.name))
            local where = m.online and "|cff7ad36aonline|r" or "offline"
            if m.compatible then
                row.status:SetText(where .. "  v" .. m.version)
                row:Enable()
                row.label:SetAlpha(1)
            else
                -- Different version: can't play together (the games wouldn't sync reliably)
                row.status:SetText(where .. "  |cffff9933v" .. m.version .. " (yours: v" .. Yatzy.version .. ")|r")
                row:Disable()
                row.label:SetAlpha(0.45)
                self.picked[m.name] = nil
            end
            row:SetChecked(self.picked[m.name] == true)
            row:Show()
        else
            row:Hide()
        end
    end
    local count = 0
    for _ in pairs(self.picked) do count = count + 1 end
    self.sendButton:SetEnabled(count > 0)
end

function Invite:Send()
    local names = {}
    for _, m in ipairs(self.members or {}) do
        if self.picked[m.name] then names[#names + 1] = m.name end
    end
    if #names == 0 then return end
    if not Yatzy.Games:CanCreate() then
        Yatzy:Print(Yatzy.Games:FullText())
        return
    end
    local fast = self.fastBox:GetChecked() and true or false
    local game = self.game == "backgammon" and "backgammon" or nil
    Yatzy.Guild:CreateGame(names, { fast = fast, game = game })
    local short = {}
    for _, n in ipairs(names) do short[#short + 1] = Yatzy.Guild:DisplayName(n) end
    Yatzy:Print((fast and "Fast game invitation" or "Invitation") .. (game and " to Backgammon" or "") .. " sent to " .. table.concat(short, ", ") .. "."
        .. (fast and " It runs out in 5 minutes." or ""))
    self:Close()
    Yatzy.UI:RefreshStart()
end
