<div align="center">

<img src=".github/media/banner.webp" alt="OPEN BREACH — Time is on your side" width="100%" />

### Plan every entry. Stop the clock. Breach together.

A top-down tactical squad game that runs entirely in your browser.<br/>
Free and open source. No install, no account, no backend.

[![Play now](https://img.shields.io/badge/▶_PLAY_NOW-in_your_browser-ff5a48?style=for-the-badge&labelColor=0b100e)](https://devjay4561.github.io/open-breach/)
[![Watch the trailer](https://img.shields.io/badge/WATCH-TRAILER-f2b84b?style=for-the-badge&labelColor=0b100e)](.github/media/trailer.mp4)

![Godot 4.7](https://img.shields.io/badge/Godot-4.7-7fd8c6?style=flat-square&logo=godotengine&logoColor=white&labelColor=0b100e)
![WebGL 2](https://img.shields.io/badge/WebGL_2-WebAssembly-7fd8c6?style=flat-square&labelColor=0b100e)
[![Code: MIT](https://img.shields.io/badge/code-MIT-f2efe4?style=flat-square&labelColor=0b100e)](LICENSE)
[![Assets: CC0](https://img.shields.io/badge/original_assets-CC0-f2efe4?style=flat-square&labelColor=0b100e)](ASSETS-LICENSE.md)

**English** · [한국어](README.ko.md)

<a href=".github/media/trailer.mp4"><img src=".github/media/hero.webp" alt="OPEN BREACH gameplay: planning, pausing and breaching" width="100%" /></a>

<sub>▲ Real gameplay, no mockups. Click for the full 53-second trailer with sound.</sub>

</div>

---

## The loop

<table>
<tr>
<td width="33%" valign="top">
<img src=".github/media/screenshot-02-planning.webp" alt="Planning routes for four operators" />
<h3>01 · Plan</h3>
Draw routes, stack your team on the door, and queue the flashbang. Every order can be reordered, timed, or tied to a go-code.
</td>
<td width="33%" valign="top">
<img src=".github/media/screenshot-05-pause.webp" alt="Paused mid-operation" />
<h3>02 · Pause</h3>
Time only moves when you let it. Freeze mid-fight, read the room, rewrite the plan, then resume.
</td>
<td width="33%" valign="top">
<img src=".github/media/screenshot-04-room-clear.webp" alt="Rooms being cleared" />
<h3>03 · Breach</h3>
Doors swing, flashes pop, and contact resolves from real lines of sight. Clear it room by room.
</td>
</tr>
</table>

## Features

- **24 operations.** 12 missions on the mission board (tutorial, campaign and variants) plus 12 fictional special operations: an airliner, a ship, compounds and more.
- **4-operator squads.** Move, face, door, gear, secure, hold, reload and signal orders, with go-codes A/B/C to sync the team.
- **Doors and flashbangs.** Open, kick or charge doors. One context action opens a door, throws a flash and waits for the blast before the stack goes in.
- **Real visibility.** Walls, doors and furniture shape paths and sight. Fights resolve automatically from what each operator can actually see.
- **Loadouts.** Rifles, sidearms, armor, helmets, optics, suppressors and breaching tools, plus names, callsigns, colors and patches per operator.
- **Deterministic replays.** Every run is a recording you can scrub, follow and share as a small JSON file.
- **Progression.** Seeded layouts, star challenges, a daily operation, unlocks and a nine-operation campaign.
- **Map editor.** Build your own kill house and share it with your plan.
- **Runs anywhere a modern browser does.** A 30 Hz simulation in Godot 4.7, compiled to WebAssembly. Progress stays in IndexedDB on your machine.

## Gallery

<table>
<tr>
<td><img src=".github/media/screenshot-01-title.webp" alt="Title screen" /></td>
<td><img src=".github/media/screenshot-03-breach.webp" alt="Breach in progress with the full HUD" /></td>
</tr>
<tr>
<td><img src=".github/media/screenshot-06-special-ops.webp" alt="Special operation: airliner" /></td>
<td><img src=".github/media/screenshot-07-loadout.webp" alt="Squad loadout screen" /></td>
</tr>
<tr>
<td><img src=".github/media/screenshot-08-replay.webp" alt="Replay timeline" /></td>
<td><img src=".github/media/screenshot-09-debrief.webp" alt="Debrief with S rank" /></td>
</tr>
</table>

## Quick start

**Play online:** [devjay4561.github.io/open-breach](https://devjay4561.github.io/open-breach/)

**Run locally** with Node.js 20+ and Python 3:

```sh
git clone https://github.com/devjay4561/open-breach.git
cd open-breach
npm run build
npm start          # → http://127.0.0.1:8080
```

On macOS you can double-click [`Play.command`](Play.command) instead. Use a local HTTP server, because opening the HTML file directly is unsupported. You need a desktop browser with WebGL 2 and WebAssembly.

> [!TIP]
> Progress, settings, plans and recent replays live in your browser. Export the plans and replays you want to keep, because clearing site data removes them.

## Controls

| Action | Default |
| --- | --- |
| Select operator | Squad card or <kbd>1</kbd>–<kbd>4</kbd> |
| Plan movement | <kbd>Right-click</kbd> the floor · <kbd>Shift</kbd> + <kbd>Right-click</kbd> adds a waypoint |
| Door actions | Click a door · right-click for open / kick / flash |
| Run / pause | <kbd>Space</kbd> |
| Face / reload | <kbd>F</kbd> then click · <kbd>R</kbd> |
| Pan / zoom / reset camera | <kbd>W</kbd><kbd>A</kbd><kbd>S</kbd><kbd>D</kbd> · mouse wheel · <kbd>Home</kbd> |
| Cancel / menu | <kbd>Esc</kbd> |

Start with the tutorial. The in-game help and settings list every action and binding, including gamepad support.

## Build from source

The committed [`runtime/web/`](runtime/web/) export lets `npm run build` package `dist/` without Godot. To change the game itself, install **Godot 4.7.x** (the checked-in export and tool installer use **4.7.2**) and the matching Web export templates:

```sh
bash scripts/setup.sh        # or: python3 scripts/setup_tools.py
npm run build:engine
npm run build
```

Open [`game/project.godot`](game/project.godot) in Godot, or set `GODOT_BIN` to your Godot executable. The installer supports macOS and Linux. On Windows, install the matching editor and Web templates manually. `npm run build -- --portable` packages only the verified prebuilt export, and source and runtime hashes must match.

<details>
<summary><b>Deploy</b></summary>

Deploy the contents of `dist/` to any static host. The included [GitHub Pages workflow](.github/workflows/pages.yml) builds and deploys on every push to `main` once **Settings → Pages → Source** is set to **GitHub Actions**. The export is single-threaded, so it works under a sub-path such as `/open-breach/` without COOP/COEP headers.

</details>

<details>
<summary><b>Tests</b></summary>

The 30-seed room-entry benchmark reaches all four original goals in **3.00 s** (previously **6.73 s**). Mean doorway dwell is **1.158 s** per operator versus **1.542 s** for the matched manual plan, a **24.9% reduction**. Doorway dwell is reported for comparison and is not a pass/fail threshold.


```sh
npm ci
npm test            # Godot headless suites (needs Godot)
npm run test:meta
npm run test:build
```

On a fresh checkout with an explicit executable, run `"$GODOT_BIN" --headless --path game --import` first. The browser tests need Playwright and a running game:

```sh
npx playwright install chromium
npm start
npm run test:browser   # in another terminal
```

</details>

<details>
<summary><b>Repository layout</b></summary>

| Path | What's inside |
| --- | --- |
| [`game/`](game/) | Godot simulation, rendering, mission data and engine tests |
| [`web/`](web/) | Browser interface, settings, storage and web assets |
| [`runtime/web/`](runtime/web/) | Verified prebuilt browser engine |
| [`scripts/`](scripts/) · [`tests/`](tests/) | Build tools and automated checks |
| [`assets/source/`](assets/source/) | Editable asset sources |
| [`licenses/`](licenses/) · [`asset-manifest.json`](asset-manifest.json) | Notices, provenance and hashes |

</details>

## License & credits

| | License |
| --- | --- |
| Code | [MIT](LICENSE) © 2026 ijaehyeon |
| Original maps, models, sounds, art and the trailer | [CC0 1.0](licenses/CC0-1.0.txt), to the extent the project holds the rights |
| Characters, weapons and motion | Quaternius (Toon Shooter, Modular Characters) and KayKit Character Animations by Kay Lousberg, all CC0 |
| Furniture, nature, particles and impact sounds | Kenney, CC0 |
| Gunfire | Free Firearm Sound Library, CC0 |
| Fonts | Noto Sans KR, Oswald and JetBrains Mono, [SIL OFL 1.1](licenses/) |
| Engine | [Godot Engine](https://godotengine.org), MIT, with [third-party notices](licenses/Godot-COPYRIGHT.txt) |

The full path-by-path breakdown is in [ASSETS-LICENSE.md](ASSETS-LICENSE.md). Exact sources and hashes are in [asset-manifest.json](asset-manifest.json).

> [!NOTE]
> All operations, places, organizations and characters are fictional. Any resemblance to real events is coincidental.
