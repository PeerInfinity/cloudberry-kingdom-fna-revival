# Cloudberry Kingdom — FNA Revival (PC / Linux / R36S)

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

## License

The **original content of this repository** (build scripts, patches, docs) is released under the
**MIT License** — see [`LICENSE`](LICENSE). This license does **not** and **cannot** cover
Cloudberry Kingdom itself, which remains © Pwnee Studios.
