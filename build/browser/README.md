# build/browser — the engine-only page

Builds Cloudberry Kingdom's engine (levels drawn as boxes, no art, sound, music or video) into a static page that
runs in a browser tab: FNA + .NET 9 browser-wasm, Mono AOT, single-threaded, WebGL 2. The engineering record
(the walls met and why each fix is what it is) is [`docs/BROWSER.md`](../../docs/BROWSER.md).

```
build/browser/build.sh --game <patched Cloudberry-Kingdom clone> --out <site-dir>
                       [--fna <FNA clone>] [--natives <dir>] [--debug-log] [--api] [--build-id <text>]
                       [--fxc <fxc.exe>] [--shaders <dir of .fxb>] [--dotnet <dotnet>]
build/browser/serve.sh <site-dir> [port=8765]
node build/browser/tools/generate.cjs <site-url> '<args-json>' [out.json]
```

## What you need

- A clone of `PwneeStudios/Cloudberry-Kingdom` with `scripts/apply_patches.sh` applied (both stages, the default).
- A clone of `FNA-XNA/FNA` with the submodules `lib/SDL2-CS lib/SDL3-CS lib/FAudio lib/Theorafile lib/dav1dfile`
  (default location: a sibling of the game clone).
- Linux or WSL, with the **.NET 9 SDK** and the **`wasm-tools` workload**. A user-local install works:
  `dotnet-install.sh --channel 9.0 --install-dir ~/.dotnet && ~/.dotnet/dotnet workload install wasm-tools`
  (about 1.6 GB). The workload brings its own Emscripten (3.1.56), which matches the native archives below.
- **`fxc.exe`** (any Windows 10 SDK) for the 17 shaders. Under WSL, `build.sh` finds it in `C:\Program Files (x86)\Windows Kits`.
  Elsewhere pass `--fxc`, or pass `--shaders` with a directory of `.fxb` files compiled on Windows with
  `fxc /T fx_2_0 /Fo <name>.fxb <name>.fx`.
- Network on the first run: `build.sh` downloads the single-threaded native archives (`ST-SDL3.a`, `ST-FNA3D.a`,
  `ST-libmojoshader.a`, `ST-FAudio.a`, about 2.7 MB) of `r58Playz/FNA-WASM-Build` release
  `5ecb4294-8cbb-42f1-a73b-476bb46ddbb6` into `--natives`, checks each against a pinned sha256, and saves them under their
  `DllImport` names.

## What build.sh does

1. Fetches and checks the native archives (above).
2. `dotnet publish Game/Game.Browser.csproj -c Release -p:RunAOTCompilation=true`, with separate `obj-browser/` and
   `bin-browser/` directories so a native build's `obj/` is left alone. **This AOT step reruns on every build and takes about
   6–7 minutes** on an 8-core machine. For game-logic work, iterate on a native build (`Game.Core.csproj`) and publish the page rarely.
3. Stages `<site-dir>`: `_framework/` from the publish, `web/index.html` + `web/main.js`, the engine-only Content from
   `Game/ContentPC` (the four root `.dds`, `Campaign/`, `Localization/`, `Objects/`, the `.fnt` fonts, the shaders compiled
   to `.fxb`), `content-manifest.json`, and `build-info.json`.

`--debug-log` defines `DEBUG` in that Release build (AOT refuses a Debug configuration), which turns on the game's own
`Tools.Write` log lines such as `Level made!`. `--api` makes the page start in generator-API mode without `?api=1`.

**Never commit or publish `<site-dir>`.** `_framework/dotnet.native.wasm` and the webcil assemblies are the game's
compiled code, which only its rights holder can license. Serve it on `127.0.0.1` (that is all `serve.sh` binds).

## The page (`web/main.js`) and why it has shims

- **Content without `--preload-file`.** Emscripten's file packager does not survive the .NET 9 ES6 loader (it replaces
  `Module` after the packager registered its `preRun`). So the page fetches `content-manifest.json` and writes each file into
  the Emscripten FS between `create()` and `runMain()`.
- **Windows paths.** The game builds paths with `\` and with the wrong case in places (`Objects\MeatBoy.smo` versus
  `meatboy.smo`). The page wraps the FS entry points so `\` becomes `/`, and a path that matches a shipped Content file
  case-insensitively resolves to that file.
- **BGRA uploads.** The game's uncompressed `.dds` files load as `SurfaceFormat.ColorBgraEXT`, and FNA3D uploads them with
  `GL_BGRA`, which WebGL 2 does not have. The texture then samples black and every textured block disappears. The page
  converts those `texImage2D`/`texSubImage2D` calls to `GL_RGBA`, swapping the bytes as a desktop driver would. It also
  answers FNA3D's renderbuffer-format probe for the formats WebGL cannot render with the same `null` WebGL would give,
  without the console warning.
- **`MONO_INTERPRETER_OPTIONS=-precise`.** With .NET 9's default precise interpreter GC scan, the first garbage collection
  after FNA hands control to the Emscripten main loop never returns, and the tab freezes at the first demo level swap.
  Turning off that one option makes the scan conservative, as in .NET 8. `?interp_opts=` overrides it; an empty value
  restores the default, and the freeze with it.
- **`?api=1`**: `window.cloudberry = {ready(), generate(args), generateText(args), timings()}`. See the generator API in
  `docs/BROWSER.md`.
- Diagnostics: `?mono_log=<mask>` (Mono's own log), `?fpsbeacon=1` and `?logbeacon=1` (frame rate / console lines sent as
  GET requests that a static server's access log records, for reading a run on another machine).

`native/__Native.c` is one `#include`. FNA binds `emscripten_set_main_loop` with `[DllImport("__Native")]`, and the .NET
P/Invoke table generator only includes modules that are named `NativeFileReference`s. Without this file the main loop call fails at runtime.
