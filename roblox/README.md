# STROOP — Roblox

A port of the `strop.html` build. Same nine colours, same timings, same
progression, same stage 4 boss with all eleven of its challenges.

## Running it

1. Double-click **`StroopGame.rbxlx`** — it opens in Roblox Studio.
2. Press **Play**.

That's the whole setup. The place file carries only Folders, Scripts and
ModuleScripts; the scripts configure everything else (no characters, no world,
no Roblox HUD) when the game starts, so there is nothing to wire up by hand.

To publish: **File → Publish to Roblox As…**

## What's in it

| | |
|---|---|
| **Solo** | Stages 1–3 (3 / 5 / 9 buttons), 3 lives, the decaying clock, the stage 2 tint and the stage 3 flashing backdrop and coloured buttons. |
| **Stage 4** | The boss. Written intro, health bar, 4 lives, the eleven layouts (grid, orbit, pulse, fall, drift, dvd, alternate, decoy, spotlight, blink, ribbon), reactions, and both endings. |
| **Lobbies** | Create or join by 5-character code, live leaderboard, speed-ranked scoring, points-to-win target, W/L end screen, rematch. |
| **Persistence** | Best score is saved per player with a DataStore. |

Scoring, stage gates and timings are the values from the original — they live in
`src/ReplicatedStorage/Stroop/Config.lua` if you want to tune them.

## Things that changed, and why

Roblox has no equivalent for a few browser features, so these were rebuilt
rather than dropped:

- **Firebase → the Roblox server.** The web build elected one player's browser
  as host and had it poll Firestore. Here the server owns round resolution
  outright, so scoring is authoritative and there's no polling lag. The rules
  are identical.
- **Lobbies are per-server.** A code only reaches players already in your
  Roblox server. To play with friends, have them join your server first (Roblox's
  own "Join" on your profile does this), then share the code.
- **Matter.js → `Boss/Physics2D.lua`.** The FALL challenge needed real rigid
  bodies. This is a small SAT + sequential-impulse solver written for it, so the
  buttons still tumble, bounce and stack.
- **`speechSynthesis` → see below.** Roblox has no text-to-speech.
- **SVG stroke-on text → a per-letter reveal.** Roblox can't animate a glyph's
  outline, so each letter's outline wipes in on the original 54 ms stagger and
  the fill inks in underneath.
- **`mix-blend-mode: difference`** isn't available, so the logo, health bar and
  clock flip between black and white depending on the backdrop behind them.
- **Fonts.** IBM Plex Mono → RobotoMono, Georgia → Merriweather, Syne Mono →
  Code. The boss's font churn draws from Roblox's built-in font list (fewer
  faces than the 400 Google fonts, same effect). Roblox text has no
  letter-spacing, so tracked labels are laid out a character at a time.
- **No clipboard or share URL.** The lobby card shows the code instead of a
  copyable link.
- **The dev-menu code word changed** to `DEVMODE` — type it into the lobby-code
  box on the JOIN screen to reveal the stage 4 previews. The original used a
  word I'd rather not reproduce; it's one string in `init.client.lua` if you
  want it different.

### The wrong-colour voice

Stage 3 and the boss lean on a voice calling out a colour that isn't the ink.
Roblox can't synthesise speech, so out of the box the word appears instead — a
faint caption that drifts up near the edge of the screen and fades.

To get the real thing, record one short clip per colour, upload them
(**Create → Audio** on roblox.com), and paste the ids into `CLIPS` at the top of
`src/StarterPlayer/StarterPlayerScripts/StroopClient/Voice.lua`:

```lua
CLIPS.RED = "rbxassetid://123456789"
```

Anything left `nil` keeps the caption, so you can add them a few at a time.
There are 18 names in total: the nine inks plus the nine the ALTERNATE
challenge uses.

## Editing

Two ways:

**In Studio** — edit the scripts directly, they're all under
`ServerScriptService` and `StarterPlayer.StarterPlayerScripts`.

**With [Rojo](https://rojo.space)** — `default.project.json` maps this tree into
a place. `rojo serve`, then connect from the Rojo plugin.

If you edit under `src/` and want a fresh place file:

```bash
powershell -ExecutionPolicy Bypass -File build/build.ps1
```

And to sanity-check the sources before building (block balance, bracket
balance, non-ASCII):

```bash
powershell -ExecutionPolicy Bypass -File build/check.ps1
```

## Layout

```
src/
  ReplicatedStorage/Stroop/     shared: Config, Util, Rounds, Net
  ServerScriptService/          lobby authority, round scoring, DataStore
  StarterPlayer/StarterPlayerScripts/StroopClient/
    init.client.lua             bootstrap, solo run, lobby glue, wiring
    Theme / Ui / Motion         tokens, widgets, CSS transitions + keyframes
    Root / Cards                the play surface, the six overlay cards
    Play                        stages 1-3: word, options, timer, transitions
    Audio / Voice               the click and thud, the distraction voice
    Boss/
      init.lua                  the stage 4 controller
      Layouts.lua               the eleven challenges
      Physics2D.lua             rigid bodies for FALL
      Writer.lua                the handwriting
      Chaos.lua                 the logo, its churn, and the letters falling
```
