-- Settings.lua
-- The "Settings" button in the title bar (left of the sound button) drops down a short
-- list of options under it. Changes are saved right away.

local _, Yatzy = ...
local Settings = {}
Yatzy.Settings = Settings

local ROW_H = 22

-- The options shown, in order. Default kind = checkbox on YatzyDB.options[key]
local OPTIONS = {
    { key = "hideInCombat", label = "Hide the window in combat" },
    { key = "fade",         label = "Fade while I move or fight", levelButton = true,
      tip = "The window fades when the mouse is away and you move or fight. The button on the right sets how see-through it gets." },
    { key = "turnAlert",    label = "On-screen notices (your turn, invites)" },
    { key = "announceYatzy", label = "Announce my Yatzys in guild chat" },
    { key = "helpDeliver",  label = "Help deliver guild games",
      tip = "Keeps a small copy (about 1 KB per game) of your guildmates' games, so their turns still arrive when they are never online at the same time." },
    { key = "sheetDetached", label = "Score sheet in its own window", default = false,
      onChange = function() Yatzy.Sheet:SetDetached(Yatzy.db.options.sheetDetached) end },
    { key = "escCloses",    label = "Escape closes the window",
      onChange = function()
          Yatzy.UI:ApplyEscape()
          if Yatzy.BGBoard.window then Yatzy.BGBoard:ApplyEscape() end
      end },
    { key = "customSounds", label = "Use my own sound files (see README)", default = false },
    { key = "bgDiceFirst", label = "Backgammon: move with the lit die", default = false,
      tip = "One die is lit up: click a lit checker to move it by that die. Click the other die to switch.",
      onChange = function()
          local B = Yatzy.BGBoard
          if B.g and B:IsShown() then B:Deselect(); B:Refresh() end
      end },
    { key = "sound",        label = "Sound", kind = "sound" },
    { key = "scale",        label = "Window size", kind = "scale" },
}

-- `button` opens and closes the panel; the panel hangs under it, inside `parent` (the window).
-- `which`: whose size the "Window size" row changes ("bg" = the backgammon window).
function Settings:AttachToButton(button, parent, which)
    local Style = Yatzy.Style

    local panel = CreateFrame("Frame", nil, parent)
    panel.which = which
    panel:SetSize(290, #OPTIONS * ROW_H + 16)
    panel:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -6)
    panel:SetFrameLevel(parent:GetFrameLevel() + 150)      -- above the resize handles and side menu
    panel:EnableMouse(true)
    Style.LeatherPanel(panel, { border = 2 })
    panel:Hide()

    panel.rows = {}
    for i, opt in ipairs(OPTIONS) do
        local y0 = -8 - (i - 1) * ROW_H
        local row
        if opt.kind == "scale" then
            -- Window size: [-] 80% [+]  Reset   (same as Ctrl + mouse wheel over the title bar)
            row = CreateFrame("Frame", nil, panel)
            row:SetSize(230, ROW_H)
            row:SetPoint("TOPLEFT", 10, y0)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", 4, 0)
            local function step(delta)
                Yatzy.UI:SetWindowScale(Yatzy.UI:WindowScale(which) + delta, true, which)
            end
            row.minus = Yatzy.UI.MakeButton(row, "-", 22, 22, "secondary")
            row.minus:SetPoint("LEFT", 92, 0)
            row.minus:SetScript("OnClick", function() step(-0.05) end)
            row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.value:SetPoint("LEFT", row.minus, "RIGHT", 0, 0)
            row.value:SetWidth(42)
            row.value:SetJustifyH("CENTER")
            row.plus = Yatzy.UI.MakeButton(row, "+", 22, 22, "secondary")
            row.plus:SetPoint("LEFT", row.value, "RIGHT", 0, 0)
            row.plus:SetScript("OnClick", function() step(0.05) end)
            row.reset = CreateFrame("Button", nil, row)
            row.reset:SetSize(44, ROW_H)
            row.reset:SetPoint("LEFT", row.plus, "RIGHT", 6, 0)
            local rt = row.reset:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            rt:SetPoint("CENTER"); rt:SetText("Reset")
            local rhl = row.reset:CreateTexture(nil, "HIGHLIGHT")
            rhl:SetAllPoints(); rhl:SetColorTexture(1, 0.85, 0.6, 0.10)
            row.reset:SetScript("OnClick", function()
                Yatzy.UI:SetWindowScale(1, true, which)
            end)
            Yatzy.UI.Tooltip(row.reset, "Reset the window size", "Back to 100%. You can also use Ctrl + mouse wheel over the title bar.")
        elseif opt.kind == "sound" then
            row = CreateFrame("Button", nil, panel)
            row:SetSize(230, ROW_H)
            row:SetPoint("TOPLEFT", 10, y0)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", 4, 0)
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(); hl:SetColorTexture(1, 0.85, 0.6, 0.08)
            row:SetScript("OnClick", function()
                Yatzy.Sound:NextLevel()
                if Yatzy.UI.UpdateSoundButton then Yatzy.UI:UpdateSoundButton() end
                Settings:RefreshAll()
            end)
        else
            row = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
            row:SetSize(ROW_H, ROW_H)
            row:SetPoint("TOPLEFT", 8, y0)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row, "RIGHT", 2, 0)
            row:SetScript("OnClick", function(self)
                Yatzy.db.options[opt.key] = self:GetChecked() and true or false
                if opt.onChange then opt.onChange() end
                Settings:RefreshAll()
            end)
            if opt.tip then Yatzy.UI.Tooltip(row, opt.label, opt.tip) end
            if opt.levelButton then
                -- How strong the fade is: Low / Medium / High, like the Sound button
                row.fadeButton = Yatzy.UI.MakeButton(panel, "Low", 64, 20, "secondary")
                row.fadeButton:SetPoint("TOPRIGHT", -10, y0 - 1)
                row.fadeButton:SetScript("OnClick", function()
                    Yatzy.UI:NextFadeLevel()
                    Settings:RefreshAll()
                end)
                Yatzy.UI.Tooltip(row.fadeButton, "Fade strength", "Click to change how see-through the window gets: Low, Medium or High. The window shows the new level for a moment.")
            end
        end
        row.opt = opt
        panel.rows[i] = row
    end

    button:SetScript("OnClick", function()
        panel:SetShown(not panel:IsShown())
        Settings:Refresh(panel)
    end)
    parent:HookScript("OnHide", function() panel:Hide() end)

    self.panels = self.panels or {}
    table.insert(self.panels, panel)
    self.panel = panel
    self:Refresh(panel)
    return panel
end

function Settings:Close()
    for _, p in ipairs(self.panels or {}) do p:Hide() end
end

function Settings:Refresh(panel)
    local opts = Yatzy.db.options
    for _, row in ipairs(panel.rows) do
        if row.opt.kind == "scale" then
            local UI = Yatzy.UI
            local scale = UI:WindowScale(panel.which)
            row.text:SetText(row.opt.label)
            row.value:SetText(("%d%%"):format(math.floor(scale * 100 + 0.5)))
            row.minus:SetEnabled(scale > UI.MIN_SCALE + 0.001)
            row.plus:SetEnabled(scale < UI.MAX_SCALE - 0.001)
        elseif row.opt.kind == "sound" then
            local level = Yatzy.Sound:Level()
            local names = { low = "Low", normal = "Normal", high = "High", off = "Off" }
            row.text:SetText("Sound: " .. (names[level] or "Low") .. "   (click to change)")
        else
            local v = opts[row.opt.key]
            if v == nil then v = row.opt.default ~= false end       -- not set yet: the option's default
            row:SetChecked(v)
            row.text:SetText(row.opt.label)
            if row.opt.levelButton then
                local names = { low = "Low", medium = "Medium", high = "High" }
                row.fadeButton:SetText(names[Yatzy.UI:FadeLevel()])
                row.fadeButton:SetEnabled(v)
            end
        end
    end
end

function Settings:RefreshAll()
    for _, p in ipairs(self.panels or {}) do self:Refresh(p) end
end
