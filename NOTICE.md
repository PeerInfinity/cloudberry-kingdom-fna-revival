# Notice, attribution & redistribution

## What this repository is

Original build tooling, source patches, and documentation for reviving **Cloudberry Kingdom** on
FNA. It is licensed **MIT** (see [`LICENSE`](LICENSE)) and is safe to publish and share.

## What this repository is NOT

It contains **no** Cloudberry Kingdom source code, art, music, sound, fonts, or any built game
content. Nothing here is a copy or derivative *distribution* of the game's assets. The patches are
small unified diffs describing modifications; you apply them to a copy of the game you obtain
yourself.

## Cloudberry Kingdom

© **Pwnee Studios**. The source and assets are publicly available at
<https://github.com/PwneeStudios/Cloudberry-Kingdom> but carry **no license** — which means all
rights are reserved by default. You may build the game for your **own personal use** from that
source; you may **not** redistribute the game's code or assets (including compiled builds that embed
them) without permission from the rights holder.

> If you are Pwnee Studios (or the rights holder): adding a permissive `LICENSE` (MIT/BSD/CC0) to the
> repository above would let the community distribute finished builds and submit the handheld port to
> PortMaster. Thank you for open-sourcing the game.

## Third-party components (referenced, not redistributed here)

| Component | Author / Source | License |
|---|---|---|
| **FNA** | flibitijibibo & contributors — <https://fna-xna.github.io> | Ms-PL |
| **FNA3D, FAudio, Theorafile** | FNA-XNA | zlib / permissive |
| **MojoShader** | Ryan C. Gordon | zlib |
| **SDL2 / SDL3** | Sam Lantinga et al. | zlib |
| **MonoGame Content Builder (mgcb)** | MonoGame Team | Ms-PL / MIT |
| **Mono** | .NET Foundation | MIT |
| **.NET runtime + `wasm-tools` workload** (Mono on WebAssembly, the browser target) | .NET Foundation / Microsoft | MIT |
| **FNA-WASM-Build** (`SDL3.a`, `FNA3D.a`, `libmojoshader.a`, `FAudio.a` for the browser target) | r58Playz — <https://github.com/r58Playz/FNA-WASM-Build> | no licence stated; builds of the zlib components above. Downloaded by `build/browser/build.sh`, not vendored |
| **Emscripten** (bundled with the `wasm-tools` workload) | Emscripten contributors | MIT / LLVM |
| **PortMaster + tooling** (`MMLoader`, `hacksdl`, gptokeyb) | PortMaster team & contributors | see PortMaster |
| **Dust: An Elysian Tail port** (runtime pattern) | JanTrueno / PortMaster | — |
| **ffmpeg / libtheora / libvorbis / libogg** | FFmpeg & Xiph.Org | LGPL / BSD |

The browser target (this fork) is built the same way: `build/browser/build.sh` compiles your own clone
into a local page. The built page embeds the game's compiled code, so it is covered by the paragraph
on Cloudberry Kingdom above, and this repository never contains one.

When you assemble the R36S port you supply the FNA/Mono runtime binaries from a PortMaster port;
those remain under their own licenses and are **not** included in this repository.
