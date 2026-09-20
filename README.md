# Neon Dodger

A stylized neon arcade shooter demo built with [GlistEngine](https://github.com/GlistEngine/GlistEngine). All visuals are procedural: glowing shapes, particle trails, and screen shake, no sprite art.

Play it in your browser: https://irrl.dev/games/neondodger

## How to play

- Move with the mouse (or WASD / arrow keys). The ship follows your cursor.
- Hold left click to shoot toward the cursor, or hold Space to auto-aim at the nearest enemy.
- On touch screens, the first finger works as a floating joystick and a second finger fires at the nearest enemy.
- Dodge or destroy the enemies:
  - Magenta triangles chase you.
  - Orange squares drift across the screen.
  - Purple hexagons are slow and tanky.
- Health scales with size: small shapes take 2 hits, hexagons take 6.
- Score comes from survival time and kills. One touch and you are wrecked.
- M, or the speaker in the top right corner, mutes the music and the effects.

## Sound

The audio is generated the same way the visuals are. `tools/gen-sounds.py` synthesizes pulse waves and LFSR noise into 8 bit 22 kHz mono WAVs under `assets/sounds`: five effects, some with variants so held fire does not turn into one repeated sample, and a four bar loop of music. The whole soundtrack is around 200 KB and the script is the source of truth for it:

    python3 tools/gen-sounds.py

Output is deterministic, so regenerating without editing the script leaves the working tree clean.

## Building

GlistEngine expects an app to sit inside a workspace next to the engine and its plugins, so the scripts in `tools` build that workspace from nothing, install Emscripten into it and keep it out of the checkout:

    tools/build-web.sh          # provisions on the first run, output in dist/
    tools/verify-web.sh         # drives dist/ in headless Chromium

The checks matter more than usual for audio. `tools/verify-web.sh` wraps the page's audio graph before the wasm loads and fails when no samples reach the output, which is the only way a sound that did not load shows up: nothing logs an error, the game just goes quiet. Screenshots land in `artifacts/`.

`tools/glist-env.sh` holds the variables that move the workspace, pin the engine or pin the Emscripten version. The `pages` workflow runs the same build and publishes `dist/` to GitHub Pages.

## Assets

- Fonts: GNU FreeFont (FreeSans family)
- GlistEngine logo, shown on the boot screen
- Sounds: generated, see above
