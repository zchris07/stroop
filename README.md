# STROOP

**Guess the ink, not the word.**

STROOP is a reaction game built on the
[Stroop effect](https://en.wikipedia.org/wiki/Stroop_effect). A colour word
like **RED** appears on screen, printed in a *different* ink colour, for
example blue. Your job is to pick the **ink** colour, not the word, before the
clock runs out. Your brain wants to read the word, and the game gets harder as
it goes.

This repo has two versions of the game:

| Folder | What it is |
|---|---|
| [`web/`](web/) | The original browser game: a single, self-contained `index.html` |
| [`roblox/`](roblox/) | The same game rebuilt as a Roblox experience |

## Stages

The game escalates through stages:

| Stage | What changes |
|---|---|
| **1** | 3 colour choices. |
| **2** | 5 choices, on a tinted backdrop. |
| **3** | 9 choices in a grid, a flashing backdrop, and a voice calling out the *wrong* colour to throw you off. |
| **4** | **The boss** (solo only). |

The answer clock gets shorter with every correct answer, so each round gives
you less time than the last.

### Stage 4: the boss

Reach stage 4 in solo and the STROOP logo itself becomes your opponent. It has
a written intro, a health bar and its own reactions. You get 4 lives, and you
wear the boss down by answering through eleven challenge layouts:

**grid, orbit, pulse, fall, drift, dvd, alternate, decoy, spotlight, blink, ribbon**

The buttons can circle the screen, tumble and stack under physics, bounce
around like an old DVD screensaver, hide in the dark or blink in and out. There
are two endings.

> ⚠️ Stage 3 and the boss include flashing colours and audio. Skip them if
> that's not for you.

## Modes

### Solo

You have **3 lives**. A wrong answer or a timeout costs one, and the run ends
when they're gone. Climb the stages, reach the boss, and beat your best score.

### Multiplayer lobbies

- Create a lobby, pick a name, and share the lobby code.
- Everyone sees the **exact same word and colour at the same moment**.
- The **fastest correct answer scores the most**, with points ranked by speed.
- The whole lobby moves to stage 2 when anyone passes ⅓ of the goal, and to
  stage 3 at ⅔.
- The host sets the points to win (the default is 10 × the number of players).
- A live leaderboard runs during the match, followed by a W/L screen and a
  rematch.

## Running it

**Web:** open [`web/index.html`](web/index.html) in a browser. Solo play works
offline. Multiplayer lobbies sync through Firebase Firestore, so they need an
internet connection.

**Roblox:** open `roblox/StroopGame.rbxlx` in Roblox Studio and press Play. See
[`roblox/README.md`](roblox/README.md) for publishing, adding voice clips and
how the Roblox version differs from the web one.
