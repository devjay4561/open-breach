# OPEN BREACH licenses and asset notices

Copyright (c) 2026 ijaehyeon. Project code is MIT; project-owned assets are
CC0 1.0 only to the extent the copyright holder holds the relevant rights. Third-party
material retains its own license. Fonts are never relicensed as CC0.

Paths below are repository-relative. `dist/` and `build/web/` mirror the web
assets and notices. Exact file selections, source URLs, transformations and
hashes are recorded in [asset-manifest.json](asset-manifest.json), the
`licenses/provenance/` records.
Specific third-party rows take precedence over broader project-owned rows.

| Paths / material | License | Notice / evidence |
| --- | --- | --- |
| Project code: `game/scripts/`, `game/shaders/`, `game/tests/`, `web/*.js`, `web/*.css`, HTML, `scripts/`, `tests/`, project configuration | MIT | [LICENSE](LICENSE) |
| Original maps/missions and catalog JSON: `game/data/**/*.json`, original procedural/Godot/Blender geometry and pose adaptations, original `assets/source/` content | CC0-1.0 | [Original-Assets.txt](licenses/Original-Assets.txt), [CC0 text](licenses/CC0-1.0.txt) |
| Original UI/ambient sounds: `web/assets/audio/{ambient,fail,order,select,stun,win}.wav` | CC0-1.0 | [Original-Assets.txt](licenses/Original-Assets.txt) |
| Original equipment geometry: `game/assets/equipment/{veil_v1,frame_v2,swift_v3,bastion_v4,dot,scope,suppressor,extended_mag,probe_c1,flare_f1,haze_s1,knock_b1}.glb` | CC0-1.0 | [Original-Assets.txt](licenses/Original-Assets.txt), [equipment sources](licenses/Operator-Equipment-CC0.txt) |
| Original special operations models: `game/assets/historical/*.glb` except the Kenney files below; original special operations `.blend` sources in `assets/source/historical/blender/` (except the Kenney adaptations below), renders in `game/assets/historical/previews/*.png` | CC0-1.0 | [special-ops-assets-original.txt](licenses/special-ops-assets-original.txt), [Original-Assets.txt](licenses/Original-Assets.txt) |
| 20 generated photos: `web/assets/equipment/*.jpg`, generation records `web/assets/equipment/generation.json` | CC0-1.0, to the extent any copyright exists and is held by the project copyright holder | [Equipment-Images.txt](licenses/Equipment-Images.txt) |
| Project-authored README media in `.github/media/` (trailer video, poster, banner, animated preview, screenshots), README and project documentation. The trailer shows gameplay of the CC0/OFL assets listed here; its soundtrack is project-synthesized plus the game's own Kenney Impact Sounds and Free Firearm Sound Library CC0 effects. Embedded third-party material keeps its license | CC0-1.0 to the extent rights are held by the project copyright holder | [Original-Assets.txt](licenses/Original-Assets.txt) |
| Quaternius Modular Characters / SWAT / rifle sources and adaptations: `game/assets/characters/{soldier,swat,rifle,combat-swat,combat-swat-gear}.glb` | CC0-1.0 | [Quaternius-Modular-Characters.txt](licenses/Quaternius-Modular-Characters.txt), [Original-Assets.txt](licenses/Original-Assets.txt) |
| Quaternius Toon Shooter motion embedded in `game/assets/characters/combat-swat*.glb` | CC0-1.0 | [Quaternius-Toon-Shooter.txt](licenses/Quaternius-Toon-Shooter.txt) |
| KayKit Character Animations 1.1 Throw motion embedded in `game/assets/characters/combat-swat*.glb` | CC0-1.0 | [KayKit-Character-Animations.txt](licenses/KayKit-Character-Animations.txt) |
| Quaternius Universal Animation Library reference source: `game/assets/characters/ual-source.glb` (not used by shipped combat GLBs) | CC0-1.0 | [Quaternius-Universal-Animation-Library.txt](licenses/Quaternius-Universal-Animation-Library.txt) |
| Quaternius adapted weapons/headgear: `game/assets/equipment/{tern_c1,mica_s2,flint_b1,pico_p1,crown_h1,crown_h2,mask_h0}.glb`; adapted gear character `game/assets/characters/combat-swat-gear.glb` | CC0-1.0 | [Operator-Equipment-CC0.txt](licenses/Operator-Equipment-CC0.txt) |
| Kenney Furniture Kit: `game/assets/environment/*.glb` (including adapted `doorLeaf.glb`) | CC0-1.0 | [Kenney-Furniture.txt](licenses/Kenney-Furniture.txt) |
| Kenney Nature Kit: `game/assets/historical/{pine_tree,palm_tree,bush}.glb`; source archive `assets/source/historical/kenney_nature-kit.zip`, GLB sources `assets/source/historical/kenney/*.glb`, and Blender adaptations `assets/source/historical/blender/{pine_tree,palm_tree,bush,rock_small,rock_medium,rock_large}.blend` | CC0-1.0 | [special-ops-assets-kenney-nature.txt](licenses/special-ops-assets-kenney-nature.txt) |
| Kenney Particle Pack: `game/assets/vfx/{smoke_05,fire_01,spark_01}.png` | CC0-1.0 | [Kenney-Particles.txt](licenses/Kenney-Particles.txt) |
| Kenney Impact Sounds: `web/assets/audio/{hit*,door*,footstep*}.wav` (exact files in tactical-audio provenance) | CC0-1.0 | [Kenney-Impact-Sounds.txt](licenses/Kenney-Impact-Sounds.txt) |
| Free Firearm Sound Library: `web/assets/audio/{shot,shot_alt,shot_close,shot_close_alt}.wav` | CC0-1.0 | [Free-Firearm-Library.txt](licenses/Free-Firearm-Library.txt) |
| Noto Sans KR: `game/assets/fonts/NotoSansKR.ttf`, `web/assets/fonts/NotoSansKR.woff2` | OFL-1.1 | [NotoSansKR-OFL.txt](licenses/NotoSansKR-OFL.txt) |
| Oswald: `game/assets/fonts/Oswald-700.ttf`, `web/assets/fonts/Oswald-700.woff2` | OFL-1.1 | [Oswald-OFL.txt](licenses/Oswald-OFL.txt) |
| JetBrains Mono: `game/assets/fonts/JetBrainsMono-500.ttf`, `web/assets/fonts/JetBrainsMono-500.woff2` | OFL-1.1 | [JetBrainsMono-OFL.txt](licenses/JetBrainsMono-OFL.txt) |
| Godot boot image: `runtime/web/engine.png` | CC-BY-4.0 | Godot Engine logo by Andrea Calabró; unmodified exported boot image. [Godot-COPYRIGHT.txt](licenses/Godot-COPYRIGHT.txt), [official artwork license](https://godotengine.org/press/) |
| Godot engine runtime: `runtime/web/engine.{js,wasm}`, engine bootstrap files and copies in `dist/` / `build/web/`; bundled third-party components retain their notices | MIT plus bundled third-party licenses | [Godot-MIT.txt](licenses/Godot-MIT.txt), [Godot-COPYRIGHT.txt](licenses/Godot-COPYRIGHT.txt) |

The engine `.pck` packages project code/assets under the licenses above; it
does not make the game content part of Godot's own license. Dependencies
(such as Playwright) retain their upstream licenses and notices.

CC0 does not grant trademark, patent, privacy or publicity rights. No rights
in third-party brands, insignia, quoted source text or identifiable people
are granted by this project's dedication. All operations, places, organizations and characters are fictional. Any resemblance to real events is coincidental.

모든 작전, 장소, 조직과 등장인물은 가상입니다. 실제 사건과의 유사성은 우연입니다.

`game/assets/characters/reload.tres` (unused by the web export) is a CC0-1.0
derivative: `game/tests/retarget_reload.gd` regenerates it byte-for-byte from
the Quaternius Universal Animation Library `Pistol_Reload` clip in
`ual-source.glb` retargeted onto the Quaternius `soldier.glb` skeleton
(verified 2026-10-22). See
[Quaternius-Universal-Animation-Library.txt](licenses/Quaternius-Universal-Animation-Library.txt).
