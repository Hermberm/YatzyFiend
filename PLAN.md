# Yatzy – WoW: Forever addon — Project plan

## Glossary (plain language)

| Term | What it means |
|---|---|
| **Addon** | A folder of text files the game reads at startup to add new UI. It works like a plugin. |
| **Lua** | The simple programming language WoW addons are written in. |
| **API** | The list of commands Blizzard allows addons to use, such as "create a window" or "play a sound". Staying inside it is what keeps us within the rules. |
| **`.toc` file** | The addon's ID card: its name, version, which files to load, and which game version it was made for (the "Interface number"). |
| **Frame** | Any UI element on screen: a window, a button, a text label. It's like a layer or frame in Figma. |
| **Event** | Something the game announces, like "a message arrived" or "you entered combat". The addon can react to it. |
| **SavedVariables** | The addon's memory between play sessions, such as window position and stats. The game saves it to a file when you log out. |
| **Addon message** | A hidden message one player's addon sends to another's. It never shows up in chat. This is how multiplayer works. |
| **Prefix** | A label on addon messages (ours is `YATZY1`) so only our addon picks them up. |
| **GUILD / WHISPER / PARTY channel** | Who receives a message: the whole guild, one person, or your group. |
| **Throttle** | The game's speed limit on how many messages an addon can send. Going over it delays or drops messages. |
| **Host** | The player who created the game. Their addon keeps the official score sheet and passes messages between players. |
| **Commit** | Locking in your turn. It's the moment your chosen score becomes official and gets sent to everyone. |
| **Taint / protected functions** | Blizzard locks some parts of the UI, like casting spells and action bars, so addons can't automate combat. We never touch those. |
| **`/reload`** | A chat command that restarts the UI so code changes take effect without logging out. |
| **Heuristic** | A set of rules of thumb, e.g. "if you have 4 of a kind, go for Yatzy". It's how the computer opponent decides. |

## 1. Goals

- A small, self-contained addon (no library dependencies) for **World of Warcraft: Forever**.
- Click a **minimap button** to open or close the Yatzy window.
- **Solo mode:** play against one computer opponent that uses decent heuristics.
- **Guild mode:** 2–4 guild members play one game together.
- **Scandinavian Yatzy** rules.
- Stats are saved between sessions: games played, wins, best score.

### Not in scope

- Betting of any kind (gold, items, trades). The game is only for fun.
- American Yahtzee rules, extra AI difficulty levels, cross-guild play.
- Anything that automates gameplay or reads or changes chat outside our own addon messages.

## 2. Compliance checklist (check before every release)

| Rule | How we meet it |
|---|---|
| Addon is free | Distributed free on CurseForge/Wago. No paid tier and no in-game donation requests. |
| Code is readable | Plain Lua, not minified or obfuscated. Source is public. |
| Uses only the sanctioned API | Frames, `C_ChatInfo.SendAddonMessage`, SavedVariables. No external programs, memory access or injection. |
| No load on servers or other players | One small message per game action. No messages while idle, apart from a short sync check when a co-player comes online. Messages are whispers between the players in the game. A send queue stays under the client throttle. |
| No gambling | No wager feature, and the UI never mentions gold. |
| No automation | The AI only plays inside our own window. The addon never presses buttons or acts on the game world. |
| No protected functions / taint | We only create our own frames and never hook Blizzard's secure frames. The window can auto-hide in combat. |
| Nothing offensive | No free-text broadcast. Player names come from the game. |

Before release, re-read Blizzard's current **UI Add-On Development Policy** and the ToS.

## 3. Game rules (Scandinavian Yatzy)

- 5 dice, up to 3 rolls per turn. Click dice between rolls to hold or release them.
- 15 turns per player. Each turn you must fill one empty category, and a 0 is allowed.

| Category | Score |
|---|---|
| Ones … Sixes | Sum of dice showing that face |
| **Bonus** | 50 if the upper total is ≥ 63 |
| One Pair | Sum of the highest pair |
| Two Pairs | Sum of two different pairs |
| Three of a Kind | 3 × face |
| Four of a Kind | 4 × face |
| Small Straight | 1-2-3-4-5 = 15 |
| Large Straight | 2-3-4-5-6 = 20 |
| Full House | 3 + 2 of different faces = sum of all dice |
| Chance | Sum of all dice |
| Yatzy | Five of a kind = 50 |

The maximum score is 374. The highest total wins. A tie at the top is a shared win.

## 4. Architecture

```
Yatzy/
  Yatzy.toc         -- metadata, Interface version, SavedVariables: YatzyDB
  Core.lua          -- namespace, events, slash command /yatzy, DB defaults
  Rules.lua         -- PURE logic: scoring, game state, turn flow (no WoW API)
  AI.lua            -- PURE logic: hold decisions + category choice
  UI.lua            -- main window: dice, score sheet, players, buttons
  Minimap.lua       -- self-written minimap button (drag to move, click toggle)
  Comm.lua          -- addon messages: encode/decode, send queue, throttle
  Lobby.lua         -- invites, My games list, resign
  Net.lua           -- turn sync between players (works across offline periods)
tests/
  test_rules.lua    -- run with standalone Lua 5.1 outside the game
  test_ai.lua
```

### Design rules

- `Rules.lua` and `AI.lua` must not call any WoW functions. Then we can test them on Windows with plain Lua 5.1, which is the Lua version WoW uses.
- Solo and guild play use the same game-state object. The only difference is who supplies the dice and decisions: the local player, the AI, or the network.
- `UI.lua` only draws the game state and passes clicks on. It contains no rules.

### Saved data (`YatzyDB`)

```lua
YatzyDB = {
  minimap = { angle = 225, hide = false },
  window  = { point = "CENTER", x = 0, y = 0 },
  options = { hideInCombat = true, acceptInvites = true },
  stats   = { solo  = { played=0, won=0, best=0, yatzys=0 },
              guild = { played=0, won=0, best=0, yatzys=0 } },
  -- options also holds: sound = true, turnAlert = true
}
```

## 5. Computer opponent (one heuristic level)

**Category choice** (after the last roll, or earlier if the hand is already great):
- For each open category, value = points scored + an adjustment.
- Upper section: reward getting 3 or more of a face, since that keeps the 63 bonus on track. Penalize falling below 3 of a face when the bonus is still reachable.
- Penalize using up valuable categories (Yatzy, the straights, Chance) for low scores.
- If every option is poor, put the 0 in the least valuable category, usually Ones or Yatzy late in the game.

**Hold choice:**
- Rule-based targets, in priority order: 4 or more of a kind (go for Yatzy or Four of a Kind) → a straight run of 4 → a full house draw → 3 of a kind → the highest pair for open categories → keep high dice for Chance.
- Only target categories that are still open.

**Feel:** add a short delay (about 0.6–1 s) between the AI's actions using `C_Timer.After`, so the player can follow along.

Enumerating every possible reroll exactly is possible later, but it can cause frame hitches. Stay with the heuristic for v1.

## 6. Guild multiplayer (2–4 players)

### Transport

- **Changed in v0.6.0 after in-game testing:** prefix `YATZY2`, all messages on the **GUILD** addon channel, each with a "to" field (who should answer; `*` = anyone). Whispers failed on WoW: Forever because realm names are written differently per client and characters have roster-only surnames. Guild messages need no names; everyone online with Yatzy hears each turn directly, so no relaying is needed while online.
- Players are identified by **first name** (lower case).
- **Presence ("P")**: at login and when the invite dialog opens, the addon asks "who has Yatzy?"; others answer with their version (random 0.5–3 s delay, at most every 20 s). Remembered in `YatzyDB.players`. The invite dialog lists only these players; a different version is shown greyed out and can't be invited.
- (Original plan: prefix `YATZY1`, whispers between players.)
- Messages are short, colon-separated text, well under the 255-byte limit. Example: `TURN:<gameId>:<turn>:<category>:<dice>:<points>`.
- A send queue in `Comm.lua` spreads messages out to stay under the client's addon-message throttle. Measure the actual limit in game.

### Play style: turn-based, works while players are offline (like Wordfeud)

- You play your turn when it suits you, and players don't need to be online at the same time.
- **Important limitation:** WoW has no server where addons can store data. Wordfeud keeps games on its own server. We can't, so every player's addon keeps **its own full copy** of each game, saved in `YatzyDB.games`.
- A finished turn travels to other players **the next time your addon and theirs are online at the same time**. That can be any time either of you is logged in, even if you're out questing and the Yatzy window is closed. It happens automatically in the background.
- In 3–4 player games, **any player who has received a turn passes it on**. So if Anna plays, then logs off, Bo (online) can deliver Anna's turn to Cid later.
- If two players' play times *never* overlap, their turns can't reach each other. That is what the "guild mailmen" design below fixes (designed 2026-11-11, not built).

### Turn order without a host

- No one needs to be the boss. The turn order is fixed when the game starts: turn 1 = seat 1, turn 2 = seat 2, …, and then it wraps around.
- So exactly one player can play turn N. Two players can never "both play" the same turn, and copies of a game can never disagree. They can only be *behind*.
- Each committed turn contains: gameId, turn number, category, final dice, points. Every client checks it: right player for this turn, category still empty, points match the dice.
- Cheating: a player could fake their own dice. That's acceptable among guildmates.

### Catching up (sync)

- When you log in, and when a guild member comes online, your addon whispers a short `HI` to each online player you share games with. It says "for game X I have N turns".
- If the other player has more turns, they send you the ones you're missing. If you have more, you send yours.
- **Guild mailmen:** see the next section.

### Guild mailmen (designed and built 2026-11-11 as v0.11.0; simulation-tested, not tried in game yet)

**As built (differences from the design below):**
- New file `Mail.lua` (after Guild.lua in the .toc). Parcels live in `YatzyDB.mail[gameId]`.
- **The player asks, the mailman answers** (pull, not push). 12 seconds after login `Mail:Ask()` sends `MQ` ("any invitations for me?") and one state message to everybody for each of my games where someone else is offline. A mailman that has more answers after a random 1.5-8 s wait. `Comm` handlers now also get `addressedToAll` as a 4th argument.
- Marker `M`: 8th field on `S`/`BS`, 4th on `T`/`BT`. `Guild:OnState` and `OnTurns` accept it from someone who isn't in the game; everything is still checked by the rules.
- A parcel is thrown away after 14 days without news (a finished game can't be recognised by a mailman), at most 40 parcels, the oldest news goes first.
- **Suppression:** a mailman cancels his waiting delivery when he hears a turn message with the marker for the same game. (The simulator runs all timers at once, so only the "two deliver, the player still gets it right" case is tested.)
- `Guild:SendTurns` now also stops at about 190 characters per message (long backgammon turns could pass 250 before).
- A player is only re-asked at login. A mailman who logs in later doesn't get asked until the next login of a player. A possible later improvement: ask again every 15 minutes while a game is waiting.
- Tests: `sim_guild.lua` step 23 (turn delivered after the author logged off, invitation and answer through a mailman, the setting off keeps nothing, outsiders and fake marker turns are ignored, backgammon parcels, a long parcel fits the message limit).

**Original design (2026-11-11):**

**The problem today.** A turn only reaches the other player while both are online at some moment. In a 2-player game, if Anna plays and logs off, and Bo logs in an hour later, nothing arrives until they happen to be online together. Every game of backgammon is a 2-player game, so it hits those most.

**The idea.** Any guild member who has the addon, even one who is not in the game, keeps a small "parcel" for each game they overhear, and hands it over when a player of that game comes online. Nothing new has to be *sent* to make that work: all turns and states already go over the guild channel to everybody (`Comm:Send("*", ...)`), so every addon online already hears them.

**What a mailman keeps** (`YatzyDB.mail[gameId]`, only for games they are not in):
- game type, creator, invited names, answers, left flags, fast flag (the same fields as the state message)
- the turns, as the short strings that are sent today (Yatzy `catLetter + dice + points`, backgammon `dice + moves`), by turn number
- when it was last updated
- Size: about 1 KB per game, so 40 parcels are about 40 KB.

**Handing over.**
1. A player comes online. Today `Guild:OnRosterUpdate` -> `SyncWith(name)` already runs for the players of my own games. The mailman does the same for the players in his parcels, after a random 3-10 second wait.
2. He sends the normal state message for the game to that player, with a marker saying "from a mailman" (8th field `M` on the state, 4th field `M` on turns).
3. The player's addon works like today: if the mailman has more turns, the player replies with *his* state, and the mailman answers with the missing turns (`SendTurns`). If the player has more, the mailman stores them. The existing "no endless ping-pong" rule stays.
4. **Several mailmen online at once:** each waits a random time and cancels if he hears a mailman message for the same game and player with the same or more turns in the meantime. Normally one delivers, not five.

**Receiving side changes** (small):
- `OnState` / `OnTurns` now require the sender to be a player of the game. With the marker `M` the sender may be anyone with the addon. Everything that arrives is still checked by the rules (right player, category free, points match the dice, every backgammon move legal), so a mailman can't make a wrong game, only delay one.
- A new game (an invitation) can arrive from a mailman too, so invitations to a player who is offline work the same way. Accept/decline answers travel back as normal state messages and the mailman merges them (`mergeFlags`, and the creator's "X" wins, as today).

**Limits and clean-up.**
- At most 40 parcels. A finished game's parcel is dropped after 3 days, an unfinished one after 14 days without news (invitations already run out after 7).
- The mailman never plays or changes anything. He only copies.
- Setting "Help deliver guild games" in Settings, **on by default**, with a tooltip: "Keeps a small copy of your guildmates' games so their turns arrive even when they're not online together. Uses about 1 KB per game."
- Players on versions without mailmen are unaffected: they ignore the marker, and can still use the old online-together sync. Only the receiving player and at least one mailman need the new version.

**What it can't do.** A turn only gets stored if at least one mailman was online when it was sent, and delivered only if one is online when the next player logs in. In a guild with a few people on at most times this works well; in a very quiet guild it helps less. Ideas for later: a "stored by N guildmates" mark next to "Waiting for Bo" in the games list (needs a tiny acknowledgement message from the mailman), and mailmen topping each other up when one logs in.

**Build steps** (about a day):
1. `Mail.lua`: parcels (store, merge, expire) and the hand-over with the random wait and the cancel rule.
2. Hook it into `OnState` / `OnTurns` (store what is overheard) and `OnRosterUpdate` (deliver).
3. Relax the sender check for the marker `M`.
4. Setting + tooltip.
5. `tests/sim_guild.lua`: three copies; Anna plays, Bo is offline, Anna logs off, Bo logs in and gets the turn from Cid. Also an invitation delivered that way, a mailman with an old parcel, and two mailmen online (only one delivers).
6. Version 0.11.0; mention in the changelog that everyone should update.

### My games list (like Wordfeud's home screen)

- The Guild tab shows all your games: **Your turn**, **Waiting for Bo**, **Waiting for invite answers**, **Finished**, plus the last-activity time.
- Limit: about 10 active games per player, to keep the saved data small.
- A player can **resign**. A game with no activity for 14 days can be closed from the list.

### Starting a game

1. Click "New game" and pick 1–3 guild members from the guild roster.
2. Each invitee gets the invite the next time you're online at the same time. It's delivered the same way as turns.
3. They accept or decline. The game starts when everyone has answered: the players who accepted play, and seat order is the order they were invited. With only one player left, the game is cancelled.

### Live view of other players' turns (spectating)

- If you're online while another player takes their turn, you see their dice live: each roll, what they hold, "Bo is rolling… (2/3)".
- Their client sends `R` after each roll, display only. If you're offline you just get the final turn later, and nothing is lost.

### Your-turn notification

- **When a turn arrives while you're online and it's now your turn:** a sound (you can turn it off), the minimap button flashes, "Your turn vs Bo!" appears in the middle of the screen, and the taskbar icon flashes if WoW is in the background.
- **When you log in:** one chat line, "Yatzy: it's your turn in 2 games", and the minimap button flashes.
- The window never opens by itself.

### Data safety

- WoW only writes saved data to disk at logout or `/reload`. If the game crashes, your last turns may be lost **on your PC**, but any turn already delivered to another player is safe with them and comes back at the next sync.

### Message list (v1)

| Code | Direction | Meaning |
|---|---|---|
| `INV` / `ACC` / `DEC` | player ↔ player | Invite / accept / decline |
| `GAME` | any → any | Game header: gameId, players, seat order (for catch-up) |
| `HI` | any → online co-players | "For game X I have N turns" |
| `TURN` | any → any | One committed turn: gameId, turn #, category, dice, points |
| `R` | active → online co-players | Live roll (display only) |
| `RES` | any → any | Player resigned |

## 7. UI design (from the designer)

The clickable prototype is in `prototype/index.html`. When the prototype and this section disagree, this section wins.

### Window: horizontal and resizable

- **Landscape window**, default 780 × 460.
- **Resize by dragging the edges** (left, right, bottom) or the bottom corners. Only the window gets bigger or smaller; the **content keeps its size** (dice, text, score sheet). In WoW that's `SetResizable` + `SetResizeBounds` with drag handles, not `SetScale`. Size and position are saved.
- **The score sheet keeps its width (290)**; the dice table gets the rest of the space. Dice outside the shrinking table move to free spots, and the idle dice row tightens its spacing.
- **Minimum sizes:** the window can go down to 460 × 340. The table needs at least 420 px width and 320 px height.
- **Never horizontal scrolling.** Only vertical scrolling, when the window is shorter than the game needs. The sheet scrolls on its own if it's too tall.
- **Narrow windows (< 420 + 290 px): the sheet folds in automatically.** Clicking the SCORES tab then slides the sheet **over** the table instead of squeezing it, and after you write a score it slides away again. When the window gets wide enough again, the sheet goes back to what the player chose last time in a wide window.
- Narrow windows get a shorter Roll button label ("Roll (2)").
- Use cases: a **small window tucked in a monitor corner** while playing, up to a big window on a large screen.

### Start screen (no game open)

```
+--------------------------------------------------------------+
| Yatzy                                                   [🔊] X |
|--------------------------------------------------------------|
|    YATZY              |  ACTIVE GAMES                         |
|                       |  > Anna, Bo, You   Round 6   Bo's turn|
|  [ Create game ]      |  > You, Computer   Round 2  YOUR TURN |
|  [ Join game   ]      |  > Cid, You        Finished · Cid won |
+--------------------------------------------------------------+
```

- **Create game** → choose *vs Computer* or *vs guild members* (pick 1–3 from the guild roster, which sends invites).
- **Join game** → a fallback when you don't get an invite. It shows open games that guild members have announced (one short message on GUILD when created as "open"), or lets you type a game code.
- **Sound toggle** (🔊/🔇) in the title bar, saved between sessions.
- **Active games list:** players' names, turn number, whose turn it is. Click a row to open that game.

### Game screen: dice table + paper score sheet

```
+--------------------------------------------------------------+
|[≡] Yatzy                                                [🔊] X |
|--------------------------------------------------------------|
|  Your turn · Roll 1/3                 |◀| +------------------+ |
|        ⚄            ⚂                 |S| |      YATZY       | |
|                 ⚅                     |C| | Ones     2   .   | |
|     ⚀                                 |O| | Twos     .   4   | |
|                     +--------------+  |R| | ...              | |
|  [ Roll dice (2 left) ]  | ⚂  ⚂ (saved) |  |E| | Total   44   9   | |
|                     +--------------+  |S| +------------------+ |
+--------------------------------------------------------------+
```

**Dice table (left):**
- Top-down view of the 5 dice. The dice are **64 px** at 1× scale.
- **Rolling:** the dice tumble across the table, bounce, and land at random spots that don't overlap. The top face shows the result.
- **Click a die on the table** → it slides into the **saved tray** (bottom right of the table) and isn't rolled again.
- **Click a die in the tray** → it goes back to the table and is rolled next time. *(Assumed; confirm.)*
- **Roll dice** button with rolls left. It's disabled after the 3rd roll and when it's not your turn.
- When it's another player's turn and you're online, you watch their dice roll live, with "Bo is rolling… (2/3)".

**Score sheet (right, always visible, can fold in):**
- Looks like a **real piece of paper** taped to the table: cream paper, blue ruled lines, red column lines, a printed "YATZY" header and printed category names.
- Scores are **handwritten**, in blue ink for you and graphite for others. A new score is "written in" with a short left-to-right animation and a pencil-scratch sound.
- **A field worth 0 is struck out** with a hand-drawn pen line, like on a real sheet: you have to strike a field when your roll fits nowhere. A missed bonus is struck out too.
- **Your column is marked with yellow highlighter.** The active player's name is underlined.
- **To score:** after rolling, **nothing shows on the empty cells**. Hovering one of your empty cells highlights it and shows the points it would give; if it would give 0, it shows the strike line instead. A click writes it in (or strikes it).
- **Fold button:** a "SCORES" tab on the sheet's left edge folds the sheet out to the right, and the table grows to the full width. The tab stays at the window edge to fold it back in. When you must pick a score while the sheet is folded, the tab pulses.
- Dice that would end up under the sheet when it unfolds move to free spots.
- The open/folded state is remembered.

### Side menu (left, fold-out)

- A small `≡` button on the left edge. Click it and a panel **slides out from left to right** over the game.
- Contains **Create game** and the **active games list** (players, turn number, whose turn). Click a game to switch to it.
- The **mute button** sits to the right side of the panel header.
- Closes by clicking `≡` again or clicking outside the panel.

### WoW UI feasibility notes

| Idea | Possible? | How |
|---|---|---|
| 3D rolling dice | **Yes, as pre-rendered animation** | Addons can't show custom 3D models. Instead each die plays a **flipbook**: a sheet of pre-rendered images of a tumbling die (like a GIF), while the addon moves and rotates it across the table. It looks 3D. |
| Random landing spots, bounce | Yes | Movement animation with easing. We pick spots that don't overlap. |
| Click to save die / tray | Yes | Simple slide animation. |
| Fold-in score sheet | Yes | Slide animation; the table's width follows. |
| Handwritten numbers | Yes | Addons can include their own font file (`.ttf`). It must be a font whose license allows redistribution, e.g. a free OFL-licensed handwriting font like "Caveat" or "Patrick Hand". Windows' Segoe Print (used in the prototype) can't be included. |
| "Writing in" animation | Yes | Reveal the number left to right (animated width/clip), plus a sound. |
| Resizable window, content keeps its size | Yes | `SetResizable` + `SetResizeBounds` and drag handles on the edges; layout recalculated on resize, a `ScrollFrame` below the minimum size. |
| Dice land without a final spin | Yes | Keep the exact end angle after a roll; only "straighten" dice to the nearest whole turn when they move into the tray. |
| Slide-out side menu | Yes | Slide animation, clipped to the window edge. |
| Hover previews, highlighted column | Yes | Standard. |

Other things to know:
- New image files are only picked up after a **full game restart**, not `/reload`. Code changes only need `/reload`.

## 7b. Art asset spec (for the AI-generated graphics)

**Format rules for WoW textures:**
- **File type: `.tga`** (32-bit, with transparency/alpha) or `.blp`. PNG and JPG **don't work** in WoW. Export as PNG from the AI tool and Claude converts it.
- **Size must be a power of two** on each side: 64, 128, 256, 512 or 1024 px, e.g. 512×512 or 1024×512.
- Transparent background around dice and UI pieces.
- Keep the total size of all art small (a few MB). The addon should stay lightweight.

**Assets needed:**

| Asset | Description | Suggested size |
|---|---|---|
| Die faces | Top-down view of a **wooden die with a gold metal rim and inlaid gold pips**, showing 1–6, one image each or all 6 on one sheet | 128×128 per face (sheet 512×256 for 6) |
| Rolling flipbook | ~16 frames of the same wooden/gold die tumbling, seen from above, in a grid (4×4) | 512×512 sheet, 128 px per frame |
| Material textures | Tileable: dark leather, brushed aged bronze, dark wood grain (table), red felt (tray), paper fibres | 256×256 or 512×512 each |
| Die shadow | Soft round shadow under each die | 64×64 |
| Table surface | The play area background (e.g. tavern table, felt, worn wood) | 512×512, tileable or stretched |
| Saved tray | Dish/tray where held dice sit | 256×128 |
| Score sheet paper | Cream paper with ruled lines and a little wear; a tape strip | 512×1024 (paper), 128×64 (tape) |
| Fold tab | Small vertical tab with arrow for folding the sheet | 64×256 |
| YATZY! banner | Big celebratory text/emblem | 512×256 |
| Icons (optional) | Mute/unmute, menu `≡`, minimap dice icon | 64×64 each |

**Style and legal:** "fits WoW's look" (fantasy, hand-painted, warm wood, gold trim) is fine. But **don't copy Blizzard art, logos or characters**, and don't ask the AI tool to reproduce specific Blizzard assets. Also check the AI service's terms to make sure you can use the images in a free public addon.

**Plan:** M2 is built first with **simple placeholder dice** (numbered squares), so the gameplay and layout can be tested. The art is swapped in when it's ready, and the code won't care which images it shows.

### Open design questions

- Clicking a saved die returns it to the table? (assumed yes)
- Does the side menu overlay the game (assumed), or push it to the right?
- Where is vs-Computer shown in the active games list: the same list, or a separate section?
- Which handwriting font (it must be free to redistribute).

## 7d. Visual style direction

- **Mood:** dark fantasy / slightly gothic game UI, in **dark browns** (wood, leather, dark panels) with **aged bronze/iron metal trim** and **deep red** accents. Inspired by the general feel of ornate fantasy game UI kits, without copying any of them.
- **Detail through materials, not ornaments (designer feedback):** the UI should feel detailed and **realistic rather than flat vector graphics**: wood grain, leather, brushed metal, felt, paper fibres, light and shadow. But no filigree scrolls, gems, diamond end caps or heavy "greebling"; that looked "too AI".
- **Window frame:** a bevelled band of **brushed, aged bronze**, plus L-shaped brushed-metal corner plates with one shaded rivet each.
- **Title bar:** a dark **leather strip with a stitched seam**. A red lacquered name plaque with a metal rim and soft gloss sits in the middle.
- **Buttons:** **lacquered deep red** with a soft top gloss, a brushed-metal rim and engraved small-caps text. Secondary buttons are dark leather with the same rim. Pressed buttons sink in.
- **Panels:** dark leather texture; list rows and the status bar have stitched edges.
- **Table:** dark wood with visible grain and darkened edges.
- **Saved tray:** a brushed-metal rim with a **red felt lining**.
- **Dice:** **carved wood** (each die shows a different part of the grain), a **gold metal rim** and **inlaid gold pips** that look slightly recessed.
- **Score sheet:** paper with fibres and slightly darker, worn edges.
- **The addon's art is rendered from the browser prototype** (designer feedback: the browser look was much nicer than re-building it from tinted textures in WoW). `tools/render/assets.html` draws each piece with the prototype's CSS; `tools/render-assets.ps1` screenshots it with headless Edge (2x, transparent) and converts to .tga: dice (5 wood variants, drawn with margin so they can rotate), pips, saved-glow, buttons per size, window frame bands + corner plates, title plaque, tray, fold tab, strike stroke. Tiled backgrounds (table wood, leather, paper) still come from `tools/convert-textures.ps1`.
- **Rolls feel human:** each die gets its own start delay (some leave together), speed, spin (gentle hop or hard spin) and 1–3 bounces, new every throw; the whole throw still takes ~0.85 s. After the 3rd roll the dice glide into a sorted row in the **middle** of the table.
- The prototype uses **real photo textures** (CC0, from Poly Haven) for the table wood, dice wood, leather, felt and metal; see `prototype/textures/CREDITS.md`. They're toned with color overlays and shading. The paper still uses a generated texture. For the addon they get converted to `.tga`, scaled down, or replaced by the AI art in section 7b.
- Viewing the prototype: double-click `prototype/index.html` in any browser. Inside Claude's browser pane it's served by `.claude/serve-prototype.ps1` (a tiny local PowerShell web server on http://localhost:8765, configured in `.claude/launch.json`).
- **Game title:** WoW's own **Morpheus** font (the designer's choice), on the start screen and in the title bar plaque, which shows the full name ("YatzyFiend" since 0.12.1, was "Big M's Lucker Yatzy").
- **Type:** a small-caps display font for other headings, buttons and labels; the prototype uses "Cinzel" (OFL, free to bundle). Handwriting font on the score sheet only.
- The paper score sheet stays light and warm, as the one bright element against the dark UI.

## 7c. YATZY celebration

This plays whenever a player rolls five of a kind, both in solo games and for every player in a guild game.
- A large "YATZY!" banner over the window that scales up, then fades out after about 2.5 s. It uses the `AnimationGroup` API.
- The five dice bounce or glow, and a fanfare plays. The sound uses the game's built-in sounds through `PlaySound`, and the option to turn it off is in `YatzyDB.options`.
- When another player rolls it, everyone sees "Jaina rolled a YATZY!". It's triggered by the live `R` message, with the `C` commit as a fallback.
- The 50 points get a gold highlight on the score sheet.
- Stats: a count of Yatzys rolled is saved in `YatzyDB.stats`.
- Guild chat (designer's decision, v0.8.6): when you roll a Yatzy in a guild game, your own client posts one line, "<FirstName> rolled a YATZYYYYY", in guild chat. Never in games vs the computer, at most once per turn, and only the roller posts (so there are no doubles). It can be turned off in Settings ("Announce my Yatzys in guild chat"). Nothing else is ever posted automatically.

## 8. Development environment

- Find the Forever install folder and its `Interface\AddOns`. Link or copy the `Yatzy` folder there.
- Get the `.toc` interface number in game with `/run print((select(4, GetBuildInfo())))`.
- VS Code + Lua language server + WoW API annotations.
- Error capture with the BugGrabber and BugSack addons. Use `/reload` after each change.
- **LuaJIT 2.1** (Lua 5.1 compatible, installed with `winget install DEVCOM.LuaJIT`) for `tests/`. Run from `C:\Yatzy`: `luajit tests/test_rules.lua`, `tests/test_ai.lua`, and `tests/smoke_ui.lua` (loads the whole addon against a fake WoW API and plays a game; catches crashes but not visual problems).
- git for version control.

## 9. Milestones

| # | Milestone | Done when |
|---|---|---|
| M0 ✅ | Skeleton | Addon loads, minimap button toggles an empty window, `/yatzy` works. **Verified in game 2026-11-07, no errors.** |
| M1 ✅ | Rules engine | All 15 categories + bonus scored correctly; tests pass outside the game. **`Yatzy/Rules.lua` + `tests/test_rules.lua`, 74 tests passing (LuaJIT).** |
| M2a ✅ | Solo vs AI, playable | Full game vs the computer in the real window with placeholder graphics: resizable window, start screen + saved games list, dice table + tray, paper sheet with hover/strike, fold tab + auto-fold, live computer turns. **v0.2.0 verified in game 2026-11-07.** |
| M2b ✅ (v0.7.0–0.7.4, sounds verified in game) | Feel | Tumbling rolls with collisions; sheet slide; side menu; minimal CC0 sounds (Kenney) in Low/Normal + custom sound files; bigger celebration; window fade + Ctrl-wheel scale |
| M2c (first pass ✅, final art pass later) | Art | Textures converted to .tga, wooden dice art, handwriting font, frame/leather/metal look from the prototype. **Built (v0.3.0): photo textures as .tga (tools/convert-textures.ps1), generated pips/shadow/rivets/stitching/paper, Cinzel + Patrick Hand fonts, styled buttons and panels; also: dice line up sorted after the 3rd roll, sheet scrolls in short windows (min height 310). v0.4.0 (art rendered from the prototype, human-like rolls) verified in game 2026-11-07.** |
| M3 | Polish + stats | Saved stats, window position, hide in combat, score previews |
| M4–M5 | Guild play (built together) | **Built (v0.5.0)**: Comm.lua (addon whispers + send queue), Guild.lua (roster/online, invites, answers, state sync, batched turn catch-up, relay via any online player, live rolls, leave), InviteDialog.lua, per-character game storage (YatzyCharDB). Verified by `tests/sim_guild.lua`. **v0.6.0 (guild channel, first-name matching, "who has Yatzy" invite list) verified in game with a guildmate 2026-11-07.** |
| M4 | Invites + My games list | Invite guildmates, they accept/decline, the game appears in everyone's list |
| M5 | Turn-based guild games | 2–4 players finish a game across logouts; turns sync on login; live view when online together |
| M6 | Release | Compliance checklist re-checked, README, CurseForge/Wago upload |

## 11. Big redesign before the CurseForge release (v1.0, noted 2026-11-09, not started)

The designer wants this in place before the first public release. A guildie asked for backgammon, so the addon becomes a **small game hub**: Yatzy is one game, backgammon is the second, and more games may come later.

### Recommended order of work
1. ✅ **Browser preview first** (built 2026-11-09: `preview/`, see preview/README.md). Build it together with the hub restructure, not afterwards. The new lobby flows (decline, timers, cancelled games) and a whole new game board will need many design rounds. Testing them in a browser with fake guildies is much faster than starting WoW every time. Final checks are still done in game.
2. **Hub and lobby restructure** using Yatzy only. *First sketch built 2026-11-09 (Yatzy/StartScreen.lua, not released):*
   - game cards (Yatzy, Backgammon "coming soon") with a vs Guild / vs Computer panel
   - game icons (IconYatzy, IconBackgammon)
   - the games list grouped Invitations / Your turn / Waiting for others / Finished, with an icon, a "Yatzy vs ..." title and a spelled-out status
   - Accept + Decline on invitations
   - the list scrolls with the mouse wheel

   The designer approved the start screen, the in-game "Your Games" menu (same groups and icons, "New game" opens the game choice) and the popped-out sheet always on top (2026-11-09).
   - ✅ **Feedback to everyone (2026-11-09, not released yet):** every player in a game gets a chat line when someone else accepts, declines, withdraws or leaves. They are also told when the game starts (with whom), when it is cancelled ("not enough players accepted"), and who they are still waiting for. Example: "[Yatzy vs Father Ghouliath] Gulki Warr declined. The game has started: You, Father Ghouliath." The game list also says "... declined". Tested in sim_guild step 17.
   - ✅ **Start now and expiring invitations (2026-11-09, not released yet):**
     - **Start now:** the creator gets a "Start now" button on a waiting game once at least one player has accepted. A confirm says who plays and who is left out.
     - **Expiry:** unanswered invitations run out by themselves after 7 days (checked by the creator's client at login and every 30 s).
     - **Rule:** only the creator writes "X" (didn't answer in time) into the answers, and an X always wins. Everyone then starts the game with the same list. If someone accepted at the same moment and their copy had already started with them in it, the copy starts again with the creator's list, as long as nobody has played yet.
     - **The left-out player** gets "<creator> started the game without you", and the invitation disappears.
     - Tested in sim_guild step 18, the race included.
   - **Still to do:** the 5-minute invite timer in Fast mode (together with Fast mode). This covers the new start screen, the new game list, invitations with accept/decline, feedback to the other players, and separate windows. Release it to the guild as a 0.10 test.
3. **Backgammon** as the second game in the hub.
4. **CurseForge release** (v1.0), after the donation/ToS check below.

### Start screen (hub)
- **Wide buttons, one per game:** "Yatzy" and "Backgammon" in v1, each with its own picture. When you click one, a small panel opens to the right of it with **"vs guildies"** and **"vs computer"**.
- The stats card stays, per game.

### Ongoing games list
- Every row gets a **clear game icon and title**: one of our dice for Yatzy, a checker piece for backgammon. The title reads "Yatzy vs Gulki" or "Backgammon vs Gulki".
- The designer finds today's list confusing. Redesign it in the preview. Group it into: **Invitations** (waiting for you), **Your turn**, **Waiting for others**, **Finished**. Each status is spelled out ("Waiting for Gulki to accept", "Gulki declined").

### Invitations: accept / decline, feedback to everyone
- An invited player can **Accept** or **Decline**.
- When everyone has answered, the game **starts with the players who accepted**, as long as at least 2 remain including the creator. If too few remain, the game is cancelled.
- **Everyone in the game is told what happens:**
  - "Gulki declined"
  - "Gulki left the game": their remaining turns are skipped, and they're shown as having left
  - "The game was cancelled: too few players"
  - "Herm removed the game"
- Today a player who removes a game, or never answers, leaves the others guessing.
- **Invite timer:** in Fast mode, 5 minutes to accept. Proposal for normal games: invites expire after 7 days, and the creator can start early with those who have accepted ("Start now with 3 players").

### Separate windows, one per game type
- **Default (no setting needed):** Yatzy and backgammon each open in their own window, so you can have one of each open at the same time. The hub/start screen is shared; opening a game from the list opens it in that game's window.
- Each window's **X closes only that window**. Escape closes the topmost one, the way WoW's own windows work.
- Size, position and fading are remembered per window. Fading and hide-in-combat apply to all of them.

### Backgammon (first notes)
- 2 players. Also playable vs the computer, with a simple AI.
- Standard rules: bear off, hit and enter from the bar.
- **No doubling cube.** Decided 2026-11-09: only the basic game.
- Same art style as Yatzy (wood, gold, our own dice). Turn-based over guild messages, like Yatzy.
- Fast mode and Poke work the same way as in Yatzy.

**Designer's decisions (2026-11-09):**
- **Moving a checker:** both ways work. Click a checker and the points it can reach light up, then click one. Or drag the checker there.
- **Ending a turn:** moves can be undone during the turn. The turn is sent only when you press **Done**.
- **No gammon/backgammon:** a game is just won or lost, with no bigger wins.
- **The board's look** is designed directly in the browser preview, in our style, and refined there.

**Technical decisions:**
- **Opening roll:** each player rolls one die (again on a tie). The higher die starts and plays both dice. In guild games the opening roll comes from the game id, so every copy gets the same.
- **Moving with several dice at once:** clicking a point that needs both dice (e.g. 13 → 5 with 5-3) plays both steps. Undo takes them back one at a time.
- **Network:** a turn is sent as the two dice plus the moves, two letters per move (e.g. "31" + "ifgf"). Every copy checks each move against the rules. Backgammon games get **their own message codes**, so older Yatzy versions ignore them instead of treating them as Yatzy games.

**Progress:**
- ✅ **Rules engine** (`Yatzy/BGRules.lua`, 2026-11-09): board, legal moves (enter from the bar first, use as many dice as possible, the higher die when only one can be used, bearing off), undo, finish, checking someone else's turn, resign. `tests/test_bgrules.lua`: 79 tests, including 200 random games that always end with 15 + 15 checkers.
- ✅ **Computer opponent** (`Yatzy/BGAI.lua`, 2026-11-09): tries every different way to play the dice and scores the end position by rules of thumb (pip count, hitting, made points, home board, primes, the risk of leaving lone checkers). It plays the standard opening moves (3-1 → 8/5 6/5, 6-1 → 13/7 8/7), beat a random player 60 of 60, and its slowest turn took under 10 ms. `tests/test_bgai.lua`.
- ✅ **Board vs the computer** (2026-11-09, preview-tested, not seen in game yet):
  - **Own window** (`Yatzy/BGBoard.lua`): movable and resizable, with the size saved in `YatzyDB.bgWindow`. The board scales to fit the window. There's a Home button (main menu) and an X, and Escape, fading and hide-in-combat work like the Yatzy window. Both windows come to the front when clicked (`SetToplevel`).
  - **Look:** a wooden case with a bronze edge, dark leather fields, and points in red and pale lacquered leather. The checkers are lacquered wood (red = you, ivory = opponent) with a gold rim. The bar is darker wood, and the borne-off tray is red leather in a metal rim. Our own wooden dice lie on the half of the player whose turn it is. New art: `CheckerRed/CheckerIvory/PointRed/PointIvory.tga` (tools/render/assets.html; `render-assets.ps1 -Only ...` renders just those).
  - **You always play from the bottom** (home board bottom right).
  - **Playing:** Roll lies on your half of the board. Click a checker and it lifts and glows; the points it can reach light up, with a gold "ghost" checker on the landing spot. Or drag it there. Checkers fly to their place. Used dice are dimmed. Undo + Done sit under the board, and Done glows when it's all that's left. The status line and the pip counts sit under the board.
  - **The computer** rolls, then moves one checker at a time. If the window is closed, it finishes the turn at once. Its last roll stays dimmed on its side until you roll.
  - **Game over:** a panel with "You won!" plus New game and Main menu. Stats are saved in `YatzyDB.stats.backgammon.solo/guild` (not shown on the stats card yet).
  - **Hub:** the Backgammon card is ready. "vs Guild" is greyed out ("coming soon"). The games list shows "Backgammon vs Computer · Turn 3 · Your turn".
  - **Tests:** `tests/smoke_ui.lua` plays a whole backgammon game through the window and turn code, including undo, Done and closing the window during the computer's turn.
  - Preview fix: `Raise()` in `preview/wow.lua` now works like WoW's (on top of the whole strata).
- **To check in game:** restart WoW fully (new .tga files and new .lua files). Check that the points, checkers and glows look right, and that dragging works with WoW's cursor. Check that clicking the Yatzy window brings it in front of the backgammon window, and the other way round.
- ✅ **Loose ends (2026-11-09, preview-tested, not seen in game yet):**
  - **Stats card:** two columns, Yatzy and Backgammon (guild games), with the column names on their own line under "Your Stats". Backgammon fills Games, Won and Win rate. Average, Best and Yatzys stay empty for it. A finished backgammon guild game also counts in "Against guild members" (won – lost, both games together).
  - **Hit checker:** it stays on its point while the hitting checker flies, then lifts off and flies to the bar (0.32 s). Closing the window or switching games mid-flight finishes it at once.
  - **Ctrl + mouse wheel** over the backgammon title bar changes that window's size. The size is its own, saved in `YatzyDB.bgWindow.scale`. The "Window size" row in Settings changes the window whose Settings button you pressed. `/yatzy reset` also resets the backgammon window.
- ✅ **Tester feedback round (0.10.2, 2026-11-11; tests and preview, not seen in game yet):**
  - **Buttons in the middle of the board (final layout in 0.10.3, see the next entry):** Done and Undo sit on the board itself, next to the dice, so everything you click in a game is in one place. Undo uses `Undo.tga` and Done `Check.tga`, both made in `tools/render/assets.html`.
  - **Bearing off with one click:** `Board:OnMouseDown`: if the tray is the only place a clicked checker can go, it moves at once. If it has other options too (e.g. a smaller die inside the board), it is selected as before and you click a lit point or the tray.
  - **Auto finish:** `BG.Contact(board)` says if the sides can still meet; once they can't, a tick box "Auto finish" shows under the Roll button (under Done during a turn). `g.auto[seat]` holds each player's choice. Computer game: my tick is enough. Guild game: both must tick; the choice is sent as `BA` (game id, 1/0), again after each of my turns, and cleared when the game ends. When it's on, `Play:RunTurn(g, true)` plays MY turns for me with the computer's choice of moves (live moves and finished turn are sent like manual play), and the other player's client does the same for theirs. Everything runs 2x as fast (`Board:OnUpdate` scales time, the pauses in BGPlay use `Play:Speed`). If the window is closed, a turn is played at once. Versions before 0.10.2 ignore `BA`, so a friend on an old version can never tick: the game simply stays manual.
- ✅ **0.10.3 (2026-11-11; tests and preview, not seen in game yet).** More tester feedback, plus the stats drop-downs:
  - **Dice layout:** the dice lie centered in the middle of my half. **Undo** (30x30 icon) is left of them and **Done** (48x48 square, big check icon) is right of them, at the same height. The Auto finish tick box is below. (This replaces the earlier "Done under the Roll button" idea.)
  - **Move with the lit die:** the primary die is much bigger (66) and lit; the other die is small (38) and plain, with no glow. `Board:DiePlan` gives the sizes, and the roll animation uses them too.
  - **I throw the opening roll myself:** turn 1's dice are still decided by the game id (so both copies agree), but they stay hidden (`Board:NeedsOpening`) until I press Roll (`g.openRolled`). `Play:Roll` then animates the existing dice once.
  - **The turn line is above the board** (picture, status text, Poke), like in Yatzy; the board starts 46 units lower.
  - **Quick clicks:** a second checker can be clicked while the first is still flying (`Play:CanAct(g, moving)`; `AnimatePath` lands the earlier flight at once, and the game state is already updated when a flight starts).
  - **Stats on the main menu:** one drop-down per game (Yatzy, Backgammon). Only one is open at a time (`db.statsOpen`, default Yatzy). A closed one shows a one-line summary ("12 games · 58%"). Same small +/- buttons as the Window size setting. Backgammon shows games, won, win rate and "Against the computer: X of Y". Rivals only show when the card has room.
  - **Tests:** test_bgrules 84 (new: `BG.Contact`), smoke_ui (opening roll, one-click bear off, quick double move, Auto finish, stats sections), sim_guild 156. `dist\Yatzy-0.10.3.zip` is built.
  - **Not verified in WoW:** the fit of the texts, the new icons, the big die with doubles.
  - **Still open from this round:** the "computer played this" mark on the score sheet, and the portrait in more places.
- ✅ **Guild play** (2026-11-09, preview- and simulation-tested, not seen in game yet):
  - **Inviting:** Backgammon → vs Guild opens "Invite to Backgammon". You pick exactly one guild member: ticking another replaces the choice. The Fast game box works here too. The invitee is told "X invited you to a game of Backgammon!". Accept/Decline, Start now, the 7-day expiry and the messages to the other player all work as in Yatzy.
  - **Start:** the opening roll comes from the game id, so both copies have the same one, and nobody has to send it.
  - **Messages:**
    - `BS` (state), `BT` (turns: dice + moves, e.g. `62nhmk`) and `BM` (live: dice + moves so far).
    - `Comm.lua` now reads message kinds of more than one letter. Versions before 0.10 only read one letter, so they skip backgammon messages and can never mistake one for a Yatzy game.
  - **Checking:** every turn that arrives is checked move by move. Moves shown live are taken back first, because the turn that arrives is the real one.
  - **Live:** while you're both online, you see the other player's roll, each move as it flies, and their undos too. The status line says "Gulki rolled 6-2 and is moving...".
  - **Notices:** "Your turn! vs …" popup, sound, chat line and the "Your turn!" box at the top work for backgammon. The box doesn't show while the backgammon window shows that game. Clicking the box opens the backgammon window.
  - **Giving up:** the bin icon in the list says "Give up the game" ("Give up this game? Gulki wins."). The other player wins and is told "X gave up: you win!".
  - **Fast games:** the time left shows under the board ("Fast · 7:42 left for your turn") with a Poke button on the other player's turn. Input is locked when your time is up. A late turn is played by the computer with dice from the shared number generator: it starts the turn over (moves taken back, new dice, except turn 1 = the opening roll), so every copy gets the same turn.
  - **Tests:** `tests/sim_guild.lua` step 22 covers all of the above, playing a whole game to the end on two copies. Versions before 0.10 skipping BS is checked too.
  - **Preview bots** play backgammon turns too: they open the game, roll, move one checker at a time (the computer's choice) and press Done.
- ✅ **Designer's small fixes** (2026-11-09, preview-tested, not seen in game yet):
  - **Bigger dice and Roll button:** the dice are 44 units in the row (they were 28) and 40 for doubles, and the Roll button is the big 170×44 one ("Roll dice").
  - **Roll animation like Yatzy:** two dice are thrown onto the player's half, each with its own start, speed, spin and 1–3 bounces, and land on free spots. They lie still for 0.35 s, then glide into a row in the middle of the half, growing and lighting up.
  - **Doubles:** only two dice are thrown. After they settle, two bonus dice slide out from under them into a 2×2 pattern.
  - **Selecting a checker:** the checker grows quickly and the lights fade in (0.1 s). New highlights always fade in.
  - **Undo** takes back all moves of the turn in one click.
  - **Shorter status texts**, e.g. "No possible move." and "Press Done, or Undo."
  - **Setting "Backgammon: move with the lit die"** (off by default, in Settings, which the backgammon window now has too):
    - The highest usable die is primary: bigger and brighter.
    - The board lights the checkers that can move with it, plus where they land.
    - A click on a lit checker moves it at once. Clicking the other die makes that one primary. Dragging still works.
  - **Opponent's picture** (new `Portrait.lua`, gold ring art `PortraitRing/PortraitBack.tga`), left of the status line:
    - the real face when WoW knows the player (you, party, raid)
    - otherwise their class icon (class from the guild roster)
    - for the computer, our die
    - ✅ **Yatzy too** (2026-11-09): the status box over the dice table ("Your turn" / "Gulki's turn") shows the picture of the player whose turn it is on its left, with the same rules (face / class icon / our die for the computer). It's hidden at game over. Made bigger the same day (64 units): it sticks out of the box at the left, a little at the top and below.
  - **"Clear list" button** on the start screen, top right above the games list, with a question first. It removes computer and finished games, declines invitations, and leaves running guild games (the others are told).
  - **Tests:** smoke_ui checks the doubles phases (throw, rest, line, bonus), Undo of all moves, dice-first play (primary die, switching by clicking a die, the one-click move) and Clear list.
  - ✅ **Follow-up fixes (2026-11-09):**
    - **Clear list's question** lay behind the list rows. Our windows are DIALOG strata and come to the front when clicked, so `UI:Confirm` now lifts WoW's popup to FULLSCREEN_DIALOG. This applies to every yes/no question of the addon.
    - **Full list explained in the addon, not only in chat:** with 10 games going, the vs Guild / vs Computer panel shows "You already have 10 games going (the most you can have). Finish one, or remove one from the list, to start a new game." instead of the buttons. Backgammon's game-over panel shows the same text if New game is pressed with a full list (`Games:FullText()`).
- **To check in game, with a guildmate:** invite, accept, a few turns online together (watch the live moves), one turn while the other is offline, giving up, a fast game with a timeout. Also check that a guildmate on 0.9.x sees nothing of it.

### ✅ "Replay" button on the game-over panels (built 2026-11-15 as v0.12.0; tests and code only, not seen in game yet)
- **As decided by the designer:** it invites everyone who accepted and played the game to the end (`Games:ReplayNames`; in backgammon the opponent always counts); a full list loses its oldest game (`Games:DropOldest`, after a question in `UI:ReplayGame`: a guild game is left, an invitation declined, a computer game deleted); the first player to press it starts the replay and everyone else's button becomes "Go to replay"; the turn order is random again.
- **How:** `Games:Replay(g)` (computer: a new game at once; guild: `Guild:CreateGame` with `opts.replayOf`). The finished game remembers `g.replayed`, the new one `g.replayOf`. State messages carry the old game's id in a 9th field (the 8th stays empty, it belongs to the mailman marker), so the other players' copies learn which game was replayed.
- **Two pressing at the same moment:** the replay with the earlier id (ids start with the time) wins. A copy that gets a later one ignores it; a creator whose own replay turns out to be later withdraws it (`Guild:Leave`).
- Buttons: Yatzy panel Replay / Back to games / Close (the panel is 340 wide now); backgammon panel Replay (was "New game") / Main menu. After pressing: a computer game opens, a guild replay goes back to the games list (waiting for answers).
- Tests: `sim_guild.lua` step 24, `smoke_ui.lua` (both panels, "Go to replay").
- Original notes (2026-11-15):
- The game-over panel (Yatzy and backgammon; today "Back to games" and "Close") gets a third button, **Replay**.
- It starts a new round with the same players: it sends an invitation to every player of the finished game, and each of them accepts or declines, exactly like a normal invitation (Accept/Decline, "Start now", 7-day expiry, the messages to the others).
- Same game type, same fast/normal setting. Against the computer: no invitation needed, it just starts a new game.
- To decide when building: who counts as "all players" (everyone invited, or only those who didn't leave?); what to do when the list is already full (10 games, use `Games:FullText()`); a Replay pressed by two players at once should not make two games (e.g. only the creator, or the first invitation wins); the new game's seat order stays random.
- Built on what exists: `Guild:CreateGame(names, opts)` with `opts.fast` / `opts.game`, so the button mostly collects the names and calls it.

### Later, maybe: chess (noted 2026-11-09)
- A third game in the hub, for a future version.
- Turn-based over guild messages, like the others. The notes for each move are short, e.g. "e2e4".
- Needs: move rules (castling, en passant, promotion, check/mate/stalemate), a board in our style, and a simple computer opponent.

### ✅ Renamed to **YatzyFiend** (chosen 2026-11-25, in 0.12.1)
- The designer wanted a name with "Yatzy" in it, written as one word (easier to search).
- **What changed:** the name players see: `## Title:` in the .toc, `Yatzy.DISPLAY_NAME` in Core.lua (title bar plaque, its tooltip, start screen logo (no subtitle, the designer's choice), minimap tooltip), the custom sounds README.
- **What deliberately stays "Yatzy":** the folder, `YatzyDB`/`YatzyCharDB`, the message prefix `YATZY2` and `/yatzy`. So no saved games need to move, and old and new versions still play together. (The folder name is only seen in the AddOns folder.)
- CurseForge title: "YatzyFiend – Yatzy & Backgammon with your guild".

### (History) rename the addon (decided 2026-11-09: it will be renamed)
- The addon is called "Big M's Lucker Yatzy" and its folder is "Yatzy". It gets a new hub name because it will hold several games.
- Do it **before** the CurseForge release.
- **Candidate (2026-11-09): "BoredGames".**
  - **For:** a nice pun on board games; short, memorable, fits a hub with several games.
  - **Against:**
    - Nobody searches for "bored". Players search "yatzy", "dice", "backgammon", "board game", "minigame".
    - There is already a CurseForge addon with the same pun and a similar idea: "Orev Triad & 'Bored' Games" (curseforge.com/wow/addons/orev-triad-bored-gmes), a tabletop/casino addon with dice, craps, poker, roulette and slots. Our addon could be mixed up with a gambling-style addon, which we deliberately avoid.
  - **Recommendation if we keep it:** put the searchable words in the project title and summary, e.g. "BoredGames – Yatzy & Backgammon with your guild". The summary/tags should name every game, plus "dice", "guild", "minigame", "turn-based", "Classic". Pick the CurseForge category "Minigames".
  - Also check the name is free on Wago and as a folder name, then decide.
- **Name research (2026-11-09, CurseForge search, WoW addons):**
  - **"Yatzy" and "Backgammon": no addon at all.** Whoever searches those words finds only us, so both words belong in the title.
  - "Yahtzee": Kniggel (2018, old) and **Forever Dice & Ale** (Nov 7, 2026: five-dice game like Yahtzee/Kniffel, solo or party/raid, for Forever). That's our closest competitor; it plays live in a group, not turn-based with the guild while offline.
  - "Bored games": Orev's "'Bored' Games" (tabletop/casino). **Advice: drop "BoredGames"**, it would be mixed up with a casino addon.
  - Crowded words: "tavern" (Forever Tavern, Tavernly, TheHearth with gold wagers, Rack & Ruin), "guild games" (30 results: Guild Together Forever, Moose Guild Forever, Psycraft Guild Games…), "dice" (853), "game night", "tabletop".
  - "Parlor" ("play turn-based games with friends") exists, so avoid that name too.
  - **"Lucker": no addon** uses it. Our logo already says "Big M's Lucker".
  - **What sets us apart:** turn-based guild play that works while people are offline (like Wordfeud). The competitors play live in a party/raid. Say it in the summary.
  - **Proposals** (the designer decides):
    1. Keep the brand: folder `LuckerGames`, CurseForge title "Big M's Lucker – Yatzy & Backgammon with your guild". Unique, already on the logo, and both game words in the title. *(recommended)*
    2. Keep "Yatzy" as the folder (no data move at all) and only change the CurseForge title to "Yatzy & Backgammon – guild games for WoW Forever". The cheapest option, but the name says less once more games arrive.
    3. A new neutral name, e.g. "TurnTable" or "Guildfeud" (not searched yet).
  - Wago's search didn't work for automated checks: look the final name up there by hand.
- The new name affects:
  - the folder and .toc name
  - the title, the minimap tooltip and `/yatzy` (keep `/yatzy` as an extra command). The tooltip name is `Yatzy.DISPLAY_NAME` in Core.lua (since 0.12.1); the title plaques in UI.lua and the start screen logo still say "Big M's Lucker Yatzy" on their own.
  - the saved data names
  - the addon message prefix
- Players' saved games and settings must be moved over from `YatzyDB`/`YatzyCharDB` on first login. Old and new versions must still understand each other during the switch, or at least say "Gulki needs to update".

### Release tooling (built 2026-11-09)
- `tools\release.ps1` builds `dist\<Addon>-<version>.zip` (one addon folder, forward-slash paths; checks that every .toc file exists). With `-Upload` it publishes on CurseForge through the upload API: the project id comes from `## X-Curse-Project-ID:` in the .toc, the game version from `## Interface:` (16001 → "1.60.1", the WoW: Forever flavor on CurseForge), the "What's new" text from the matching section of `CHANGELOG.md`. The API token lives outside the project (`%APPDATA%\AddonRelease\curseforge-token.txt` or `CF_API_KEY`). `-DryRun` does everything except the upload.
- `RELEASING.md` is the step-by-step guide (one-time CurseForge setup by the designer, then every update).
- `CHANGELOG.md` has a draft 0.10.0 section.
- Not tested against CurseForge yet (no project or token yet). The zip build is tested.
- No version history yet: Git isn't installed, and there's no GitHub. Optional, see RELEASING.md.

### Donations / tips: what the rules say (checked 2026-11-09)
- **Blizzard, UI Add-On Development Policy** (official, pinned on the WoW forums; applies to WoW: Forever too):
  - add-ons must be free, with no paid "premium" features
  - the code must be visible
  - no advertising
  - **rule 5: add-ons may not ask for donations in the game.** Donation requests belong only on the add-on's website or distribution site.
  - **So:** no donation text, link or button anywhere inside the addon (also not in "About" or a tooltip). This matches our compliance table.
- **CurseForge moderation policy:**
  - Personal donation links (Ko-fi, Patreon…) **are allowed** on the project page, but **at the bottom, after the description**, at a reasonable size.
  - Donor-only features may not be advertised (Blizzard forbids them anyway).
  - CurseForge also has a donation button setting in the project's settings, and a rewards program: points per download, paid out at 100+ points via Payoneer/Tremendous. Check the current terms when signing up.
- **Verdict:** a Ko-fi/PayPal link at the bottom of the CurseForge page (and in a GitHub README, if there is one) is fine. The addon itself stays clean.

### Reminder: donations / tips (original note)
- Check whether a PayPal, Ko-fi or similar link may be shown for tips, while the addon stays completely free.
- Read Blizzard's current **UI Add-On Development Policy** and ToS (WoW: Forever rules if they differ), plus CurseForge's own rules for project pages.
- Things to settle:
  - Is a link on the **CurseForge page / README** allowed? This is likely fine, but check.
  - Is a mention **inside the game** (e.g. in the addon's "About") allowed? Our compliance table currently says no in-game donation requests, and we keep it that way unless the policy clearly allows it.
  - CurseForge's own reward program as an alternative.

## Ideas and small fixes noted by the designer

- ✅ (v0.5.2) Show the addon version in the window: bottom-right of the start screen.
- ✅ (v0.5.2) Bin icon on each row of the games list: declines invitations, withdraws from / leaves guild games, deletes games vs the computer, removes finished or cancelled games.
- ✅ (v0.8.6) Yatzys in guild games are announced in guild chat by the roller ("Gulki rolled a YATZYYYYY"); a setting turns it off.

### To test in game before the next release (everything built since 0.9.4, preview-tested only)

The designer can't start the game right now, so these were built and tested in the browser preview and the automated tests only. Check them in game, with a guildmate, before the zip goes out (next version: 0.10.0). **StartScreen.lua is a new file: restart the game fully once.**

1. **Start screen:**
   - game cards (Yatzy, Backgammon "coming soon"), with the vs Guild / vs Computer panel; clicking elsewhere closes it
   - grouped list (Invitations / Your turn / Waiting for others / Finished) with icons and status text
   - wheel scrolling only when the list is too long
   - Accept / Decline on invitations
2. **"Your Games" menu in a game:** groups and icons; "New game" opens the game choice.
3. **Popped-out score sheet on top of the main window;** the strike-out question still on top of it.
4. **Messages to everyone:** accepted, declined, withdrew, left, started, cancelled, still waiting for.
5. **Start now + 7-day expiry:**
   - the button shows for the creator once someone has accepted
   - the left-out player is told and their invitation disappears
   - all copies agree on the players (also if someone accepts at the same moment)
6. **Random turn order:**
   - guild games: the same order for everyone
   - vs the computer: a coin toss, and the computer plays its first turn by itself
   - old waiting invitations keep the invitation order
7. **Totals hidden while a game runs** (a dash in the Total row and the pinned strip); shown at game over.
8. **Winner frame on the game-over panel:** gold frame, soft light, sparks running round it. The panel now has room for 6 players (it used to show only 4).
   - Also fixed: the soft light used only a corner of its image, which made the "smudge on the right".
9. **Window size in Settings:** - 90% + and Reset, in step with Ctrl + mouse wheel. No chat line when you use the Settings row.
10. **Docked sheet faded twice:** `paper:SetIgnoreParentAlpha(true)`. Check that the faded sheet now looks as faded as the rest of the window, docked and popped out.
11. **Thin lines on small screens:**
    - score sheet lines, metal-border hairlines and list/header lines are now whole screen pixels and are resized when the scale changes
    - check at a small UI scale and low resolution that all sheet lines show
    - the "made by" line hides in a small window
12. **Fast mode** (new file Fast.lua):
    - the "Fast game: 10 minutes per turn" box in the invite dialog
    - "Fast · m:ss left" on the status line (red in the last minute) and in the games list
    - the Poke button: the poked player gets a popup, a sound and a chat line, once per turn
    - when time runs out the computer plays the turn: your own client if you're online, otherwise the next online player 15 s later
    - fast invitations run out after 5 minutes
    - after 3 missed turns in a row a player gets 30 s per turn
    - Ctrl + wheel at the max/min size no longer repeats "Window size 120%" in chat
13. **Your turn is hard to miss** (players missed their turns, 2026-11-09):
    - **"Your turn!" box at the top of the screen** (new file TurnBanner.lua). It shows while it's your turn in a guild game that isn't on screen (window closed, or another game open; not on the start screen, whose list already shows it). Click it to open the game. It has the game icon, "vs …", "+N more" and, for fast games, the time left top-right (same colour as "Round 1/15"). It can be dragged (position saved). The x hides it until the next turn. It's hidden in combat (with the hide-in-combat setting) and when on-screen notices are off.
    - **The fast timer on the game screen** is now small text in the top-right corner, in the same colour as "Round 1/15" of the "Your turn" box ("Fast 9:41"), not red in the sub-line.
    - **The Roll button** flashes for 3 s as before, then keeps a calm glow until you roll.

### ✅ Fast mode: built 2026-11-09 as designed below (Fast.lua; sim_guild step 20; tried in the preview with a 40 s limit). Not built yet: the small "computer played this" mark on the score sheet.

- **New file `Fast.lua`** (after Guild.lua in the .toc). `Yatzy.Fast` with:
  - **Limits:** TURN_LIMIT 600 s, INVITE_LIMIT 300 s, GRACE 15 s, SLEEP_AFTER 3, SLEEP_LIMIT 30 s.
  - **Turn clock (runtime only, never saved):** `Fast.clock[id] = { turn, started = GetServerTime() }`. `Fast:Note(g)` is called at the end of `Guild:Advance` and from a 1 s ticker. After a /reload or login the clock restarts, so a stale save can never trigger a timeout.
  - **Timed-out turns:** when the turn changes, if the elapsed time was ≥ the limit, that seat's `g.missed[seat]` goes up by 1 and a chat line says "Time's up for X: the computer played their turn". Otherwise `g.missed[seat]` is reset to 0. After 3 misses in a row, that seat's limit becomes 30 s.
  - **Who plays the computer turn:**
    - the current player's own client, right at the deadline (input is locked: Play:Roll/ToggleHold/Score check `Fast:TimeUp(g)`);
    - otherwise the first ONLINE player after the current seat (skipping players who left), at deadline + 15 s.
  - **The computer turn is deterministic:** `AI.PlayTurnInstantly(g, rng)`, starting from rollsUsed = 0 with nothing held. The rng is an LCG seeded from the id digits + turn × 7919. Every client gets identical dice, so duplicate sends are harmless. It is sent with `Guild:OnLocalTurn(g)`.
  - **Poke:** message `K:to:id:turn`, allowed once per turn per game (`g.pokedTurn`). The receiver, if it's their turn: popup + chime + chat line "X pokes you". Fast:Init registers it and is called from Guild:Init.
  - **Invitations:** the creator's client calls `Guild:StartNow` on fast invites older than 300 s (in CloseExpired).
- **Protocol:** the state message gets a 7th field, "F" = fast. OnState sets `g.fast` (sticky). `Guild:CreateGame(names, opts)` takes `opts.fast`.
- **UI:**
  - **InviteDialog:** a check box "Fast game: 10 minutes per turn".
  - **Board status line:** the sub-line gets "· 7:42 left", updated every second. A small "Poke" button sits on the status bar when it's someone else's turn in a fast game.
  - **Start screen rows:** "Fast · Round 3/15 · Gulki's turn · 7 min left", refreshed every ~10 s.
- **Tests:** sim_guild step 20:
  - a timeout makes the next online player auto-play
  - all copies get the same dice
  - the current player's own client auto-plays and its input is blocked
  - a poke reaches only the current player, once per turn
  - a fast invite runs out after 5 minutes

### To do for the next build (noted 2026-11-07; items 1, 2, 4-7 above are built)

- **The faded score sheet looks faded twice (docked).** Screenshot: while the window is faded, the paper and its rows are much more see-through than the rest of the window. The pinned name and Total strips (which sit outside the scrolling area) look normal. Likely cause: WoW draws the contents of a ScrollFrame and then applies the window's opacity again, so the paper ends up at about 0.45 × 0.45 ≈ 0.2. Probable fix: `paper:SetIgnoreParentAlpha(true)` with alpha 1 (so the paper is drawn solid inside the scroll area and only the scroll frame applies the fade once). Check it in game, docked and detached. If it isn't that, compare by setting the fade to 0.45 and measuring how see-through the paper, the strips and the table each are. Test both docked and detached, since the detached window has the same scroll area.
- **Hide total scores until the game is over** (noted 2026-11-08). The Total row in the score sheet shows "–" (or is blank) for every player while the game runs. When the game ends, the totals appear (the game-over panel already shows them). Proposal: keep the upper-section sum and bonus visible, because players need them to chase the bonus. Only the grand total is hidden. The status line and the game list must not reveal totals or who is leading either. Check the guild list, the login notice and the turn popup.
- **Random turn order and random starting player in every game** (noted 2026-11-08). The seats are shuffled when the game is created, so the starting player is random too. This applies to guild games and games vs the computer. Only the creator's client shuffles, and the order is sent in the invite/state message, so every player sees the same order. Older saved games keep their order.
- **Fast mode, a toggle when creating a guild game** (noted 2026-11-08).
  - **Timer:** each player gets a turn timer of 10 minutes. It is shown in the status line and on the sheet next to the active player.
  - **Poke:** other players can "Poke" the player whose turn it is. The poked player gets the turn popup, the chime and a chat line. Limited to one poke per player per turn (or once a minute) so it can't be spammed.
  - **Timeout:** if the timer runs out, the computer plays that player's turn (the same AI as in solo games) and the game moves on.
  - **Design questions to settle when building:**
    - The player who timed out is often offline, so another online player's client must play the computer turn. Rule: the next player in the order does it. If they're offline, the first online player in the order does it. The others accept the result as an ordinary turn message.
    - Clocks differ between computers, so the start of each turn is stored as server time (`GetServerTime()`), not local time.
    - The game list shows a "Fast" tag, plus a timer for games where it's your turn.
    - The sheet marks a turn played by the computer (e.g. a small robot/cog icon on that cell).
    - Are several timeouts in a row allowed? Proposal: after 3 timeouts in a row, the player is "asleep" and the computer plays all their turns until they come back.
- **Clearer winner highlight on the game-over panel** (noted 2026-11-08, screenshot). The soft glow behind the winner reads as a faint smudge on the right side. Replace it with a **distinct glowing gold border** around the winner's row: a thin bright gold frame with rounded corners, a soft outer glow and a slow pulse. The winner's text stays in the title font. With a tie, every winner gets the border.
  - **Reference (2026-11-09 screenshot):** the WoW action-bar "proc" highlight. It's a bright gold square border with a warm glow and small light dots running around the edge. We draw our own version, with no Blizzard art: our own gold border texture, a soft outer glow, and small sparkle dots that travel along the border (marching-ants style). It lasts as long as the panel is open and stays calm (no flashing).
- **Window size in Settings** (noted 2026-11-09). Several players shrink the window with Ctrl + mouse wheel over the title bar but find it hard to discover. Add a "Window size" row in Settings with **− / +** buttons and the current size in % between them (e.g. "− 80% +"), in steps of 5% within the same 50–120% range as `/yatzy size`, plus a "Reset" option to go back to 100%. It uses the same function as Ctrl + wheel, so all three ways stay in sync. Keep Ctrl + wheel.
- **Character portrait in the turn box** (noted 2026-11-09, screenshot of WoW's player frame). The status box on the game screen ("Gulki's turn") shows a round portrait of the character's face on its left, in a round gold-rimmed frame like WoW's player frame.
  - WoW can only draw a face (`SetPortraitTexture(texture, unit)`) for characters the game "sees" as a unit:
    - yourself (`player`)
    - your party or raid members (`party1`–`party4`, `raidN`)
    - your target, or the character under the mouse
  - A guildie elsewhere in the world has no unit, so their face can't be fetched, and an addon can't send a picture over messages.
  - **Plan:**
    - Show the real face when it's your turn, and when the active player is in your group (look the name up in party/raid).
    - Otherwise show a fallback in the same round frame: the character's **class icon**. The class comes from the guild roster, and the icon is WoW's own (we only use it in game, not copy it). Last resort: one of our dice.
    - The face/icon also shows on the game-over panel and in the game list (small), if it looks good in the preview.
  - Check in game that `SetPortraitTexture` works on WoW: Forever.
- **Graphical bugs on small screens / small window** (noted 2026-11-09):
  - **Text spills outside the main menu** (start screen): labels and buttons don't shrink with the window. Fix: make the texts fit (smaller font steps, shortening with "…") and check the start screen, stats card, game list and settings at the minimum size and at 50% scale.
  - **The horizontal lines in the score sheet disappear.** They are probably 1 px lines that vanish when the window is scaled down (WoW rounds them to 0 pixels). Fix: snap the lines to whole screen pixels, so they're always at least 1 real pixel thick, at every scale.
  - Test at small UI scale and low resolution (e.g. 1366×768) to catch more of the same.

### ✅ Built in v0.9.0 (list noted 2026-11-07)

All items below are in 0.9.0 (plus the soft "light from inside" winner glow). Decisions made while building: full names everywhere except the score sheet columns. The detached sheet follows the main window (show/hide, fade, combat, Escape). The toggle is in Settings plus "Pop out" on the sheet and "Dock" on the detached window. Not seen in game yet.

- **Names:** the Invite Guild Members panel shows **full names** again ("Gulki Warr", "Illoyal Advisor"). Today two different players both show as "Gulki". **First name only on the score sheet inside a game** (column headers and the pinned name strip). Since 0.8.2 first names are also used in the games list, the game-over results, the status line ("Gulki is rolling"), invitation texts and the chat Yatzy line. Ask the designer which of those should go back to full names. **Decided:** the status line over the table shows the full name ("Father Ghouliath is rolling", "Father Ghouliath's turn"). Still to ask: games list, game-over results, invitation texts, the chat Yatzy line.
- **Score sheet width follows the number of players:** in a 5-player game the columns are now about 30 px wide and names get cut to "Bi…", "Fat…". Give every score column a fixed, comfortable width (around 55–60 px, as in 2-player games) and let the sheet grow or shrink with the number of players instead of squeezing the columns. Check that the window still auto-folds the sheet when the table would get too small, and that 6 players still fit at the designer's usual window size (otherwise the sheet overlays the table).
- **Better fading** (setting "Fade while I move"). Fade only while the mouse is **outside** the window, and then whenever:
  - **the character is moving at all**, not only while movement keys are held. That includes autorun, click-to-move, /follow, falling, swimming and being knocked back. Today's check is `IsPlayerMoving()`; switch to the actual speed, `GetUnitSpeed("player") > 0`, so every kind of movement counts.
  - **except on a flight path:** no fading while `UnitOnTaxi("player")` is true.
  - **in combat**, even when standing still (`UnitAffectingCombat("player")`). This only matters when "Hide the window in combat" is off. If it's on, the window is hidden in combat anyway.

  Probably rename the setting to something like "Fade while I move or fight (mouse away)". A detached score sheet should fade the same way.
- **"Your turn" highlight on the Roll button:** when your turn starts in the game that's open on screen, a yellow border around the Roll dice button flashes (pulses) for 3 seconds, then stops. It also shows when you open a game where it's already your turn. It only runs while the window is visible, at most once per turn, and stops early if you click Roll. Build it as a glowing yellow frame drawn just outside the button's rim, pulsing about twice a second.
- **Bug: a die taken back out of the tray can land on top of other dice** (they can't be clicked then). Cause, found in `Board.lua` `placeDie`: the die goes back to the spot it had *before* it was saved, but the other dice have been rolled since and may be lying there now. Fix: when a die leaves the tray, check its old spot against the dice on the table. If it's too close, give it a free spot (`FreeSpot`, which also does the zigzag on small tables), ideally with a short glide from the tray. Add a test: save a die, roll the others many times, put it back, and check the distances.
- **Bug: no sound for "your turn" when the window is closed.** Likely cause, found in `Play.lua` `AlertMyTurn`: it returns at once when "On-screen notices" is off, so the sound is skipped too. The sound should follow only the Sound setting (Low/Normal/High/Off), not the notices setting. Second cause: since 0.8.7 the login summary marks the turn as already told, so a turn that was waiting when you logged in gives no sound. Play the sound once with the login notice too. **Answer: the popup shows, but there's no sound.** So `AlertMyTurn` does run and calls `Sound:Play("turn")`, and the popup itself plays the "chime". Neither cause above explains it. New main suspect, in `Sound.lua` `Sound:Play`: for "turn" (and "yatzy" and "invite") it first tries the player's own file `Media\Sounds\Custom\turn.ogg` and stops if `PlaySoundFile` returns true. If the client returns true for a file that doesn't exist, the built-in sound is never played. (`/yatzy soundtest` skips the custom check, which is why the sounds were heard there.) The chime is probably just too quiet on Low (8 dB under the others). Fix: only try custom files when the player has turned that on (a new setting, "Use my own sounds"), otherwise always play the built-in file. Also test the Yatzy and invite sounds, which use the same path, and consider making the chime a little louder.
- **Confirm before striking out a field:** when you click a field that would give 0 points (a strike-out) while at least one other open field would give points, ask first. A small popup appears just above the clicked cell, not WoW's big dialog in the middle of the screen: "Strike out Fours? You could score elsewhere." with **Strike out** and **Cancel**. Clicking elsewhere or pressing Escape cancels. No question when every open field is 0 anyway, since then striking out is the only choice. Write it into `Sheet:OnCellClick`. Add a test: clicking a 0-field with a scoring option open does not score until confirmed.
- **Strike-out stroke too small:** in narrow columns the pen stroke shrinks to about 22 × 3 px and looks like a faint "– –" (5-player screenshot). Today, in `Sheet:Layout`, its width is 80 % of the column (max 64 px) and its height is 1/8 of the width. Fix: never thinner than about 4 px and never shorter than about 30 px. The wider fixed columns (sheet-width item above) help as well. Re-render `Strike.tga` with a bolder, less broken line (tools/render/assets.html "strike"), so it stays a clear single pen stroke when scaled down. Keep the same ink colour as the numbers.
- **Shorter guild chat line:** the Yatzy message becomes just **"YATZYYY"** (exactly that, three Y's at the end). The sender's name is already shown by guild chat ("[Gulki Pala]: YATZYYY"), so "Gulki rolled a YATZYYYYY" said the name twice. Change it in `Play:AnnounceYatzy`, and update the sim test (step 13) and the README/PLAN text.
- **Detachable score sheet:** a toggle to pop the score sheet out of the main window into its own window, so it can be placed anywhere in the UI. It needs its own movable frame (drag by a small title strip), a saved position and size, and a way to dock it back (the same toggle, and maybe a "Dock" button on the detached sheet). When it's detached, the table uses the full window width and the SCORES fold tab is hidden. Open questions: does the detached sheet follow the main window's show/hide, fade and combat-hide (probably yes), and where does the toggle live: in Settings, a small button on the sheet, or both?

## 10. Risks / open questions

- **Interface number and API differences** in Forever's 1.60 client. Check that `C_ChatInfo` and `C_Timer` exist (they do in current Classic clients).
- **Addon-message throttle values:** measure them in game and tune the send queue.
- **Testing multiplayer needs two accounts or a friend.** M4–M5 depend on a guildmate tester.
- **Cross-realm guild members** (if Forever has connected realms): whispers need the full `Name-Realm`.
