-- Portrait.lua
-- A small round picture of a player in a gold ring (like WoW's player frame, our own art).
-- Used in the backgammon window for the opponent; meant for Yatzy's turn box too.
--
-- WoW can only draw a character's face for "units" the game knows: you, your party or raid
-- members, your target. A guildie elsewhere has no unit, so then the picture is their
-- class icon (class from the guild roster; WoW's own icon, only shown in game).
-- Games vs the computer, and players whose class we don't know: one of our dice.

local _, Yatzy = ...
local Portrait = {}
Yatzy.Portrait = Portrait

local CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

function Portrait:Create(parent, size)
    local Style = Yatzy.Style
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    local back = f:CreateTexture(nil, "BACKGROUND")
    back:SetTexture(Style.TEX.ui.portraitBack)
    back:SetAllPoints()
    -- the picture sits inside the ring
    local pic = f:CreateTexture(nil, "ARTWORK")
    pic:SetPoint("TOPLEFT", size * 0.14, -size * 0.14)
    pic:SetPoint("BOTTOMRIGHT", -size * 0.14, size * 0.14)
    f.pic = pic
    local ring = f:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(Style.TEX.ui.portraitRing)
    ring:SetAllPoints()
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        if not self.name then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(self.name)
        if self.note then GameTooltip:AddLine(self.note, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return f
end

-- The unit WoW knows this player as right now (you, party, raid), or nil
function Portrait:UnitFor(name)
    local Guild = Yatzy.Guild
    if not name or not UnitName then return nil end
    if Guild:SameName(name, Guild:MyName()) then return "player" end
    local function check(unit)
        local n = UnitName(unit)
        return n and Guild:SameName(n, name)
    end
    for i = 1, 4 do
        if check("party" .. i) then return "party" .. i end
    end
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do
            if check("raid" .. i) then return "raid" .. i end
        end
    end
    return nil
end

-- Show the player in `seat` of game `g`
function Portrait:Set(f, g, seat)
    if not f or not g or not g.players then return end
    local name = g.players[seat]
    local pic = f.pic
    local Style = Yatzy.Style
    f.name = Yatzy.Games:PlayerName(g, seat)
    f.note = nil
    local function dieIcon()
        pic:SetTexture(Style.TEX.ui.gameIcon.yatzy)
        pic:SetTexCoord(0, 1, 0, 1)
    end
    if g.kind == "computer" and seat == g.computer then
        dieIcon()
        return
    end
    local unit = self:UnitFor(name)
    if unit and SetPortraitTexture then
        local ok = pcall(SetPortraitTexture, pic, unit)
        if ok then
            pic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            return
        end
    end
    local class = Yatzy.Guild:ClassOf(name)
    local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if coords then
        pic:SetTexture(CLASS_ICONS)
        -- a little inside the icon, so its square edge stays under the ring
        local l, r, t, b = coords[1], coords[2], coords[3], coords[4]
        local dx, dy = (r - l) * 0.08, (b - t) * 0.08
        pic:SetTexCoord(l + dx, r - dx, t + dy, b - dy)
        f.note = "Their face shows when you're in a group together."
        return
    end
    dieIcon()
end
