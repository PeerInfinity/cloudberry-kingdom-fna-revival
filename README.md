# Cloudberry Kingdom — FNA Revival (PC / Linux / R36S) + browser target

## This fork

This is PeerInfinity's fork of [fera89/cloudberry-kingdom-fna-revival](https://github.com/fera89/cloudberry-kingdom-fna-revival).
It keeps the upstream "bring your own source" model and adds four things on top of the upstream patch set:

| Adds | What it is |
|---|---|
| **Engine-only mode** | Pwnee's own placeholder mode (`CloudberryKingdomGame.LoadResources = false`): levels are drawn as collision boxes, with a patch that makes music and sound silent. The game needs no art, sound, music or video, only about 1 MB of data files and compiled shaders from your clone. |
| **Browser target** | The engine-only game on FNA + .NET 9 browser-wasm (Mono AOT, single-threaded, WebGL 2), as a static page you build and serve locally. The page carries two host shims: WebGL has no BGRA texture upload, and Mono 9's precise interpreter GC scan must be off. See [`docs/BROWSER.md`](docs/BROWSER.md). |
| **Keyboard control** | The page plays with the game's own PC bindings. Menus: arrows (or W/S) choose, Enter or Space confirm, Esc back. In a level: ←/→ or A/D run, ↑ or W jump, Esc pause, Enter the power-up menu, Space restart from the door. Menu and HUD text is readable: the page draws a placeholder glyph atlas with the browser's own font onto the game's glyph rectangles. |
| **Generator API** | Seed + difficulty + hero in, a JSON level (`ck-level/1`: blocks, obstacles, the goal) plus the computer player's recorded input and trace out. It works in the tab (`window.cloudberry.generate({...})`) and natively (`--generate`), with the same bytes on both. |

The fork's patches live in [`patches/browser/`](patches/browser/) and are applied after upstream's by
`scripts/apply_patches.sh` / `.ps1`. The fork's set turns `LoadResources` off for every target, so to follow the
upstream README below (the full-content PC and R36S builds) apply with `--upstream-only` (`-UpstreamOnly`).
`scripts/export_patches.sh` regenerates them from a local branch, and `build/browser/build.sh` rebuilds the page.

### Quick start (browser)

Linux or WSL, with the .NET 9 SDK + `dotnet workload install wasm-tools`, and `fxc.exe` from a Windows SDK (WSL) or prebuilt `.fxb` shaders:

```bash
git clone https://github.com/PwneeStudios/Cloudberry-Kingdom.git
git clone https://github.com/FNA-XNA/FNA.git && git -C FNA submodule update --init lib/SDL2-CS lib/SDL3-CS lib/FAudio lib/Theorafile lib/dav1dfile
git clone -b browser https://github.com/PeerInfinity/cloudberry-kingdom-fna-revival.git
cloudberry-kingdom-fna-revival/scripts/apply_patches.sh Cloudberry-Kingdom
cloudberry-kingdom-fna-revival/build/browser/build.sh --game Cloudberry-Kingdom --fna FNA --out site   # ~7 min (AOT)
cloudberry-kingdom-fna-revival/build/browser/serve.sh site 8765    # http://127.0.0.1:8765/  (?api=1 for the generator API)
```

### What is NOT here (browser target)

No built page, ever. The AOT `.wasm` and the assemblies in `_framework/` embed the game's compiled code, so this
repository has no `site/`, no `_framework/`, no native archives and no GitHub Pages deployment of the game, and
`.gitignore` covers them. You build the page locally from your own clone of Pwnee's source, as with the upstream `.exe`.

### Rights holders: takedown on request

If you hold rights to Cloudberry Kingdom (Pwnee Studios or its successors) and want this repository changed or
removed, open an issue on [this repository](https://github.com/PeerInfinity/cloudberry-kingdom-fna-revival/issues)
and we will comply promptly. GitHub's DMCA process is also available. We also support upstream's request for an
open licence: [PwneeStudios/Cloudberry-Kingdom#173](https://github.com/PwneeStudios/Cloudberry-Kingdom/issues/173).

### How this fork was made

The patches, the page, the scripts and the docs in this fork were written by Claude (Anthropic) sessions directed by
PeerInfinity. The measurements behind each change are recorded in the commit messages and in [`docs/BROWSER.md`](docs/BROWSER.md).

### Upstream

This fork is meant to be offered back to fera89 as a pull request once it is stable, so the two do not diverge.

---

## Upstream README

Build tooling and source patches that revive **Cloudberry Kingdom** (Pwnee Studios, 2013)
on modern **Windows/Linux** via [FNA](https://fna-xna.github.io/), and on the
**Anbernic R36S** handheld (ArkOS) via the PortMaster FNA-on-Mono runtime.

The original game runs on the long-dead **XNA Framework**, so it won't build or run on a
modern machine as-is. This project migrates it to FNA (an actively-maintained,
cross-platform XNA4 reimplementation) and rebuilds all of its content with an open toolchain.

> **This repository contains NO game code or assets.** It ships only original build scripts,
> unified-diff patches, and documentation. You **bring your own source** from Pwnee Studios'
> own public repository. See [Legal / "Bring Your Own Source"](#legal--bring-your-own-source).

---

## What you get

| Target | Result |
|---|---|
| **Windows** | Self-contained `.exe` (no .NET install needed), Vulkan via FNA3D, optional Inno Setup installer |
| **Linux** | Same self-contained approach (`linux-x64`); native libs vendored by FNA |
| **R36S / ArkOS** | A PortMaster port (`cloudberry/` + `.sh`) running on Mono + classic SDL2 FNA + GLES, **full-speed** |

Everything is reproducible from scripts in [`build/`](build/). The full story of *how* and *why*
each piece works is in [`docs/TECHNICAL.md`](docs/TECHNICAL.md) (recommended reading).

---

## Legal / "Bring Your Own Source"

Pwnee Studios published Cloudberry Kingdom's full source **and assets** on their own GitHub
([PwneeStudios/Cloudberry-Kingdom](https://github.com/PwneeStudios/Cloudberry-Kingdom)), but
**without a license**. Under default copyright that means "all rights reserved," so the game's
code and assets **cannot be redistributed** here. This repo therefore follows the same model
PortMaster uses for commercial games: **you supply the game, we supply the tooling.**

You will need to obtain the source yourself:

```bash
git clone https://github.com/PwneeStudios/Cloudberry-Kingdom.git
```

If you are the rights holder (or know them): adding a permissive `LICENSE` (MIT/BSD/CC0) to that
repo would let the community distribute finished builds and submit the handheld port to
PortMaster. See the issue template idea in [`docs/TECHNICAL.md`](docs/TECHNICAL.md).

---

## Prerequisites

| Tool | Why | Install (Windows) |
|---|---|---|
| **.NET 8 SDK** | build the game (`dotnet`) | `winget install Microsoft.DotNet.SDK.8` |
| **MonoGame Content Builder** | textures/audio → `.xnb` | `dotnet tool install -g dotnet-mgcb` |
| **ffmpeg** | `.wma`→`.ogg`, `.wmv`→`.ogv`, texture resize | `winget install Gyan.FFmpeg` |
| **Windows 10/11 SDK** | `fxc.exe` compiles shaders to `fx_2_0` | (ships with VS / Windows SDK) |
| **Inno Setup 6** (optional) | Windows installer | `winget install JRSoftware.InnoSetup` |
| **FNA** | the XNA reimplementation | see below |
| **Cloudberry Kingdom source** | the game | see [Legal](#legal--bring-your-own-source) |

### FNA

```bash
git clone --depth 1 https://github.com/FNA-XNA/FNA.git
cd FNA
git submodule update --init --depth 1 lib/SDL2-CS lib/SDL3-CS lib/FAudio lib/Theorafile lib/dav1dfile
```
FNA's native libraries (`SDL3.dll`, `FNA3D.dll`, `FAudio.dll`, `libtheorafile.dll`, …) come from
[fnalibs-dailies](https://github.com/FNA-XNA/fnalibs-dailies). A public download for the latest
build is available via nightly.link:
`https://nightly.link/FNA-XNA/fnalibs-dailies/workflows/ci/main/fnalibs.zip`
Put the platform folders (`x64/`, `lib64/`, `libaarch64/`, `D3D12/`) under `build/fnalibs/`.

---

## Quick start (Windows / Linux)

Assuming this repo, `Cloudberry-Kingdom/`, and `FNA/` are siblings:

```
GitHub/
  cloudberry-kingdom-fna-revival/   <- this repo
  Cloudberry-Kingdom/               <- git clone of Pwnee's source
  FNA/                              <- git clone of FNA
```

```powershell
# 1. Apply patches + deploy the project files and build/ scripts into your game clone
pwsh scripts/apply_patches.ps1 -GameRepo ..\Cloudberry-Kingdom

# ...then work from inside the clone (the scripts expect its layout):
cd ..\Cloudberry-Kingdom

# 2. Build all content (shaders, textures, audio, music, video, data)
pwsh build/build_content.ps1            # writes Game/BuiltContent

# 3. Self-contained release -> dist/CloudberryKingdom
pwsh build/build_release.ps1 -SkipContent

# 4. (optional) installer -> dist/CloudberryKingdom-Setup-<ver>.exe
pwsh build/build_installer.ps1
```

Run it: `dist/CloudberryKingdom/CloudberryKingdom.exe`
(Put `fnalibs/` under `Cloudberry-Kingdom/build/fnalibs` before step 2/3 — see [Prerequisites](#prerequisites).)

## Quick start (R36S / ArkOS)

See [`docs/R36S.md`](docs/R36S.md) for the full handheld guide (PortMaster runtime, the "Anders"
performance mode, HackSDL, controls). In short:

```powershell
pwsh build/build_content_r36s.ps1       # 40%-resized textures -> BuiltContent-R36S
pwsh build/build_r36s_port.ps1          # assembles dist/CloudberryKingdom-Port
```
Copy `Cloudberry Kingdom.sh` + `cloudberry/` into your device's `/roms/ports/` and launch it
from the **Ports** menu.

---

## Repository layout

```
build/                 Build scripts (PowerShell + the R36S launcher/port.json)
patches/               Unified-diff patches + the SDK-style .csproj files (our work)
scripts/               apply_patches helpers
docs/
  TECHNICAL.md         The full engineering writeup (how every problem was solved)
  R36S.md              Handheld-specific guide
LICENSE                MIT (covers THIS repo's original content only)
NOTICE.md              Attribution + what you may/may not redistribute
```

---

## Credits & thanks

- **Pwnee Studios** — for making Cloudberry Kingdom and open-sourcing it.
- **[FNA](https://fna-xna.github.io/)** (flibitijibibo & contributors) — XNA reimplemented, beautifully.
- **[PortMaster](https://portmaster.games/)** and the **Dust: An Elysian Tail** porter (JanTrueno) —
  the FNA-on-Mono handheld runtime pattern this project follows.
- **MojoShader**, **FAudio**, **Theorafile**, **SDL** — the native backends that make it all run.
- **Claude (Anthropic)** — AI pair-programmer for the whole revival: the XNA→FNA migration, the
  content/shader/audio/video pipeline, the on-device debugging, and the R36S / Mono / PortMaster port.

## License

The **original content of this repository** (build scripts, patches, docs) is released under the
**MIT License** — see [`LICENSE`](LICENSE). This license does **not** and **cannot** cover
Cloudberry Kingdom itself, which remains © Pwnee Studios.
