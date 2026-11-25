# YatzyFiend: Yatzy & Backgammon (WoW: Forever addon)

(Called "Big M's Lucker Yatzy" until 0.12.1. The folder, saved data and `/yatzy` are still named "Yatzy".)

The addon itself is in the `Yatzy` folder. The full plan is in [PLAN.md](PLAN.md), the approved UI prototype in [prototype/index.html](prototype/index.html).

## Installed how?

`World of Warcraft\_forever_\Interface\AddOns\Yatzy` is a **link** (a Windows "junction") to `C:\Yatzy\Yatzy`.
Changes made here show up in the game after a `/reload`. **New files (like the new .lua files in 0.2.0) need a full game restart the first time.**
Deleting the link in the AddOns folder only removes the link, not the files here.

## v0.12.1: games stay in step, new icons, new name

- **New name: YatzyFiend** (title bar, start screen, minimap tooltip, addon list). Folder, saved data and messages are unchanged, see PLAN.md.
- **Out-of-step fix:** the desync we saw in an instance (one player had finished, the others still waited for them). Turn messages could get lost in combat or when WoW held them back, and nothing sent them again. Now: refused messages are retried, the addon compares games with the other players every 45 s while you wait, 8 s after your own turn, after combat and after a loading screen. Messages WoW hides in combat are skipped safely instead of causing errors.
- **Minimap button:** two clean ivory dice (drawn as shapes, since the photo-textured dice turned to mush at 20 px) instead of the placeholder, and a new tooltip (name, "Your turn in N games", invitations; no click/drag help, that's understood). The name comes from `Yatzy.DISPLAY_NAME` in Core.lua: change it there at the rename. With a button-collector addon the button now shows our own picture and text.
- **Title bar:** Settings is now a square cog button; Sound is a speaker (as big as the cog, small waves) that shows 1/2/3 waves for Low/Normal/High and is crossed out when off. Hover tells you the level. Checked that the icons can be read down to about 60 % window size.
- Not seen in WoW yet: whether Forever has the newer "secret values" and chat lockdown (the code handles both cases), and the collector-addon path.
- Latest build: `dist\Yatzy-0.12.1.zip`.

## v0.12.0: Replay

- **Replay** on the game-over panels (see CHANGELOG.md and PLAN.md). Everyone in a guild game should update; players on 0.11.x just see a normal invitation.
- **Fixed:** the score sheet's paper didn't fade (it ignores its parents' opacity, so it now gets the fade itself, in `UI:FadeStep`).
- Latest build: `dist\Yatzy-0.12.0.zip`.

## v0.11.2

- **Stats:** "Against guild members" is now the drop-down **Game record** at the top of the stats card (`YatzyDB.statsOpen = "record"`). It lists your won – lost against the three guild members you play most; the tooltip lists everyone when there are more. Latest build: `dist\Yatzy-0.11.2.zip`.

## v0.11.1

- **Fade strength:** a Low / Medium / High button next to the fade tick box in Settings (Low = the old 45% opacity, Medium 28%, High 14%). Saved as `options.fadeLevel`; clicking it shows the new level for 1.5 seconds.
- Fixed the version/maker line overlapping "more below - scroll" on the start screen: the games list now ends 14 px higher.
- Latest build: `dist\Yatzy-0.11.1.zip`.

## v0.11.0: guild mailmen

Turns and invitations reach you even when you and the other player are never online together: any guildmate with the addon keeps a small copy of the game and hands it over when you log in (setting "Help deliver guild games", on by default). New file (Mail.lua): **restart WoW completely**. Everyone who plays guild games must update. Simulation-tested only, not tried in WoW yet. Latest build: `dist\Yatzy-0.11.0.zip`.

## Where we were before (v0.10.3)

A small **game hub** for WoW: Forever with two games, **Yatzy** and **Backgammon**, each against the computer or a guildmate (turn by turn, also when you're not online together). Fast games (10 minutes per turn) and Poke work in both. The latest build is `dist\Yatzy-0.10.3.zip`; everything new is in [CHANGELOG.md](CHANGELOG.md).

Not seen in WoW yet: the newest backgammon layout and the stats drop-downs (tested in the browser preview and by the test suites).

Next, in the plan ([PLAN.md](PLAN.md)): a new name for the addon, the CurseForge release, and maybe 3D dice. (Guild mailmen are built in 0.11.0.)

## v0.10.3

- **Stats on the main menu:** a drop-down for each game (Yatzy, Backgammon), with the same small + / - buttons as the Window size setting.
- **Backgammon:** Auto finish once the checkers have passed each other, one-click bearing off, Undo (left) and Done (right) beside the dice in the middle of your half, a much bigger lit die in "move with the lit die" mode, you throw the opening roll yourself, the turn line sits above the board, and you can click the next checker before the first has landed.
- New images (Undo and Done icons): **restart WoW completely**. Everyone in a guild game should be on 0.10.3 (the invite list marks other versions as not compatible). Auto finish with a guild player needs 0.10.2 or newer on both sides.

## v0.10.0 (test version for the guild)

The game hub with **Backgammon**, the new start screen and Fast mode. Everything new is listed in [CHANGELOG.md](CHANGELOG.md).
Many new files and images: **restart WoW completely** (not just /reload). Everyone who plays guild games should update; players on 0.9.x don't see backgammon games and keep playing Yatzy as before.

## v0.9.4

- **Docked sheet in a smaller window:** the sheet gets narrower first (score columns down to 30 px), so the table and the sheet stay side by side. It only folds in when even the narrowest sheet doesn't fit next to a 350 px table, or when you fold it yourself with the SCORES tab. Example with 4 players: both visible down to about a 610 px wide window, the full-width sheet from about 680 px.
- **"Pop out" sits on the paper** next to the YATZY title and scrolls away with it. It used to stay pinned and cover the player names when the sheet was scrolled.

## v0.9.3

- **Docked score sheet: narrower score columns** (46 px each, at most 52 px). The sheet is now 250 px for 2 players, 314 for 4 and 406 for 6. In its own window the columns still follow the window's width.

## v0.9.2

- **Fixed: errors in combat with the window open (0.9.1).** In combat WoW gives addons "secret" values for the character's speed, and the new fading compared one, which is an error. Combat now comes from the combat events, which are always allowed. Unreadable values are skipped instead of compared. Fading in combat and while moving works as before.
- **The score sheet in its own window can now be resized sideways too** (bottom-right corner). A wider window gives wider score columns. It can't get narrower than the players need (about 34 px per column), and the width is remembered.
- **The game window and the score sheet window fade together:** they always have the same opacity, and pointing the mouse at either one makes both solid.

## v0.9.1

- **The window can be smaller:** down to 420 × 270 (was 460 × 310). Ctrl + mouse wheel still scales the whole window as well.
- **Breakpoint for small tables:** when the dice table is narrower than 470 px or lower than 270 px, the Saved tray (40 px high, smaller dice), the Roll button and its text get smaller, so the dice keep their room.
- **Small start screen:** in a narrow window, the games list puts the status ("Your turn") on the second line of each game, so the names keep their room.
- **Window frame:** the metal corner plates are gone. The frame is the same bronze band, now with slightly rounded corners. The corner plates on the game-over panel and the invite dialog are gone too, so everything matches.
- New images: **restart WoW completely**.

## v0.9.0

New file images and sounds: **restart WoW completely**. Everyone in a guild game should update.

- **Names:** full names everywhere ("Father Ghouliath is rolling", the invite list, the games list, the results). Only the score sheet columns use first names. Long names in the status line get a slightly smaller font instead of being cut off.
- **The score sheet grows with the players:** every score column keeps the same comfortable width (2 players: 250 px, 4: 354, 6: 466). In a narrow window a wide sheet folds in and slides over the table.
- **Score sheet in its own window:** click "Pop out" (top-right of the sheet) or Settings → "Score sheet in its own window". Drag it by its title strip and change its height with the corner grip; its position is remembered. "Dock" puts it back. It opens, closes and fades together with the game window, and only shows while a game is open.
- **Better fading** (Settings → "Fade while I move or fight (mouse away)"): with the mouse outside the window, it fades whenever your character moves in any way (autorun, click-to-move, follow, falling, swimming, knockbacks) and in combat, even standing still. It never fades on a flight path.
- **Your turn:** the Roll dice button flashes with a yellow border for 3 seconds when your turn starts in the open game.
- **Fixed: a die taken back out of the tray could land on another die.** It now gets a free spot if its old one is taken.
- **Fixed: no "your turn" sound.** The addon first tried your own sound file, and when that file didn't exist, nothing played at all. Built-in sounds now always play unless you turn on Settings → "Use my own sound files". The turn sound also plays when On-screen notices are off, and once with the login notice. The soft chime with the popup is a bit louder.
- **Confirm before striking out:** clicking a field that would get 0 while another open field would score asks first, in a small box above the field (Strike out / Cancel; clicking elsewhere or Escape cancels).
- **Clearer strike-out stroke:** never smaller than about 30 × 5 px, and a bolder line.
- **Guild chat:** the Yatzy line is now just "YATZYYY" (the chat already shows who wrote it).
- **Game over:** the winner's glow is now a soft light shining out from behind the name, gently breathing, instead of a ring.

## v0.8.7

- **Fixed: removed games came back.** A guild game you removed was sent back by the other players' addons the next time you were online together, and it quietly returned (and was counted in the login notice). Removed games are now remembered for 90 days and ignored.
- **Login notice only counts ongoing games** (not removed, left or finished ones), and not games you were already told about this turn. With one game it just says "Your turn vs Gulki!". With several: "Your turn in 3 games: vs Gulki, vs Computer, vs Bo & Cid."
- Games that came back before this fix may still be in your list: remove them once more and they'll stay gone.

## v0.8.6

- **Yatzy in guild chat:** when you roll a Yatzy in a game against guild members, the addon posts "Herm rolled a YATZYYYYY" in guild chat, under your own name. Only the player who rolled it posts, so there are no doubles. It posts at most once per turn and never in games against the computer. Turn it off under Settings → "Announce my Yatzys in guild chat".
- **Up to 6 players:** Play vs Guild lets you pick 1–5 guild members. The score sheet is 30 px wider for each player above 4 (310 px for 6), and long names are cut short in narrow columns. **Everyone in a 5- or 6-player game needs 0.8.6**; older versions ignore those invitations.
- Game invitations now send names without the realm part, so six names fit in one message. Players are matched by first name as before.

## v0.8.5

- The Saved tray and the Roll button are shorter (56 px instead of 70), and the button is narrower (210 px), with at least 16 px between them. Saved dice in the tray are a little smaller to match. The dice get a bit more room on the table.
- New images (tray, button): **restart WoW completely**.

## v0.8.4

- The pause before the dice line up on the last roll is halved (0.6 seconds).
- The score sheet is narrower: 250 px instead of 290, so the dice table gets 40 px more.

## v0.8.3

- **Last roll:** saved dice stay in the tray while the others roll. When everything has landed, the dice lie still for about a second so you can see what you rolled, and only then glide into the row in the middle. (Since 0.7.7 the saved dice jumped to the row as soon as you rolled.)

## v0.8.2

- **Dice never overlap.** Dice land at least 92 px apart (a turned die is 90 px corner to corner). On a short table, like a window sitting on top of the screen, they land in a loose zigzag, one high and one low. Only if even that doesn't fit do the dice get a little smaller (never below 44 px). At the usual small window they stay full size.
- **Saved tray on the left, Roll button on the right**, as big as the tray. On a narrow table the button gets narrower, because the tray needs room for 5 dice.
- **Score sheet:** pinned names now always show when you scroll. Score columns are at most 60 px wide, and the row names get the rest.
- **First names only** for guild players everywhere (sheet, game list, game over, invitations).
- **Games menu:** the big Main menu button is gone. The **Home** button now sits left of "Games".
- **Stats card:** only your guild games are shown. The missing "Games" label is fixed.
- **YATZY glow** now turns with each die (it used to stick out as a straight square behind turned dice).

## v0.8.1

- **Game over:** the winner's line is bigger, in the gold title font, with a soft pulsing glow behind it. On a shared first place, every winner glows.
- Fixed garbled characters in Board.lua (the "·" in the status line and the "—" in the results) and an invisible byte-order mark at the start of Core.lua and Yatzy.toc. Both came from a script used for the version bumps in 0.7.7–0.8.0.

## v0.8.0

- **"Your turn!" popup** in the middle of the screen now uses the Yatzy title font (bigger), with "vs Bo & Cid" underneath. It glides up gently, holds about 3 seconds and fades out. It replaces WoW's raid-warning style text.
- A **very soft glass chime** plays with the popup (Kenney CC0, 8 dB quieter than the other sounds), on top of the usual "your turn" bong.
- New sound file: **restart WoW completely**.

## v0.7.9

- **Sticky score sheet:** when the sheet is too short and scrolls, the players' names stay pinned at the top and the **Total** row at the bottom. Each strip only appears while its real row is scrolled out of view, so a sheet that fits looks the same as before.

## v0.7.8: stats

- **Your Stats** card on the main menu, under the play buttons: games, wins, win rate, average score, best score and Yatzys, in one column for the computer and one for the guild. Saved for your whole account.
- **Against guild members:** your record (won – lost) against the guildmates you play most. It shows in the card when the window is tall enough. Hover the card to see everyone.
- The average and head-to-head start counting from this version. Older games still count in Games, Won, Best and Yatzys.
- New file (Stats.lua): **restart WoW completely**.

## v0.7.7

- **Fixed: saved dice showed late for the other players.** Saving or putting back a die is now sent to the others right away (quick clicks go as one message), so it moves to the tray on their screen before the next roll.
- **Saved dice all sit the same way up** in the tray and in the final row (2, 3 and 6 were sometimes turned sideways).
- **Settings** is now a button in the title bar, left of the sound button. It drops down the options. The old Settings link in the bottom-left corner is gone.
- New setting **"Escape closes the window"** (on by default). Turn it off and only the X or the minimap button closes the window.
- **Roll button:** big "Roll dice" with "2 left" in small text underneath.
- "made by Herm Berm" next to the version on the main menu.
- In narrow windows the title plaque hides so it doesn't cover the title-bar buttons.

## v0.7.6

- **Fixed: false "YATZY!" popups.** When another player scored right after their last roll, the turn moved on during the roll animation; the dice had already reset to 1-1-1-1-1, which looked like five of a kind. The Yatzy check now uses the dice frozen at the moment of the roll. (Five of a kind collected over several rolls in one turn still counts, as in the rules.)
- Live rolls are sent the moment you roll, so the others see the dice at the same time as you.
- Start screen: **Play vs Guild** is the big red button on top; New game vs Computer is smaller underneath.
- In a game: a **Home** button next to "Games" goes straight to the main menu, and the Games menu has a big **Main menu** button at the top.

## v0.7.5

- New sound level **High** (title-bar button: Low → Normal → High → Off). High is boosted and limited (louder at the same peak) and plays on WoW's **Master** channel, so a low "Sound Effects" slider doesn't hold it back.
- `/yatzy soundtest` plays all sounds and reports what WoW could play (added in 0.7.4, when sounds were also made clearly louder).

## v0.7.3

- Fading changed: the window is faded **only while you move your character with the mouse outside the window**. Pointing at the window, or standing still, keeps it solid.

## v0.7.2

- When someone rolls a Yatzy and you're **not looking at that game** (window closed, or another game open), a big **YATZY!** in the title font pops up over the game world with "Name rolled a Yatzy!" and the Yatzy sound. Once per turn; not for old turns caught up at login. Turned off together with "On-screen notices" in Settings.

## v0.7.1

- **Whose turn** is shown big at the top ("Your turn", "Bo is rolling"); round and roll in small text below. "press Roll dice" is gone.
- **Settings** (bottom-left of the start screen and the side menu, folds out): hide the window in combat, fade when the mouse is away, on-screen notices, sound Low/Normal/Off.
- **Yatzy sound** = the friend's "Yatzy!" cut from the recording (`tools/sounds-src/custom`). **Your turn** = a softer, lower "bong".
- Listen to all sounds without WoW: `prototype/sounds.html` (via the preview server).

## v0.7.0: finishing touches

- **Sounds** (minimal, CC0 by Kenney.nl): dice throws, picking up a die, your turn, invitation, Yatzy fanfare. The title-bar button cycles **Sound: Low** (default) → Normal → Off. They follow WoW's sound-effects volume too.
- **Your own Yatzy sound:** put `yatzy.ogg` (or `.mp3`) in `Interface\AddOns\Yatzy\Media\Sounds\Custom\` and restart WoW. Same for `turn.ogg` and `invite.ogg`. See the README.txt in that folder.
- **Window fades** to about half while the mouse is elsewhere, full when you point at it (`/yatzy fade` to turn off).
- **Smaller window:** Ctrl + mouse wheel over the title bar (50–120%), or `/yatzy size 70`.
- The **score sheet slides** in and out; the table grows with it.
- **Games** (title bar, in a game) slides out a **side menu** with your games, New game vs Computer and Play vs Guild.
- **Bigger YATZY celebration**: rays, pop-in title, glowing dice, fanfare.
- Player names on the score sheet are fixed (font loading).

## Testing v0.5.0 (guild games) in game

You need a guildmate (or a second account) with the **same addon version** installed — copy the whole `Yatzy` folder to their `Interface\AddOns`.

1. **Both restart WoW completely** (new files). Your old games vs the computer move to the character you log in with first.
2. Click **Play vs Guild**, tick your friend (online or offline), **Send invites**.
3. Your friend gets a message on screen and an **Invitation** row with **Accept / Decline** in their list. If they were offline, it arrives when you're both online.
4. When everyone has answered, the game starts. The creator plays first.
5. Play a turn: your friend sees your rolls live if they're watching the game, and gets "your turn" when you've written your score.
6. Try it offline: one of you logs out, the other plays a turn, then log back in — within about 30 seconds the turn arrives.
7. Right-click a running guild game to **leave** it (your remaining turns are struck out). Right-click finished/cancelled games to remove them.
8. Dice now bump into each other instead of overlapping; try a small window.

If something doesn't arrive, wait 30 seconds (the guild list refreshes then) and check both have the same version.

**Troubleshooting (v0.5.1+):** `/yatzy sync` sends your guild games to online players right away. `/yatzy debug` shows your name as the addon sees it, how each online guild member will be whispered, and every addon message sent/received — screenshot that if something still doesn't arrive.

Note (WoW: Forever): each client writes realm names differently (one sees "Name-...EU4...", the other "Name-...EU5..."), characters have surnames that only the guild roster shows ("Father Ghouliath" vs the game's "Father"), and whispering failed. **Since 0.6.0 all addon messages go over the guild addon channel** (no names needed), players are matched by first name, and **Play vs Guild only lists guild members who have Yatzy, with their version** (other versions are greyed out). Games from 0.5.x don't carry over to 0.6.0's messages — remove old waiting invitations with the bin icon.

## Testing v0.4.0 in game

1. **Restart WoW completely** (new texture files).
2. Dice, buttons, the window frame and corners, the title plaque, the tray and the SCORES tab are now **images rendered from the browser prototype** (`tools/render-assets.ps1` + `tools/render/assets.html`). They should look like the prototype.
3. Roll a few times: each die flies with its own timing, spin and bounces; they don't all land together.
4. After the 3rd roll the dice line up, sorted, in the **middle** of the table.
5. Strike out a field: the pen stroke should be smooth, not jagged.
6. The "Games" and "X" buttons in the title bar should show their text.

## Testing v0.3.0 (the prototype's look) in game

1. **Restart WoW completely**: there are new files (Style.lua, textures, fonts).
2. Check the look: bronze frame with rivets, leather title bar with a red YATZY plaque, wooden table, red felt tray, wooden dice with gold rims and round gold pips, paper sheet with handwritten numbers.
3. Roll three times: after the 3rd roll all dice glide up into a sorted row at the top.
4. Make the window short: the score sheet gets a thin scroll bar; scroll it with the mouse wheel.
5. If text shows in WoW's normal font instead of the small-caps font (Cinzel), tell Claude — the font file couldn't load and a fallback is used.

Textures: `Yatzy/Media/Textures` (CC0, see `prototype/textures/CREDITS.md`; regenerate with `tools/convert-textures.ps1`). Fonts: `Yatzy/Media/Fonts` (OFL licences included).

## Testing M2a (v0.2.0) in game

1. **Restart WoW completely** (new files were added). Check that Yatzy is enabled under AddOns.
2. Click the dice button on the minimap. The start screen shows "Big M's Lucker Yatzy".
3. Click **New game vs Computer**. The game opens: dice table on the left, score sheet on the right.
4. Press **Roll dice**. Click dice to save them in the tray (click again to put them back). Roll up to 3 times.
5. Hover your column on the score sheet: the points show only on hover; fields worth 0 show a pen stroke. Click to write it in.
6. Watch the computer play its turn live. Try closing the window during its turn: it finishes on its own and you get a "your turn" alert.
7. Resize the window from the left/right/bottom edges and the bottom corners. Make it narrow: the sheet folds in; the SCORES tab slides it over the table.
8. Click **Games** (top left) to return to the list; your game is saved. `/reload` and reopen it.
9. Roll a Yatzy if you're lucky: a big YATZY! appears.
10. If anything goes wrong: copy the BugSack error and paste it to Claude.

## Tests outside the game

Run from `C:\Yatzy` (LuaJIT is at `%LOCALAPPDATA%\Programs\LuaJIT\bin\luajit.exe`):

```
luajit tests/test_rules.lua   # the Yatzy rules
luajit tests/test_ai.lua      # the computer opponent
luajit tests/test_bgrules.lua # the backgammon rules
luajit tests/test_bgai.lua    # the backgammon computer opponent
luajit tests/smoke_ui.lua     # loads the whole addon against a fake WoW API and plays full games (Yatzy and backgammon)
luajit tests/sim_guild.lua    # 2-3 copies of the addon talking to each other: invites, turns, offline catch-up, relays, leaving, backgammon, Auto finish
```
