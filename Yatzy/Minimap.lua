-- Minimap.lua
-- A round button on the edge of the minimap, with two of our dice on it.
-- Left-click opens or closes the window. Drag it to move it around the minimap.
--
-- If another addon has loaded the standard minimap libraries (LibDataBroker + LibDBIcon,
-- which button-collector addons use), the button is made through them, so collectors show
-- our own picture and tooltip. Otherwise we draw the button ourselves.
-- (The name shown in the tooltip is Yatzy.DISPLAY_NAME in Core.lua: change it there when the
-- addon is renamed.)

local _, Yatzy = ...

local function icon() return Yatzy.Style.TEX.ui.minimap end

-- The tooltip: our name and what's waiting for you
local function fillTooltip(tt)
    tt:AddLine(Yatzy.DISPLAY_NAME, 1, 0.82, 0)
    local Games = Yatzy.Games
    local myTurn, invites = 0, 0
    for _, g in ipairs(Games and Games:All() or {}) do
        if not g.hidden then
            if Games:IsInvite(g) then invites = invites + 1
            elseif g.status == "active" and Games:IsMyTurn(g) then myTurn = myTurn + 1 end
        end
    end
    if myTurn > 0 then
        tt:AddLine(myTurn == 1 and "Your turn in 1 game" or ("Your turn in %d games"):format(myTurn), 0.4, 1, 0.4)
    end
    if invites > 0 then
        tt:AddLine(invites == 1 and "1 invitation waiting" or ("%d invitations waiting"):format(invites), 0.4, 1, 0.4)
    end
    -- (no "click to open / drag to move" lines: every minimap button works that way)
end

local function updatePosition(button)
    local angle = math.rad(Yatzy.db.minimap.angle)
    local radius = (Minimap:GetWidth() / 2) + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

-- While dragging, work out the angle from the minimap's center to the cursor.
local function onDragUpdate(button)
    local centerX, centerY = Minimap:GetCenter()
    local cursorX, cursorY = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cursorX, cursorY = cursorX / scale, cursorY / scale

    Yatzy.db.minimap.angle = math.deg(math.atan2(cursorY - centerY, cursorX - centerX)) % 360
    updatePosition(button)
end

-- The standard libraries, when another addon has loaded them
local function libraries()
    if not LibStub then return end
    local ldb = LibStub("LibDataBroker-1.1", true)
    local dbi = LibStub("LibDBIcon-1.0", true)
    if ldb and dbi then return ldb, dbi end
end

function Yatzy:CreateMinimapButton()
    if self.minimapButton or self.minimapIcon then return end
    local db = self.db.minimap

    local ldb, dbi = libraries()
    if ldb and dbi then
        db.minimapPos = db.minimapPos or db.angle             -- LibDBIcon keeps its own position
        local object = ldb:NewDataObject("Yatzy", {
            type = "launcher",
            text = Yatzy.DISPLAY_NAME,
            icon = icon(),
            OnClick = function() Yatzy:ToggleMainWindow() end,
            OnTooltipShow = fillTooltip,
        })
        dbi:Register("Yatzy", object, db)
        self.minimapIcon = dbi
        return
    end

    local button = CreateFrame("Button", "YatzyMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Dark circle behind the dice.
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)

    -- Two of our dice, filling the round hole of the ring.
    local pic = button:CreateTexture(nil, "ARTWORK")
    pic:SetSize(21, 21)
    pic:SetTexture(icon())
    pic:SetPoint("TOPLEFT", 6, -5)
    button.icon = pic

    -- Gold ring, the same style as Blizzard's minimap buttons.
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function()
        Yatzy:ToggleMainWindow()
    end)

    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", onDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        fillTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    self.minimapButton = button
    updatePosition(button)
    if db.hide then
        button:Hide()
    end
end

function Yatzy:SetMinimapButtonShown(shown)
    self.db.minimap.hide = not shown
    if self.minimapIcon then
        if shown then self.minimapIcon:Show("Yatzy") else self.minimapIcon:Hide("Yatzy") end
    elseif self.minimapButton then
        self.minimapButton:SetShown(shown)
    end
    if shown then
        self:Print("Minimap button shown.")
    else
        self:Print("Minimap button hidden. Type /yatzy minimap to bring it back.")
    end
end
