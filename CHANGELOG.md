# Changelog

What's new in each version. The newest version goes at the top.
`tools\release.ps1 -Upload` sends the section for the version in the .toc to CurseForge
as the file's "What's new", so write it for players.

## 0.12.1

**New name:** the addon is now called **YatzyFiend**. Your games, stats and settings are all still there, and you can still type `/yatzy`.

**Fixed**

- Guild games could get out of step: one player had taken their turn while the others still waited for them (seen in an instance during combat). The addon now compares games with the other players regularly while you wait, shortly after your own turn, after combat and after loading screens, and resends messages that WoW refused to send. Everyone in a game should update.

**New look**

- The minimap button shows two of our dice, and its tooltip tells you when it's your turn or an invitation is waiting.
- Settings is now a cog button, and the Sound button is a speaker: one, two or three sound waves for Low, Normal and High, crossed out when the sound is off.

## 0.12.0

**Replay**

- New **Replay** button on the game-over panels (Yatzy and Backgammon). Against the computer it starts a new game at once. In a guild game everyone who played to the end gets an invitation to the new round, and can accept or decline. The turn order is drawn again.
- Only the first player to press Replay starts the new round. When the others press it, they go to that game ("Go to replay").
- If your list is full (10 games), Replay asks first and then removes your oldest game to make room.

**Fixed**

- The paper of the score sheet now fades with the rest of the window. It stayed fully solid before, so "Fade while I move or fight" seemed not to work on the score sheet.

## 0.11.2

- Your record against guild members is now its own drop-down at the top of the stats on the main menu, called "Game record" (before, it was a list under Yatzy and Backgammon). Closed, it says how many players you have a record with.

## 0.11.1

- New "Low / Medium / High" button next to "Fade while I move or fight" in Settings. Low is the old fade; Medium and High make the window much more see-through, so you see the game behind it. The window shows the new level for a moment when you click.
- Fixed: "made by ... v0.x" no longer overlaps the "more below - scroll" text at the bottom right of the start screen.

## 0.11.0

**Guild mailmen**

- Turns and invitations now reach you even when you and the other player are never online at the same time. Any guildmate with the addon keeps a small copy of your guild games (about 1 KB each) and hands it to you when you log in.
- New setting "Help deliver guild games" (on by default). Turn it off if you don't want to keep copies for others.
- Everyone who plays guild games should update to 0.11.0 (the invite list shows other versions as not compatible).

## 0.10.3

**Stats**

- Your stats on the main menu now have a drop-down for each game: click Yatzy or Backgammon to open or close its numbers. Backgammon shows games, won, win rate and your record against the computer.

**Backgammon**

- New "Auto finish": when your checkers have passed each other and nothing can be hit any more, a tick box appears under the dice. When both players have ticked it (against the computer: just you), the computer plays the rest of the game, faster.
- Bearing off takes one click: click a checker that can only go to the tray and it goes there by itself.
- The dice now lie in the middle of your half. Undo (a small arrow icon) is left of them and Done (a big check mark button) is right of them.
- "Move with the lit die" is much clearer: the die you move with is big and lit, the other one is plain.
- You throw the dice yourself for the opening roll when you start (before, they were thrown for you).
- The turn line with the picture is now above the board, like in Yatzy.
- You can click the next checker (for example two from the same point) before the first one has landed.

## 0.10.1

- "Roll dice" always fits inside its button, also in a small window.
- The "vs Computer" button is narrower than "vs Guild".

## 0.10.0

**Backgammon** is here: the addon is now a small game hub with two games.

- Play backgammon vs the computer, or vs a guild member, taking turns whenever you're online.
- Click a checker and then where it goes, or drag it. Undo, then Done to send your turn.
- Watch your opponent's moves live while you're both online.
- Fast games (10 minutes per turn) and Poke work in backgammon too.
- Optional setting "Backgammon: move with the lit die", for a mobile-app style of play.
- Its own window: open Yatzy and backgammon at the same time.

**New start screen**

- Game cards for Yatzy and Backgammon, each with vs Guild / vs Computer.
- Your games grouped: Invitations, Your turn, Waiting for others, Finished.
- Accept or decline invitations. Everyone in a game is told who accepted, declined or left.
- "Start now" with the players who have accepted. Unanswered invitations run out after 7 days.
- A "Clear list" button.
- Your stats show Yatzy and Backgammon side by side.

**Yatzy**

- Fast mode: 10 minutes per turn. When time runs out, the computer plays the turn.
- A "Your turn!" box at the top of the screen when it's your turn in a game that isn't open.
- The picture of the player whose turn it is, next to "Your turn".
- Random turn order. Totals are hidden until the game is over.
- A new winner frame on the game-over panel.
- Window size in Settings (as well as Ctrl + mouse wheel over the title bar).
- Sharper lines on small screens.

## 0.9.4

The last version before the game hub.
