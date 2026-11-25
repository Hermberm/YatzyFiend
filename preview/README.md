# Browser preview

Runs the addon's real Lua files in a browser, inside a small fake WoW. Use it to look at layouts
and try flows without starting the game. It is **not** part of the addon: never put this folder
in the release zip.

## Start

```
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Yatzy\.claude\serve-preview.ps1
```

Then open http://localhost:8766/preview/ (only reachable from this PC).
In Claude Code the launch config is called `preview`.

## What you can do

- **Play as Herm Berm (you).** The main window opens at start. Mouse, mouse wheel, Escape and
  Ctrl + wheel work like in game. Press Enter (or `/`) to type in chat, e.g. `/yatzy`, `/reload`.
- **Fake guild:**
  - Gulki, Father and Biggie have the addon.
  - Tankie doesn't have the addon.
  - Biggie starts offline.
  - Switch players online/offline, choose how they answer invites (yes / no / never), and whether
    they play their turns by themselves.
  - "Se som" shows the addon exactly as that player sees it (you can also play for them).
- **Your character:** running, in combat (with WoW's "secret" values), on a flight path.
- **Screen:** resolution and UI scale, to check small screens and pixel-thin lines.
- **Saving:** saved games and settings are kept in the browser (localStorage) per player.
  "Nollställ allt" wipes them.
- **Errors:** Lua errors show in the side panel, like WoW's error popup.
- **Zoom:** add `#native` to the address to see the game screen at 1:1 pixels.

## How it works

| File | What it does |
|---|---|
| `wow.lua` | The fake WoW UI: frames, textures, text, anchors, mouse/keyboard, timers, events. |
| `main.lua` | Loads the addon once per fake player and connects them with a fake guild (roster, addon messages, guild chat). It also runs the bots. |
| `host.js` | Draws on a canvas, measures text, decodes the addon's .tga images, plays the .ogg sounds. |
| `vendor/fengari-web.js` | Fengari 0.1.4 (MIT): Lua in the browser. It is patched to behave like WoW's Lua 5.1 with numbers ("3", not "3.0"). |

## Known differences from the game

- **Fonts:** Friz Quadrata and Morpheus are Blizzard's, so stand-ins are used (Georgia / Cinzel). Text widths differ a little.
- **Blizzard textures:** the minimap ring, check boxes and tooltip use simple stand-ins drawn by the preview.
- **Speed:** about 30 frames per second while dice roll (Lua in the browser is slower than in WoW). The timing is still correct.
- **Final checks** of looks and feel are always done in game.
