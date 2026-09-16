# Cloudberry Kingdom in a browser tab — engine-only, FNA + .NET 9 browser-wasm

This is the engineering record for this fork's browser target: what it is, the walls met on the way, the cause of each,
and why each fix has the shape it has. It also specifies the generator API. The build steps are in
[`../build/browser/README.md`](../build/browser/README.md); the patches are in [`../patches/browser/`](../patches/browser/).

- [1. What runs](#1-what-runs)
- [2. Engine-only mode](#2-engine-only-mode)
- [3. The browser build](#3-the-browser-build)
- [4. The walls, in order](#4-the-walls-in-order)
- [5. The two page shims](#5-the-two-page-shims)
- [6. The generator API](#6-the-generator-api)
- [7. Patch reference](#7-patch-reference)
- [8. Known gaps](#8-known-gaps)

---

## 1. What runs

The C# game, engine-only (Pwnee's own `LoadResources = false` placeholder mode: collision boxes instead of art, silent
audio), on FNA + .NET 9 browser-wasm: Mono AOT, **single-threaded** (no `WasmEnableThreads`, so no COOP/COEP headers),
FNA3D's OpenGL driver on **WebGL 2**. The attract-mode ScreenSaver generates level after level and plays them with the computer
player, drawn as shapes. Measured on a desktop GPU in Chrome: 58–61 frames/s over 229 s, 29 levels made in 223 s. Headless
Chromium without a GPU (SwiftShader) draws 7–9 frames/s; that limit is the software rasteriser, not the game.

Payload per page load, uncompressed: `dotnet.native.wasm` ≈ 17.9 MB, the JS loader ≈ 0.5 MB, 27 webcil assemblies
≈ 5.7 MB, Content ≈ 1.1 MB, so ≈ 25 MB in total (no compression, no trimming beyond `TrimMode=partial`).

## 2. Engine-only mode

Jordan Fisher's 2016 commit `f401be35` ("Game now works (and is somewhat readable) without any art resources") added
`CloudberryKingdomGame.LoadResources`. With it `false`, every texture and font resolves to the 1×1 `White` texture,
`Tools.DrawBoxes = true` and `Tools.DrawGraphics = false`. The fork sets it `false` and adds the one thing that mode was
missing: **silent audio**. Without sound files, `Resources.LoadMusic` throws on the missing `Content/Music` directory, and
`CoreSongWad.FindByName` / `CoreSoundWad.FindByName` index an empty list. So in engine-only mode:

- `LoadMusic` / `LoadSound` enumerate no files;
- `FindByName` registers a silent entry under the requested name on a miss (no hard-coded name list);
- `XnaSong.LoadSong` skips loading; `XnaSong.Play` returns `SilentSongSeconds` for a null song; `CoreSound.Play*` return on a null `SoundEffect`.

What the engine still reads (≈ 1.08 MB, staged by `build.sh` from `Game/ContentPC`): the four root `.dds` files (`White`,
`Circle`, `Smooth`, `Transparent`; FNA's `ContentManager` loads raw `.dds`, so no XNB step is needed), `Campaign/`, `Localization/`,
the 8 `Objects/*.smo` animations, the `.fnt` font metrics, and 17 shaders compiled to `.fxb` (`fxc /T fx_2_0`; `RootEffect.fx` is include-only).

The same mode runs natively (`Game.Core.csproj`, Windows or Linux). A native build is the control for anything that
looks wrong in the tab: if it also happens natively, it is not a browser problem.

## 3. The browser build

`Game/Game.Browser.csproj` (a new file) is `Microsoft.NET.Sdk.WebAssembly`, `net9.0`, with the same 402 `Compile` items
as `Game.Core.csproj` and `DefineConstants = WINDOWS;GAME;PC_VERSION;PC;SDL2;BROWSER`. It sets:

| Setting | Why |
|---|---|
| `RunAOTCompilation=true` (passed by `build.sh`) | The interpreter traps on `SDL_CreateWindow` (a `uint64` flags argument): `RuntimeError: null function or function signature mismatch at do_icall`. Other ports shim that DllImport for non-AOT builds; AOT needs no shim. AOT requires `Configuration=Release` (`error : AOT is not supported in debug configuration`), so `-p:CkDebugLog=true` adds `DEBUG` to a Release build when the game's log lines are wanted. |
| `WasmBuildNative=true` + `NativeFileReference` ×4 | The single-threaded archives of `r58Playz/FNA-WASM-Build` (`ST-SDL3.a`, `ST-FNA3D.a`, `ST-libmojoshader.a`, `ST-FAudio.a`), renamed to their `DllImport` names. That project builds with Emscripten 3.1.56, the same version as the .NET 9 `wasm-tools` workload (.NET 8's is 3.1.34). |
| `NativeFileReference __Native.c` | FNA's `SDL3_FNAPlatform.RunPlatformMainLoop` already calls `emscripten_set_main_loop` in a browser, through `[DllImport("__Native")]`. The P/Invoke table generator only includes modules named by a `NativeFileReference`; without it the function is absent from `pinvoke-table.h`. The `unwind` page error right after `XnaGameClass LoadContent Done` is that call's `simulate_infinite_loop` throw, and it is expected. |
| `-sMIN_WEBGL_VERSION=2 -sMAX_WEBGL_VERSION=2 -sFULL_ES3` | FNA3D needs `glUnmapBuffer`, which Emscripten's `webgl2.c` returns from `emscripten_webgl2_get_proc_address` only under `FULL_ES3`. Without it: `OpenGL ES 3.0 support is required!` |
| `InvariantGlobalization`, `TrimMode=partial`, `DisableBuildCompression` | a smaller, simpler first page; compression is left to the server |

FNA's own `FNA.Core.csproj` (`net8.0`) builds for browser-wasm unchanged. Note that FNA-WASM-Build's `FNA3D.patch` adds `-pthread`
to FNA3D and MojoShader unconditionally, so `ST-FNA3D.a` is byte-identical to the threaded `FNA3D.a`. `wasm-ld` links it into
the single-threaded build silently, and it runs.

## 4. The walls, in order

| # | Symptom (verbatim) | Cause | Fix |
|---|---|---|---|
| 1 | `Module.preRun should exist because file support used it; did a pre-js delete it?` | `emcc --preload-file` registers a `preRun` while `Module` is still dotnet's factory; `dotnet.es6.pre.js` then replaces `Module`. `WasmFilesToIncludeInFileSystem` is ignored by `Microsoft.NET.Sdk.WebAssembly`. | The page writes Content into the FS itself from `content-manifest.json`, between `create()` and `runMain()`. |
| 2 | `RuntimeError: null function or function signature mismatch at do_icall` (last P/Invoke: `SDL_CreateWindow`) | the interpreter cannot call a `uint64` native signature | AOT |
| 3 | `error : AOT is not supported in debug configuration` | — | Release + `CkDebugLog` |
| 4 | `OpenGL ES 3.0 support is required!` | `glUnmapBuffer` only under `FULL_ES3` | `-sFULL_ES3` |
| 5 | `[MONO] mini-wasm.c:675` then `ExitStatus` | `g_error("pthread_getschedparam")`, reached from `Thread.CurrentThread.Priority = Lowest` in `Resources._LoadThread` | skip the priority under `BROWSER` |
| 6 | `IO_FileNotFound_FileName, /Content/Objects\FlyingCoin_v2.smo` | Windows `\` paths on a POSIX FS | page FS shim: `\` → `/` |
| 7 | `IO_FileNotFound_FileName, /Content/Objects\MeatBoy.smo` (the file is `meatboy.smo`) | case | page FS shim: case-insensitive match against the manifest |
| 8 | `exceptions-wasm.c:66 … not met` ×2,006 in 60 s, then `NullReferenceException`, black canvas | Running the level-generation thread bodies inline broke the game: the caller expected the thread to run *after* it returned. In addition, every throw after the main-loop hand-off asserts in Mono's wasm unwinder. | The thread bodies go to `Tools.BrowserBackgroundQueue`, which runs at the start of the next `Update`. Exception reporting does not walk stacks. Result: 0 throws after the hand-off. |
| 9 | Platforms invisible (hero, coins and hazards drawn); `texImage2D: invalid format` ×5 | BGRA upload (§5) | page shim |
| 10 | Tab freezes at the first demo level swap (~19 s on a GPU) | Mono 9 precise interpreter GC scan (§5) | `MONO_INTERPRETER_OPTIONS=-precise` |

Single-threading: the game starts two kinds of threads, level generation (`NormalGameData.Init`) and `Tools.EasyThread`.
Under `BROWSER` both queue their body on `Tools.BrowserBackgroundQueue`, and `XnaGameClass.Update` runs the queue first.
`GameType.KillThread` returns early instead of calling `Thread.Abort`. A level's generation (0.4–1 s) blocks the frame it runs in; that is the only visible cost.

## 5. The two page shims

**BGRA.** Chain: `White/Circle/Smooth/Transparent.dds` have masks `R=0xFF0000 G=0xFF00 B=0xFF A=0xFF000000` → FNA's
`Texture.ParseDDS` → `SurfaceFormat.ColorBgraEXT` → FNA3D OpenGL `glTexImage2D(…, GL_RGBA8, …, GL_BGRA, GL_UNSIGNED_BYTE, …)`.
WebGL 2 has no `GL_BGRA`, so the call fails with `INVALID_ENUM` and the texture stays incomplete (it samples black). Everything
drawn on `White`/`Smooth`, including the blocks, vanished against the black background, while the untextured box shader (hero, coins, hazards)
still drew. `main.js` wraps `texImage2D`/`texSubImage2D`: a `GL_BGRA`+`UNSIGNED_BYTE` call becomes `GL_RGBA` with B and R swapped
in a copy of the pixels. It also returns `null` for FNA3D's `getInternalformatParameter` probe of formats WebGL cannot render
(S3TC and their sRGB twins, `GL_ALPHA`, `R16/RG16/RGBA16`). That is the value WebGL returns for them anyway, minus the warning.
Rebuilding FNA3D to map BGRA on ES, or re-encoding the `.dds` files, would be narrower fixes and cost more.

**`-precise`.** A CDP pause on the frozen tab, symbolised with `-p:WasmEmitSymbolMap=true`, gave the same stack 3 times, 3 s apart:
`interp_mark_stack ← sgen_client_scan_thread_data ← pin_from_roots ← … ← GC.Collect ← Recycler.Empty ← … ← StringWorldGameData.SwapToLevel ← … ← SDL3_FNAPlatform.RunEmscriptenMainLoop`.
Removing the game's forced `GC.Collect` calls only moved the freeze to a natural nursery collection, so any collection
can hang. In dotnet/runtime v9.0.20 `interp.c`, the only part of `interp_mark_stack` gated by `INTERP_OPT_PRECISE_GC` (on by
default in .NET 9) is `interp_mark_no_ref_slots`: a walk of the thread's LMF chain. With that option off the freeze is
gone, so the non-terminating loop is in that walk. *Why* the chain does not terminate was not measured. The likely
candidate is that FNA's `emscripten_set_main_loop(…, simulate_infinite_loop=1)` unwinds out of `Main` without popping the LMF
entries. Mono reads `MONO_INTERPRETER_OPTIONS` at interpreter init, and the page sets `-precise` through `withEnvironmentVariable`.
A/B before making it the default: with it, 14 levels in 117 s; without it, a freeze at 19 s and 29 s. It does not freeze natively
(21 levels in 90 s with `BROWSER` defined), so the queue itself is correct.

## 6. The generator API

`CloudberryKingdom.GeneratorApi` (new file `Game/MainClass/GeneratorApi.cs`) turns the level generator and the computer player into a callable:

- **Tab**: build with `--api` or open the page with `?api=1`. The game loads Content, then idles on the game's own empty level
  instead of starting the ScreenSaver.
  ```js
  await cloudberry.ready();
  const doc = await cloudberry.generate({seed: 7, difficulty: 4, hero: 'Normal', length: 6700, geometry: 'Right', tileset: 'castle'});
  await cloudberry.timings()   // {generateMs, exportMs, replayMs} of the last call
  ```
  `generateText(args)` returns the document exactly as C# wrote it, for byte comparison.
- **Native**: `CloudberryKingdom --generate @args.json --out doc.json [--repeat N]` (Windows; on Linux `dotnet CloudberryKingdom.dll …`
  with `SDL_VIDEODRIVER=offscreen`, which gives a software GL context: the game will not construct without a graphics device).

**Arguments:** `seed` (int, default 1), `difficulty` (float, 2), `hero` (the `BobPhsx<Name>` class suffix, e.g. `Normal`, `Big`,
`Jetman`; resolved by reflection, default `Normal`), `length` (world units, 6700), `geometry` (`Right`/`Up`/`Down`/…, `Right`),
`tileset` (`cave`), `replay` (bool, run the replay check, true), `trace` (bool, emit the dense trace, true), `controlFromTick`
(int, a negative control: a third replay with the input neutralised from that tick). Unknown keys are refused.

**Determinism.** `LevelSeedData.Seed` is *not* the generation's seed: `StandardInit` draws it from `data.Rnd`, which is seeded
from `Tools.GlobalRnd`, and `DifficultyGroups` draws from `Tools.GlobalRnd` directly. The API re-seeds
`Tools.GlobalRnd = new Rand(seed)` for the call and restores it afterwards. Measured: 16 argument sets (seeds 1/7 × difficulty
0/2/4/6 × length 3000/6700), 5 repeats each, in one tab, in Windows native processes and in Linux native processes, gave
**one byte string per set across all three** (Mono AOT wasm, CoreCLR 8 x64, CoreCLR 9 x64). For a fixed `engine.build`, documents are byte-comparable.

**The replay check.** The game's own watch path cannot answer "does the computer reach the door". `Level.WatchComputer`
makes computer bobs immortal, `Bob.Die` returns early for them, and `Level.UpdateBobs` snaps a computer bob back onto the
recording whenever it drifts. The API adds a probe (`Level.ReplayProbe` / `ReplaySnapDisabled` / `ReplayRunPastEnd`, a counted
death in `Bob.Die`, `Door.BobInReach` factored out of `Door.Interact`) and replays twice from the recording's start state:
**`engine`** as the game does it (snaps counted), and **`inputsOnly`** with the snap disabled, so the recorded input alone drives the bob.
Both compare the position after every step with the recorded trace, count would-be deaths, continue past the recording on the
engine's continuation input, and stop when the final door's own reach test fires (or after `pieceLength + 120` steps).
For the Normal hero in all 16 sets, `inputsOnly` reproduces the recording exactly (max deviation 0.0, 0 snaps, 0 deaths) and reaches
the goal. The negative control discriminates: with the input neutralised from tick 30, 48 deaths and no goal.

**`ck-level/1`** (one trimmed real document, seed 1, difficulty 2, length 3000):
```json
{"format":"ck-level/1","args":{"seed":1,"difficulty":2,"hero":"Normal","length":3000,"geometry":"Right","tileset":"castle"},
 "engine":{"build":"<commit the page or binary was built from>","physicsHz":60,"units":"world (game px)"},
 "level":{"tileset":"castle","heroResolved":"BobPhsxNormal","seedDrawn":607892308,"bl":[-3500,-5789.596],"tr":[6500,0],"par":304},
 "pieces":[{"index":0,"startStep":0,"pieceLength":304,"bobs":1,"replay":[{"start":[50,-351.05566],"startVel":[0,0],"ticks":304,
   "input":[[0,0,0,0,0],[1,0,0,0,1],[8,0,0,0,0],[26,1,0,0,0],…],"trace":[[0,50,-354.00568,0,-2.95,0],[1,50,-359.90567,0,-5.9,0],…]}]}],
 "blocks":[{"kind":"NormalBlock","pos":[-450,-2521.0278],"shapes":[{"field":"MyBox","type":"box","bl":[-1350,-4500],"tr":[450,-542.05566]}],"extra":{"Active":true,"ExtraPadding":0,"Invert":false,"Moved":false}},
   {"kind":"MovingBlock","pos":[1598.9774,-410.39993],"shapes":[{"field":"MyBox","type":"box","bl":[1408.9774,-600.7999],"tr":[1788.9774,-219.99994]}],"extra":{"Active":true,"Displacement":[344,0],"MoveType":"Line","Offset":0,"Period":328}},…],
 "objects":[{"kind":"Door","pos":[50,-351.05566],"code":"Start of Level Connector","shapes":[],"extra":{…}},
   {"kind":"FlyingBlob","pos":[2324.7778,-619.99994],"shapes":[{"field":"Box","type":"box","bl":[2245.402,-611.2531],"tr":[2387.4187,-567.74347]},{"field":"Box2",…}],"extra":{"Period":230,"Offset":6,"Displacement":[172.88889,0],"MyMoveType":"Line",…}},…],
 "nonFiniteValues":0,"goal":{"startDoor":[50,-351.05566],"door":[3880,-485]},
 "replayCheck":{"engine":{"reachedGoal":true,"ticksToGoal":296,"goalWithinRecording":true,"ticksCompared":296,"maxDeviationFromTrace":0,"snaps":0,"deaths":0,…},
                "inputsOnly":{"reachedGoal":true,"ticksToGoal":296,"goalWithinRecording":true,"ticksCompared":296,"maxDeviationFromTrace":0,"snaps":0,"deaths":0,…}}}
```
- `pieces[i].replay[b]`: per piece, per bob (`HeroLevel` always makes 1 of each). `input` rows are `[tick, x, y, A, B]`,
  emitted when any component changes, so a row holds until the next one. `trace` rows are `[tick, x, y, vx, vy, onGround]`; tick 0
  is the start state, and `trace[t]` is the position after t physics steps.
- `blocks` / `objects` share one shape. `shapes` lists every `AABox` / `CircleBox` / `MovingLine` field in the object's class
  hierarchy, which covers circles and lines as well as boxes. `extra` holds every public `int/float/bool/Vector2/string/enum` field
  below `ObjectBase`, found by reflection: complete, and noisy (read `shapes` and a few `extra` keys such as `Period`, `Offset`, `Displacement`).
  Kinds are the runtime class names (`NormalBlock`, `MovingBlock`, `FireSpinner`, `Laser`, `FlyingBlob`, `Spike`, `Door`, …).
- `level.heroResolved`: `HeroLevel` changes some requests (e.g. Spaceship on `Up`/`Down` becomes `BobPhsxDouble`).
- JSON has no NaN/Infinity: those are written `null` and counted in `nonFiniteValues`.
- Errors return `{"format":"ck-level/1","error":"<Type>: <message>"}`.

Cost: the page is ready ≈ 3 s after navigation; one call (generate + both replays) is ≈ 120–590 ms in headless Chromium,
similar to native. Documents are 19–95 KB with the trace.

## 7. Patch reference

`patches/browser/` (applied after the upstream set; regenerate with `scripts/export_patches.sh`):

| Patch / file | Change |
|---|---|
| `Game-MainClass-CloudberryKingdom.cs.patch` | `LoadResources = false` |
| `Game-Engine-GameTools-Resources.cs.patch` | no music/sound enumeration in engine-only mode; no thread priority under `BROWSER` |
| `Game-Engine-Song-EzSong.cs.patch`, `…-EzSongWad.cs.patch`, `Game-Engine-Sound-EzSound.cs.patch`, `…-EzSoundWad.cs.patch` | silent songs and sounds |
| `Game-Engine-GameTools-Tools.cs.patch` | `BrowserBackgroundQueue`; `EasyThread` queues under `BROWSER`; `ExceptionStr` without `StackTrace` under `BROWSER` |
| `Game-Games-NormalGame.cs.patch` | the level-generation thread body queued under `BROWSER` |
| `Game-Games-GameType.cs.patch` | `KillThread` returns under `BROWSER` |
| `Game-MainClass-XnaGameClass.cs.patch` | `Update` runs the queue first under `BROWSER` |
| `Game-MainClass-MainClass.cs.patch` | API argument processing; a first-chance exception printer under `BROWSER` (first 40) |
| `Game-MainClass-InitialLoading.cs.patch` | API mode starts `GeneratorApi.OnLoaded` instead of the ScreenSaver |
| `Game-MainClass-DebugHelper_MakeTestLevel.cs.patch` | `MakeEmptyLevel` becomes `internal` and not DEBUG-only (the API idles on it) |
| `Game-Level-Level.cs.patch`, `Game-Objects-Bob-Bob.cs.patch`, `Game-Objects-Door-Door.cs.patch` | the replay probe (§6) |
| `Game-Game.Core.csproj.patch` | compiles `GeneratorApi.cs` natively too |
| `files/Game/Game.Browser.csproj`, `files/Game/MainClass/GeneratorApi.cs` | new files, entirely this fork's |

## 8. Known gaps

- *Why* Mono's LMF chain walk does not terminate is inferred, not measured. If the stale-LMF reading is right, the durable fix is an
  FNA-side `simulate_infinite_loop = 0` with a runtime that outlives `Main`.
- No threads: `WasmEnableThreads` would need OffscreenCanvas, COOP/COEP headers and the threaded archives.
- No input yet (keyboard control is the next planned change), no saves (`MyDocuments` is empty on wasm; persistence would need IDBFS/OPFS).
- The replay check does not hold for every hero: Bouncy diverges from input alone; Time/TimeShip count deaths with zero deviation
  (their obstacle clock follows the hero); some vertical geometries (Box/Invert/UpsideDown/FourWay on `Up`/`Down`) come out degenerate
  (`pieceLength` 6000). The API does not refuse them yet.
- `replayCheck.*.doorDistanceAtRecordingEnd` is wrong (measured from the origin) when the goal fires inside the recording.
- Obstacle shapes are the tick-0 state; motion is described by `extra` parameters, not a per-tick timeline.
