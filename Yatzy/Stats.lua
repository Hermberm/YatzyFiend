-- Stats.lua
-- Your record, saved for the whole account (YatzyDB.stats):
--   solo / guild = { played, won, best, yatzys, total, counted }
--     total/counted = sum and number of final scores (for the average; older games
--     from before 0.7.8 have no score saved, so they don't count toward it)
--   backgammon.solo / backgammon.guild = { played, won }
--   vs[key] = { name, played, won, lost }   head-to-head per guild member
-- Shown as a small card under the play buttons on the main menu: drop-down sections "Game
-- record" (your record against guild members), Yatzy and Backgammon. Only one is open at a
-- time, so the card stays small; which one is saved in YatzyDB.statsOpen ("record", "yatzy",
-- "backgammon", or "" for none).

local _, Yatzy = ...
local Stats = {}
Yatzy.Stats = Stats

local Rules = Yatzy.Rules

local function bucket(g)
    return Yatzy.db.stats[g.kind == "guild" and "guild" or "solo"]
end

-- A rolled Yatzy (five of a kind) by me
function Stats:AddYatzy(g)
    local s = bucket(g)
    s.yatzys = (s.yatzys or 0) + 1
end

-- A game ended: record it once.
function Stats:Record(g)
    if g.statsRecorded or not g.me or not g.sheets then return end
    g.statsRecorded = true
    local s = bucket(g)
    local mine = Rules.Total(g.sheets[g.me])
    s.played = (s.played or 0) + 1
    s.best = math.max(s.best or 0, mine)
    s.total = (s.total or 0) + mine
    s.counted = (s.counted or 0) + 1
    for _, seat in ipairs(Rules.Winners(g)) do
        if seat == g.me then s.won = (s.won or 0) + 1 end
    end

    -- Head-to-head against each guild member in the game (a tie counts as neither)
    if g.kind == "guild" then
        local all = Yatzy.db.stats
        all.vs = all.vs or {}
        local Guild = Yatzy.Guild
        for seat, name in ipairs(g.players) do
            if seat ~= g.me then
                local k = Guild:Key(name)
                local r = all.vs[k] or { played = 0, won = 0, lost = 0 }
                r.name = Guild:DisplayName(name)
                r.played = r.played + 1
                local theirs = Rules.Total(g.sheets[seat])
                if mine > theirs then r.won = r.won + 1 elseif mine < theirs then r.lost = r.lost + 1 end
                all.vs[k] = r
            end
        end
    end
end

-- Rivals sorted by games played together (most first)
function Stats:Rivals()
    local list = {}
    for _, r in pairs(Yatzy.db.stats.vs or {}) do list[#list + 1] = r end
    table.sort(list, function(a, b)
        if a.played ~= b.played then return a.played > b.played end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

-- The numbers shown for one game, as text
function Stats:Column(s)
    local played = s.played or 0
    local function n(v) return played > 0 and tostring(v or 0) or "–" end
    return {
        played = tostring(played),
        won    = n(s.won),
        rate   = played > 0 and ("%d%%"):format(math.floor((s.won or 0) / played * 100 + 0.5)) or "–",
        avg    = (s.counted or 0) > 0 and tostring(math.floor(s.total / s.counted + 0.5)) or "–",
        best   = n(s.best),
        yatzys = tostring(s.yatzys or 0),
    }
end

---------------------------------------------------------------------------
-- The card
---------------------------------------------------------------------------

local LINE_H = 15
local HEADER_H = 22
local MAX_RIVALS = 3
local VALUE_X = 198                  -- right edge of the numbers

-- The drop-down sections, top to bottom. `numbers(all)` gives the text for each row.
-- "Game record" (rivals = true) lists your won - lost against the guild members you play
-- most, in both games; its rows come from Stats:RivalRows().
local SECTIONS = {
    {
        key = "record", title = "Game record", rivals = true,
        numbers = function() return { count = #Stats:Rivals() } end,
        summary = function(numbers)
            local n = numbers.count
            return n == 0 and "no games yet" or (n == 1 and "1 player" or ("%d players"):format(n))
        end,
    },
    {
        key = "yatzy", title = "Yatzy",
        rows = {
            { key = "played", label = "Games" },
            { key = "won",    label = "Won" },
            { key = "rate",   label = "Win rate" },
            { key = "avg",    label = "Average" },
            { key = "best",   label = "Best" },
            { key = "yatzys", label = "Yatzys" },
        },
        numbers = function(all) return Stats:Column(all.guild or {}) end,
    },
    {
        key = "backgammon", title = "Backgammon",
        rows = {
            { key = "played",   label = "Games" },
            { key = "won",      label = "Won" },
            { key = "rate",     label = "Win rate" },
            { key = "computer", label = "vs Computer" },
        },
        numbers = function(all)
            local bg = all.backgammon or {}
            local col = Stats:Column(bg.guild or {})
            local solo = bg.solo or {}
            col.computer = (solo.played or 0) > 0 and ("%d of %d"):format(solo.won or 0, solo.played) or "–"
            return col
        end,
    },
}

-- Rows and values of the Game record section: the guild members you play most
function Stats:RivalRows()
    local rows, values = {}, {}
    for i, r in ipairs(self:Rivals()) do
        if i > MAX_RIVALS then break end
        rows[#rows + 1] = { key = "r" .. i, label = r.name or "?" }
        values["r" .. i] = ("%d – %d"):format(r.won, r.lost)
    end
    if #rows == 0 then
        rows[1] = { key = "none", label = "No guild games yet" }
        values.none = ""
    end
    return rows, values
end

function Stats:OpenKey()
    local db = Yatzy.db
    if db.statsOpen == nil then db.statsOpen = "yatzy" end
    return db.statsOpen ~= "" and db.statsOpen or nil
end

function Stats:Toggle(key)
    Yatzy.db.statsOpen = (self:OpenKey() == key) and "" or key
    self:Refresh()
    if Yatzy.UI and Yatzy.UI.RefreshStart and Yatzy.UI.start and Yatzy.UI.start:IsShown() then Yatzy.UI:RefreshStart() end
end

function Stats:CreateCard(parent)
    local Style = Yatzy.Style
    local card = CreateFrame("Frame", nil, parent)
    card:SetWidth(210)
    Style.LeatherPanel(card, { color = { 0.20, 0.16, 0.13 }, border = 1, stitch = 4 })
    self.card = card

    local function text(font, size, color, justify, owner)
        local fs = (owner or card):CreateFontString(nil, "OVERLAY")
        Style.Font(fs, font, size, color)
        fs:SetJustifyH(justify or "LEFT")
        fs:SetWordWrap(false)
        return fs
    end
    local GOLD, DIM = Style.TITLE, { 0.70, 0.64, 0.52 }

    local title = text("display", 12, GOLD)
    title:SetPoint("TOPLEFT", 12, -9)
    title:SetText("Your Stats")

    -- One header button per game (click to open or close it) with its rows below
    self.sections = {}
    for i, def in ipairs(SECTIONS) do
        local sec = { def = def, cells = {} }
        local head = CreateFrame("Button", nil, card)
        head:SetHeight(HEADER_H - 2)
        head:SetPoint("LEFT", card, "LEFT", 8, 0)
        head:SetPoint("RIGHT", card, "RIGHT", -8, 0)
        local hl = head:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(); hl:SetColorTexture(1, 0.85, 0.6, 0.08)
        -- the same small "+" / "-" button as in the Window size setting (the click goes to the header)
        local icon = Yatzy.UI.MakeButton(head, "+", 18, 18, "secondary")
        icon:SetPoint("LEFT", 2, 0)
        icon:EnableMouse(false)
        sec.icon = icon
        sec.name = text("display", 11, Style.TEXT, "LEFT", head)
        sec.name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        sec.summary = text("display", 9, DIM, "RIGHT", head)
        sec.summary:SetPoint("RIGHT", head, "RIGHT", -4, 0)
        head:SetScript("OnClick", function() Stats:Toggle(def.key) end)
        sec.head = head
        sec.line = card:CreateTexture(nil, "ARTWORK")
        Style.ThinLine(sec.line, 1, true)
        sec.line:SetColorTexture(0.80, 0.66, 0.40, 0.30)
        local keys = {}
        if def.rivals then
            for n = 1, MAX_RIVALS do keys[#keys + 1] = "r" .. n end
            keys[#keys + 1] = "none"
        else
            for _, row in ipairs(def.rows) do keys[#keys + 1] = row.key end
        end
        for _, key in ipairs(keys) do
            local label = text("display", 10, Style.TEXT)
            local value = text("hand", 14, { 0.95, 0.90, 0.78 }, "RIGHT")
            sec.cells[key] = { label = label, value = value }
        end
        self.sections[i] = sec
        self.byKey = self.byKey or {}
        self.byKey[def.key] = sec
    end

    card:SetScript("OnShow", function() Stats:Refresh() end)
    card:EnableMouse(true)
    card:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Your Stats")
        GameTooltip:AddLine("Click a title to open or close it. Game record: your won – lost against the guild members "
            .. "you play most, in both games (ties not counted). Yatzy and Backgammon: your guild games, saved for your "
            .. "whole account (backgammon also shows your record against the computer). Win rate counts shared first place as a win.", 1, 1, 1, true)
        local rivals = Stats:Rivals()
        if #rivals > MAX_RIVALS then
            GameTooltip:AddLine(" ")
            for _, r in ipairs(rivals) do
                GameTooltip:AddDoubleLine(r.name or "?", ("%d – %d  (%d games)"):format(r.won, r.lost, r.played), 1, 0.86, 0.5, 1, 1, 1)
            end
        end
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return card
end

-- `room` = height available for the card; the rivals part hides when it doesn't fit.
function Stats:Refresh(room)
    if not self.card then return end
    local Style = Yatzy.Style
    local all = Yatzy.db.stats
    local open = self:OpenKey()

    -- Sections, top to bottom: a header, and the rows when it's open
    local y = -28
    for _, sec in ipairs(self.sections) do
        local def = sec.def
        local numbers = def.numbers(all)
        local isOpen = open == def.key
        sec.head:ClearAllPoints()
        sec.head:SetPoint("TOPLEFT", self.card, "TOPLEFT", 8, y)
        sec.head:SetPoint("TOPRIGHT", self.card, "TOPRIGHT", -8, y)
        sec.icon:SetText(isOpen and "-" or "+")
        sec.name:SetText(""); Style.SetText(sec.name, def.title)
        -- closed: a short summary on the right
        sec.summary:SetShown(not isOpen)
        if not isOpen then
            local played = tonumber(numbers.played) or 0
            sec.summary:SetText("")
            Style.SetText(sec.summary, def.summary and def.summary(numbers)
                or (played > 0 and ("%d games · %s"):format(played, numbers.rate) or "no games yet"))
        end
        y = y - HEADER_H
        sec.line:ClearAllPoints()
        sec.line:SetPoint("TOPLEFT", self.card, "TOPLEFT", 10, y + 3)
        sec.line:SetPoint("TOPRIGHT", self.card, "TOPRIGHT", -10, y + 3)
        sec.line:SetShown(isOpen)
        for _, cell in pairs(sec.cells) do cell.label:SetShown(false); cell.value:SetShown(false) end
        if isOpen then
            local rows, values = def.rows, numbers
            if def.rivals then rows, values = self:RivalRows() end
            for _, row in ipairs(rows) do
                local cell = sec.cells[row.key]
                cell.label:SetShown(true); cell.value:SetShown(true)
                cell.label:ClearAllPoints(); cell.label:SetPoint("TOPLEFT", self.card, "TOPLEFT", 12, y - 2)
                if def.rivals then cell.label:SetPoint("RIGHT", self.card, "LEFT", 130, 0) end   -- long names stop before the numbers
                cell.value:ClearAllPoints(); cell.value:SetPoint("TOPRIGHT", self.card, "TOPLEFT", VALUE_X, y)
                -- written again each time: a custom font may still have been loading
                cell.label:SetText(""); Style.SetText(cell.label, row.label)
                cell.value:SetText(""); Style.SetText(cell.value, values[row.key])
                y = y - LINE_H
            end
            y = y - 4
        end
    end
    local tableBottom = -y + 6

    room = room or self.room or 999
    self.room = room
    self.card:SetHeight(tableBottom)
    self.card:SetShown(room >= tableBottom)
end
