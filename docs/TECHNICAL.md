# Cloudberry Kingdom on FNA — Technical Writeup

How an abandoned **XNA** game was brought back to life on modern PC/Linux and on an ARM handheld.
This document explains every non-obvious problem and the fix, so the patches in [`../patches/`](../patches/)
and the scripts in [`../build/`](../build/) make sense.

- [1. The problem: XNA is dead](#1-the-problem-xna-is-dead)
- [2. FNA and the project file](#2-fna-and-the-project-file)
- [3. The content pipeline](#3-the-content-pipeline)
- [4. Bugs the build surfaced](#4-bugs-the-build-surfaced)
- [5. Native libraries](#5-native-libraries)
- [6. Packaging (Windows)](#6-packaging-windows)
- [7. The R36S handheld port](#7-the-r36s-handheld-port)
- [8. The performance story (read this)](#8-the-performance-story-read-this)
- [9. Patch reference](#9-patch-reference)

---

## 1. The problem: XNA is dead

Cloudberry Kingdom targets **Microsoft XNA Game Studio 4.0**, discontinued in 2013. It doesn't
install on modern Windows and never supported Linux. The game's C# is fine; the *framework* under
it is gone.

**[FNA](https://fna-xna.github.io/)** is a faithful, actively-maintained reimplementation of XNA 4.0
that runs on Windows/Linux/macOS and consoles. Migrating to FNA keeps ~all of the game's C# intact
and swaps the dead framework for a living one. Handily, Pwnee's repo already contained a half-started
`Game.SDL2.csproj` referencing FNA — evidence they'd begun this exact migration.

Two flavors of FNA exist:
- **FNA (modern, .NET 8, SDL3)** — used for the PC/Linux build. `FNA.Core.csproj`.
- **FNA (classic, .NET Framework / Mono, SDL2)** — used for the R36S build (Mono), because that's
  the runtime the handheld ecosystem (PortMaster) is built on. See [§7](#7-the-r36s-handheld-port).

---

## 2. FNA and the project file

The original `.csproj` is old-style MSBuild with 402 explicit `<Compile Include>` items. Rather than
fight it, we author a clean **SDK-style** project ([`patches/Game.Core.csproj`](../patches/Game.Core.csproj))
that:

- targets `net8.0`, `OutputType=Exe`, `AllowUnsafeBlocks=true`;
- sets `EnableDefaultItems=false` and reuses the **exact 402 file list** from `Game.SDL2.csproj`
  (so we compile the intended FNA set and *not* the XNA-only or `__Editors/` files);
- sets `GenerateAssemblyInfo=false` (the repo has its own `AssemblyInfo.cs`; otherwise you get
  `CS0579: duplicate attribute`);
- `ProjectReference`s `..\..\FNA\FNA.Core.csproj`;
- `DefineConstants = WINDOWS;GAME;PC_VERSION;PC;SDL2`.

That last line matters: the game's menu **mouse hit-testing** (`MenuItem.HitTest`) lives under
`#if WINDOWS`, and several subclasses `override` it unconditionally — so *without* `WINDOWS` you get
`CS0115: no suitable method to override`. Defining `WINDOWS` alongside `SDL2` is exactly what Pwnee's
own SDL2 config did, and the `SDL2` guard keeps the truly Windows-only bits (WinForms, etc.) out —
the compiled assembly ends up with **no** references to `System.Windows.Forms`/`System.Drawing`.

With that, the game **compiles to a `CloudberryKingdom.exe` with zero errors.** The hard part isn't
the code — it's the content.

---

## 3. The content pipeline

Pwnee's repo ships content as **raw source**, not compiled `.xnb`:
825 `.dds` textures, 30 `.wav`, 18 `.fx` shaders, 12 `.wma` songs, 10 `.wmv` videos, plus `.tsv`
data and `.fnt` fonts. The game loads `Content/*.xnb` at runtime (`Content.RootDirectory = "Content"`),
so everything must be built. [`build/build_content.ps1`](../build/build_content.ps1) does all of it.

### 3.1 Shaders (`.fx` → `.fxb`)

FNA renders effects through **MojoShader**, which consumes `fx_2_0` bytecode built by **FXC** (the
DirectX effect compiler). Two happy surprises:

1. The **modern Windows 10/11 SDK `fxc.exe` still compiles `fx_2_0`** (it prints a deprecation
   warning `X4717` but succeeds). No need for the ancient June-2010 DirectX SDK.
2. We **bypass the XNB wrapper entirely.** Instead of `Content.Load<Effect>`, we load the raw `.fxb`
   with `new Effect(GraphicsDevice, File.ReadAllBytes(...))`. That's the `LoadEffectFXB` helper in
   [`Resources.patch`](../patches/Resources.patch); the 16 shader loads in `Tools.cs` are switched to
   it ([`Tools.patch`](../patches/Tools.patch)). No XNA content pipeline required for shaders.

`RootEffect.fx` is an include-only file (no `technique`) and is skipped.

### 3.2 Textures & audio (`.dds`/`.wav` → `.xnb`)

Built with the **MonoGame Content Builder (`mgcb`)**. FNA reads MonoGame-built `Texture2D`/`SoundEffect`
XNBs fine. Two gotchas:

- The game expects `PremultiplyAlpha=False` and `TextureFormat=NoChange` (mgcb defaults to
  premultiplied — get this wrong and blending is visibly off).
- **mgcb path quirk:** relative `/build:` paths resolve against the **response-file directory**, but
  the *output* sub-path is computed from the **process working directory**. Both must be the content
  root, so the script writes the response file into `ContentPC/` and runs mgcb via `Push-Location`
  there. (PowerShell's `Set-Location`/`Push-Location` sets `$PWD`, which is what a native child's CWD
  inherits — `[Directory]::SetCurrentDirectory` alone does **not** work here.)

### 3.3 Music (`.wma` → `.ogg`)

XNA used Windows Media; FNA plays **Ogg Vorbis**. We transcode with ffmpeg and load the `.ogg`
directly via `Song.FromUri(name, new Uri(fullPath))`, bypassing the XNB `Song` reader
([`EzSong.patch`](../patches/EzSong.patch)). The game already enumerates `Content/Music` and, under
`#if SDL2`, looks for `.ogg` — Pwnee had planned this too.

### 3.4 Video (`.wmv` → `.ogv`) — and a real bug

Videos become **Ogg Theora** (`libtheora` + `libvorbis`), loaded with `Video.FromUriEXT(uri, gd)`
([`Video.patch`](../patches/Video.patch)). But FNA's raw-file `Video` constructor sets
`Duration = TimeSpan.MaxValue` (Theora has no cheap duration), and the game ends a video when
`Elapsed > Duration` — which is **never** true, so the intro logo hangs on a black screen forever.
Fix: also end when `VideoPlayer.State == MediaState.Stopped` (FNA sets this at end-of-stream). The
same patch makes `StartVideo` **skip gracefully if the `.ogv` is missing**, which lets handheld
builds omit videos entirely for a faster boot.

### 3.5 Fonts & data

The `.fnt` files are a **custom bitmap-font format** (glyph pixel-rects + a `.dds` atlas), loaded by
the game's own loader per-language (`Localization.LoadFont` picks only the current language's atlas).
They are copied as-is and the atlas `.dds` are built like any texture. `.tsv`/`.txt`/`.smo` data files
are copied verbatim into `Content/`.

---

## 4. Bugs the build surfaced

Building **Release** (not Debug) exposed code paths Debug hid:

- **`DigitalDayBuild` orphaned symbol** — referenced in the `#else` (production) branch of
  `CloudberryKingdom.cs` but never declared. Compiles in Debug (the `#if DEBUG` branch avoids it),
  breaks in Release. Fixed by declaring `public const bool DigitalDayBuild = false;`
  ([`CloudberryKingdom.patch`](../patches/CloudberryKingdom.patch)).
- **Silent audio** — `XnaGameClass` sets volumes to `0` under `#if DEBUG || INCLUDE_EDITOR` (a dev
  mute). It's compiled out in Release, but the `0` can get **persisted to the settings file** and
  then bleed back in. We removed the debug-mute and set a proper `DefaultValue` on the volume
  `WrappedFloat`s ([`XnaGameClass.patch`](../patches/XnaGameClass.patch)).
- **Intro video hang** — see [§3.4](#34-video-wmv--ogv--and-a-real-bug).

---

## 5. Native libraries

FNA is managed C#; the real work happens in native libs it P/Invokes: **SDL** (window/input/GL),
**FNA3D** (graphics; Vulkan/D3D11/OpenGL), **FAudio** (audio), **Theorafile** (video). Modern FNA
defaults to **SDL3**; its `FNA.dll.config` dllmaps `SDL3`/`FNA3D`/`FAudio`/`dav1dfile` to the platform
`.so`/`.dll`. Grab them from **fnalibs-dailies** (see the README) and drop the right platform folder
next to the executable. On a desktop GPU FNA3D picks **Vulkan** automatically.

---

## 6. Packaging (Windows)

[`build/build_release.ps1`](../build/build_release.ps1) does `dotnet publish -r win-x64
--self-contained` (bundles the .NET runtime so end users need nothing installed; **no trimming** —
FNA uses reflection), then copies the `x64` native libs + `D3D12/` + `Content/`. The project sets
`ApplicationIcon` to the game's own `.ico`. [`build/installer.iss`](../build/installer.iss) is an
Inno Setup script producing a ~compressed installer with Start-menu/desktop shortcuts and an
uninstaller.

---

## 7. The R36S handheld port

The Anbernic R36S is a **Rockchip RK3326** (quad Cortex-A35 ~1.5 GHz, **Mali-G31**, **1 GB RAM**)
running **ArkOS** (aarch64 Linux). Two hard constraints shaped everything:

1. **No usable Vulkan.** Mali-G31 exposes only **OpenGL ES 3.x** on Linux (Panfrost's Vulkan is
   disabled on this SoC). FNA3D must use its **OpenGL** backend; MojoShader targets the **`glsles`**
   profile — which our `fx_2_0` shaders translate to cleanly.
2. **Old userland + the handheld ecosystem runs on Mono/SDL2.** The proven way to run an FNA game on
   these devices is **PortMaster**: a shared **Mono 6.12** runtime + **classic SDL2 FNA** + a small
   **`MMLoader`** (which also ASTC-recompresses textures for the 1 GB budget) + **`hacksdl`** (a
   shim for the 640×480 screen). This is exactly how *Dust: An Elysian Tail* — another FNA game — is
   ported, and it's the pattern we follow.

So the R36S build is a **second configuration**, [`patches/Game.Mono.csproj`](../patches/Game.Mono.csproj):
`net472`, referencing a **classic SDL2 `FNA.dll`** (from an existing PortMaster FNA port), with
`DefineConstants = WINDOWS;GAME;PC_VERSION;PC;SDL2;MONO;HANDHELD`. It compiles to a Mono-runnable
`.exe` with no Windows-only references.

The launcher ([`build/r36s-launcher.sh`](../build/r36s-launcher.sh)) sets the critical environment:

```sh
export FNA3D_FORCE_DRIVER=OpenGL          # no Vulkan on Mali-G31
export FNA3D_OPENGL_FORCE_ES3=1
export FNA3D_OPENGL_FORCE_VBO_DISCARD=1   # Mali perf hack
export MONO_IOMAP=all                     # map XNA's Windows-style back-slash paths
```

See [`R36S.md`](R36S.md) for assembling the port and the runtime you must supply.

---

## 8. The performance story (read this)

This is the most useful part, because the intuitive optimizations **didn't work** and the real fix
was surprising.

The first R36S build ran at ~70–80% speed with more slowdown in busy scenes. The obvious levers:

- **Lower the render resolution.** No effect — because **HackSDL pins the surface to 640×480**, so
  the game is already rendering low; it is *not* fill-rate bound. (A `CK_RENDER_SCALE` experiment was
  added and then **removed** — it did nothing and confused the in-game resolution option.)
- **Resize textures to 40%** and **halve particles.** Barely moved the needle. Kept only because
  they shrink the package (664 MB → ~180 MB) and ease memory, not for speed.

The real win was a **built-in option the game already had: "Anders."** Toggling it (`AndersSwitch`,
gated behind `CodersEdition = true`) makes `LevelSeedData.SetTileSet` convert **every** environment
to one of **three simple "Anders" tilesets**. The bottleneck was the *variety and complexity of the
detailed background art* — draw-call count and per-object work — not textures or particles. With
Anders on, the game runs **full speed**. The handheld build therefore **defaults `AndersSwitch = true`**
(it's still toggleable in Options).

**Takeaway:** on weak, GL-driver-limited hardware, reducing *scene/draw-call complexity* beat every
pixel/memory optimization. Measure before you optimize; the profiler here was the device itself.

---

## 9. Patch reference

All patches are unified diffs against `PwneeStudios/Cloudberry-Kingdom@master`, apply from the game
repo root (`git apply` or `patch -p1`). See [`../scripts/apply_patches.ps1`](../scripts/apply_patches.ps1).

| Patch | File | What it does |
|---|---|---|
| `Resources.patch` | `Engine/GameTools/Resources.cs` | `LoadEffectFXB` — load `.fxb` shaders without XNB |
| `Tools.patch` | `Engine/GameTools/Tools.cs` | route the 16 effect loads through `LoadEffectFXB` |
| `EzSong.patch` | `Engine/Song/EzSong.cs` | load `.ogg` songs via `Song.FromUri` |
| `Video.patch` | `Engine/Video.cs` | `.ogv` via `FromUriEXT`; fix `Duration=MaxValue` hang; skip if missing |
| `CloudberryKingdom.patch` | `MainClass/CloudberryKingdom.cs` | declare `DigitalDayBuild`; default `AndersSwitch` on for `HANDHELD` |
| `XnaGameClass.patch` | `MainClass/XnaGameClass.cs` | remove debug volume-mute; set volume `DefaultValue` |
| `ParticleEmitter.patch` | `Engine/ParticleEffects/ParticleEmitter.cs` | halve particle capacity on `HANDHELD` |

The two `.csproj` files in `patches/` are new (drop them into `Game/`), not diffs.
