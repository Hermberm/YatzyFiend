# Releasing on CurseForge

How a new version gets from this folder to players. After the one-time setup, every update
is: write what's new, raise the version number, run one command.

## How it works (plain language)

- **CurseForge** hosts the addon. Players install and update it with the CurseForge app.
  Every update is a new **file** (a zip) uploaded to our **project** page.
- **The zip** is the `Yatzy` folder, packed. `tools\release.ps1` builds it into `dist\`.
- **Uploading** can be done by hand on the website, or by the same script. The script
  talks to CurseForge with an **API token**: a long password that only allows uploading
  files. It is stored on this computer only, never in the project folder.
- **Game version:** CurseForge tags each file with the game it's for. Ours is
  **WoW: Forever 1.60.1**. The script works this out from `## Interface: 16001` in the .toc.
- New files are checked by CurseForge before they go public (minutes to an hour).

## One-time setup (the designer does this; nobody else can create the account)

The name is decided: **YatzyFiend** (PLAN.md). Use it for the project name, so the web
address becomes curseforge.com/wow/addons/yatzyfiend. Title on the page:
"YatzyFiend – Yatzy & Backgammon with your guild". The zip still holds the folder `Yatzy`.

1. **Create a CurseForge author account** at curseforge.com (log in, then open the
   "Author Console" / authors.curseforge.com).
2. **Create the project:** game World of Warcraft, category **Minigames**. Name, summary
   and description: see PLAN.md (searchable words: Yatzy, Backgammon, dice, guild,
   minigame, turn-based). License: e.g. "All Rights Reserved" or MIT.
3. **Find the project ID:** the number under "About Project" on the project page.
   Give it to Claude, who adds this line to `Yatzy.toc`:
   `## X-Curse-Project-ID: 123456`
4. **Create an API token:** in the author console, "API Tokens", create one
   (name it e.g. "release script"). Save it in this file (create the folder):
   `%APPDATA%\AddonRelease\curseforge-token.txt`
   (paste `%APPDATA%\AddonRelease` into the Explorer address bar to get there).
   Never paste the token into a chat, the project folder, or a screenshot.

## Every update

1. Test in game (see PLAN.md, "To test in game before the next release").
2. Ask Claude: "release version 0.10.1". Claude will:
   - raise `## Version:` in `Yatzy.toc`
   - add a `## 0.10.1` section at the top of `CHANGELOG.md` (what players see as "What's new")
   - run all tests
   - run a dry run (everything except the upload):
     `powershell -ExecutionPolicy Bypass -File tools\release.ps1 -Upload -DryRun`
3. Upload (Claude asks before doing this, since it publishes):
   `powershell -ExecutionPolicy Bypass -File tools\release.ps1 -Upload`
   Use `-ReleaseType beta` for a test version that only players who opted in get.

Just the zip, without uploading (e.g. to send to a guildmate):
`powershell -ExecutionPolicy Bypass -File tools\release.ps1`

**By hand instead:** build the zip, then on the project page choose "Upload file", pick the
zip from `dist\`, game version Forever 1.60.1, and paste the changelog section.

## What the script checks

- every file listed in the .toc exists (a missing file would break the addon for everyone)
- the version has a section in CHANGELOG.md
- a zip for this version doesn't already exist in `dist\` (so an old version is never replaced)
- the zip has one `Yatzy/` folder with normal forward-slash paths (the old hand-made zips
  used backslashes, which some addon managers and Macs don't handle)

## GitHub (optional, later)

Not needed for CurseForge. What it would add: a backup of the code online and a full
history of every change. Without it, this folder on this computer is the only copy, so
at least keep a copy elsewhere (OneDrive, a USB stick) until then.
To set it up: install Git (git-scm.com), create a GitHub account, then ask Claude to
create the repository and push. CurseForge can also be linked to GitHub so that a new
version is uploaded automatically, but the script above already makes updates one command.
