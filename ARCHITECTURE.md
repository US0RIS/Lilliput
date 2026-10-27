# Lilliput architecture

Three layers with one-way data flow: **observation** (what windows exist and where) → **coordination** (which windows get a site, on which display, what is in front of what) → **simulation and rendering** (sites, crew, scaffolding). The simulation never talks to the window server; the Demo drives it with fake windows through the same API.

```
WindowTracker ──events──▶ SimulationCoordinator ──site ops──▶ ConstructionScene (one per display)
  │  CGWindowList (truth)        │ site limit, display routing,      └─ ConstructionSite (one per window)
  │  AXObserver (when to look)   │ occlusion from real stacking           ├─ ScaffoldGenerator → ScaffoldElementNode
  └─ WindowRegistry (diffing)    └─ OverlayManager (windows/views)        ├─ Worker + WorkerAnimator
                                                                          ├─ ConstructionDirector (extension)
DemoController ──same site ops──▶ ConstructionScene (demo)                ├─ EventScheduler (extension)
                                                                          └─ ParticleSystem, springs, pendulums
```

## Source map

| Folder | Files | Role |
|---|---|---|
| `App` | `LilliputApp`, `AppDelegate`, `StatusMenuController` | Entry point (agent app, no Dock icon), lifecycle, menu-bar item |
| `Permissions` | `PermissionManager`, `OnboardingView` | Accessibility trust state, one-time prompt, onboarding window |
| `Settings` | `SettingsTypes`, `SettingsStore`, `SettingsView` | Persisted preferences, `SimSettings` snapshot, SwiftUI settings, launch at login (`SMAppService`) |
| `Tracking` | `WindowTracker`, `WindowRegistry`, `WindowModels` | Window discovery/observation, lifecycle diffing, coordinate conversion |
| `Overlay` | `OverlayManager`, `SimulationCoordinator` | Per-display transparent windows; glue between tracking and scenes |
| `Simulation` | `ConstructionScene`, `ConstructionSite`, `ConstructionDirector`, `EventScheduler`, `ScaffoldGenerator`, `ScaffoldNodes`, `Navigation`, `Worker`, `WorkerAnimator`, `PhysicsController`, `ParticleSystem`, `Occlusion`, `RNG` | The miniature world |
| `Art` | `PixelCanvas`, `Palette`, `WorkerArt`, `PropArt`, `TextureCache` | All pixel art, authored in code, cached as nearest-filtered textures |
| `Audio` | `SoundEngine` | Synthesized, rate-limited, opt-in sounds |
| `Demo` | `DemoController`, `DemoWindowController` | Demo Mode window with fake windows |

## Window tracking

**Source of truth: `CGWindowListCopyWindowInfo`** (`.optionOnScreenOnly`, `.excludeDesktopElements`). It returns every on-screen window front to back with its window number (`kCGWindowNumber`, stable for the window's lifetime), owner PID, layer, alpha and bounds. Titles (`kCGWindowName`) would require Screen Recording; Lilliput never reads them, so no such permission is needed. Only layer-0 windows are considered.

**When to look: `AXObserver`.** One observer per running app (created on launch, removed on terminate) registered on the application element for `AXWindowCreated`, `AXWindowMoved`, `AXWindowResized`, `AXWindowMiniaturized`, `AXWindowDeminiaturized`, `AXFocusedWindowChanged`, `AXApplicationHidden/Shown` and `AXUIElementDestroyed`. Registration failures are tolerated: not every app supports every notification. The C callback hops to the tracker on the main run loop.

**Cadence.**
- *Active mode* (60 Hz timer in `.common` run-loop mode) starts on move/resize notifications and on global left-mouse down/drag/up (`NSEvent.addGlobalMonitorForEvents`), and ends 0.3–0.4 s after the last activity. This gives smooth following for apps whose move notifications only arrive at the end of a drag.
- *Idle mode*: one reconciliation every 0.6 s (with timer tolerance) as the fallback for anything notifications miss. Never a per-frame enumeration while idle.
- Other notifications schedule a coalesced reconciliation 50 ms later.

**Eligibility** (conservative): layer 0, alpha > 0.05, at least 180×120 pt, not owned by Lilliput, not a known system agent (Dock, Window Manager, Control Center, Notification Center, Spotlight, screenshot UI…), not in the user's exclusion list, not covering a whole display (full-screen apps) unless "Show over full-screen apps" is on. Each new window is then matched once to its `AXUIElement` (same PID, frame within 3 pt) and accepted only for `AXWindow`/`AXStandardWindow`, or `AXDialog` at least 300×200. Windows with no AX match after five attempts are accepted only if clearly app-sized (≥400×250), which covers apps that expose no AX windows. All AX calls use a 0.2–0.25 s messaging timeout so a hung app can't stall Lilliput.

**`WindowRegistry`** (pure, unit tested) turns successive lists into events:
- new window → *pending* until its frame has been unchanged for 0.25 s and it is at least 0.2 s old (opening animations settle first) → `opened`
- frame change > 0.5 pt → `changed`
- gone from the on-screen list: if `CGWindowListCopyWindowInfo(.optionIncludingWindow, id)` still finds it → `hidden` (minimized, app hidden, other Space), else → `closed`
- hidden and back on screen → `restored`; hidden and no longer existing → `closed` (checked on idle passes only)

Space switches reconcile with animations off, so sites on the departing Space vanish instantly and the arriving Space's sites appear already built.

## Coordinates

Three spaces:
1. **Core Graphics global**: origin top-left of the primary display, y down (window list, AX positions).
2. **AppKit global**: origin bottom-left of the primary display, y up (`NSScreen.frame`). Conversion: `y_appkit = primaryHeight − (y_cg + height)` (`ScreenGeometry.appKitRect`), where the primary display is the screen whose frame origin is `(0,0)`.
3. **Scene**: each display's SpriteKit scene is the size of that display with origin at its bottom-left, so `scene = appkit − display.frame.origin`.

Inside a site, everything is in **art pixels** relative to the window's bottom-left corner. The site's root node is placed at the window origin (snapped to the display's device-pixel grid via `backingScaleFactor`) and scaled by the worker-size pixel scale (1.5 / 1.75 / 2.0 pt per art pixel). Workers, planks, poles and props all share that grid, which keeps the art crisp and consistent. A window belongs to the display that contains the middle of its bottom edge (where most scaffolding is); when that changes mid-drag, the site is detached from one scene and attached to the other without restarting. Displays with negative coordinates and mixed scale factors are covered by unit tests.

## Overlays

`OverlayManager` creates one `OverlayWindow` per `NSScreen`:
- borderless `NSWindow`, `isOpaque = false`, clear background, no shadow
- `ignoresMouseEvents = true`: every click, drag, scroll and resize goes to the window underneath
- `canBecomeKey` / `canBecomeMain` return false, so it never takes focus; the app is `LSUIElement`, so it is absent from the Dock and Cmd-Tab
- level just below the status bar (above normal and floating windows, below menus and popovers)
- collection behaviour `.canJoinAllSpaces`, `.stationary`, `.ignoresCycle`, plus `.fullScreenAuxiliary` only when the user allows effects over full-screen apps

Each window hosts a transparent `SKView` (`allowsTransparency`) presenting a `ConstructionScene`. The scene reports its activity: **empty** pauses the view (zero rendering), **idle** runs at 20–30 fps depending on intensity, **busy** (construction, teardown, pack/rebuild, motion, resize, particles in flight) runs at 60 fps. Display changes (`didChangeScreenParametersNotification`) rebuild the overlays and re-add live windows without animation. Sleep stops the tracker; wake starts it fresh. Disabling Lilliput or quitting stops the tracker (observers, timers, the mouse monitor) and closes every overlay window.

## Occlusion and clutter

The coordinator computes occlusion from the real front-to-back order (`Occlusion.compute`). For each site it passes the rects of windows in front of it, in scene coordinates; for tracked front windows the rect is expanded to include the strip below and beside the window where that window's own crew works. Each frame (every other frame for scaffold parts) the site hides any worker, scaffold element or prop whose centre falls inside one of those rects. If less than 30% of the site's working area is visible (sampled along the bottom edge and lower sides), the whole site fades out and its crew logic is suspended until it is uncovered. At most *N* sites (default 6, frontmost first) are live; windows beyond the limit are packed away and rebuilt quickly if they move forward again.

## Simulation

**`ScaffoldGenerator`** (pure, unit tested) produces a `ScaffoldLayout` from the window size in art pixels, density, and the screen's visible bounds:
- a **deck** under the bottom edge (planks at y −2…0, truss below, clipped above the Dock/screen edge), split into 1–20 bays of ~18 px; workers stand on y = 0
- up to two **towers** outside the left/right edges (never over content or the traffic lights), 1–4 levels of 16 px depending on density and window height, each with poles, X-bracing, platform, top guard rail and a ladder per level; towers that would leave the screen are dropped
- optional **crane** on a tower top (busy, or wide windows on normal) and a **pulley** on the other tower
- prop positions (sign, plank stack, toolbox, cones)
- an ordered element list with prerequisites (a tower level needs the ladder below it) and a reachable work spot for each, plus walkable **surfaces** (deck and platforms) for navigation

During a live resize the topology (bay and level counts) is locked and existing nodes are re-positioned, so nothing is rebuilt per frame. When the resize settles (0.35 s quiet), the layout is regenerated: new elements are built by workers who fetch a plank from the stack; removed ones collapse with dust.

**`ScaffoldElementNode`** draws each element from 1-px colour sprites and pixel textures (planks and ladders are sub-rects of single strip textures). Child sprites are created once and reconfigured on layout changes. Build and removal animations scale around each element's own pivot.

**`Worker`** is a sprite plus a queue of steps (`walk`, `climb`, `anim`, `face`, `emote`, `hop`, `fade`, `carry`, `waitUntil`, `call`). Walking and climbing frames advance with distance travelled, so feet don't slide. Reactions (brace, hang, stumble) override animation and pause the queue without discarding it, so a worker resumes what it was doing when a window stops moving. `Navigation` plans paths over the deck and tower chains (down one tower, across the deck, up the other).

**`ConstructionDirector`** (an extension of `ConstructionSite`) runs the phases:
- **constructing**: the crew fades in at a staging point beyond the nearest deck end and jogs in carrying the sign, planks and toolbox; the sign is planted, the stack and toolbox set down, then workers take elements whose prerequisites are built, preferring nearby ones, and group adjacent deck bays. Hammer time per element is scaled to land the build in about 4–5 s, with a safety net that finishes anything left after ~7 s.
- **active**: idle choices weighted by personality (diligence, laziness, curiosity), with cooldowns and pacing from the intensity setting: hammer, inspect a blueprint, carry materials, climb, rest, tighten bolts, signal the crane, wander, look around.
- **tearingDown** (window closed, frozen at its last frame): workers come down, elements are removed top-down over ~1.5 s, props are packed, and the crew walks off with toolbox and sign. About 2.5–3.5 s total, then the site is destroyed.
- **packing / packed / rebuilding** (minimize, hide, other Space, demotion): elements collapse and workers vanish in a puff in under a second; on return the crew pops back and rebuilds left to right in ~1.3 s.

**`EventScheduler`** (extension) fires an occasional micro-event every ~22–48 s (scaled by intensity) when the site is idle, visible and not moving: two-person long plank, dropped hammer, crane lift with a signaller, nap and wake-up, knocked-over stack, supervisor inspection (one at a time across a display, at most every 75 s), blueprint disagreement. Completion celebrations, the tower flag and resize near-falls are contextual.

**Motion physics**: `MotionTracker` estimates window velocity and acceleration from frame deltas. Props ride damped springs driven by −acceleration; crane hooks and the pulley bucket are pendulums driven by horizontal acceleration. Movement above 45 pt/s makes the crew brace; very fast flings make someone on a tower hang on or someone on the deck stumble; stopping after a fast move kicks up dust.

**Determinism and budgets**: each site's RNG is seeded from its window number. Particles come from a fixed per-site pool of 36 sprites. Crew per site is capped by density and the user limit. Bays are capped at 20 and tower levels at 4. Texture caches are fixed or bounded. Observers and timers are removed on stop.

## Implementation status

**Implemented and exercised in CI on a real macOS runner (Xcode 16.4, macOS 15):**
- The app compiles as a universal (arm64 + x86_64) Release build, ad-hoc signed, `LSUIElement = true`.
- 32+ unit tests pass: scaffold layout (contiguous bays, towers outside the window, off-screen clipping, density scaling, locked topology, prerequisite ordering), navigation, registry lifecycle (stabilisation, move, minimize/restore, close, stacking), coordinate conversion including negative-origin displays, occlusion, springs, pendulums, RNG, and every sprite pose.
- Smoke launch: the app starts, shows the menu-bar icon, opens the onboarding window (Accessibility not granted on CI) and Demo Mode, and runs Demo autoplay (open, move, fling, resize, focus, minimize/restore, close, special events) for ~70 s without crashing. Screenshots from the run are uploaded with every build.

**Implemented but not verifiable in CI** (needs a logged-in Mac with Accessibility granted; CI runners cannot grant it):
- Real window observation: Finder/Safari construction, following drags and resizes, minimize/close behaviour, multi-monitor routing, Space switching, sleep/wake, full-screen handling, launch at login. The code paths are the same site API that Demo Mode drives, and the window-list/registry logic is unit tested, but end-to-end behaviour with real windows has not been observed by the author. The manual test list below covers it.

**Known limitations**
- Occlusion is per-element (centre-point test), not per-pixel: a scaffold piece half-covered by a front window is either drawn whole or hidden.
- Windows of apps that expose no Accessibility windows are accepted only if they are at least 400×250 pt.
- Ad-hoc signing means macOS asks for Accessibility again after each new build.
- Mission Control and Exposé may briefly pack and rebuild sites, because the window server reports windows as moved or hidden during the animation.
- Sounds are simple synthesized clicks.

## Manual test checklist (real windows)

1. Launch → hard-hat icon in the menu bar, no Dock icon, onboarding window if not trusted.
2. Menu → Demo Construction… works before granting access.
3. Grant Accessibility → onboarding closes by itself; existing windows get crews (staggered).
4. Open a Finder window (⌘N in Finder) → crew arrives, sign, stack, deck bays, towers, ladders over ~4–5 s.
5. Open Safari → its own independent site.
6. Drag Safari slowly → scaffolding stays glued to it, crew braces; fling it fast → someone hangs on or stumbles; release → dust, crew resumes.
7. Resize Finder → structure stretches during the drag, one worker wobbles, and after release bays/levels are added (carried in) or removed.
8. Close Safari → teardown at its last position, crew leaves; nothing remains.
9. Minimize a window → quick pack in under a second; restore from the Dock → quick rebuild.
10. Click through the overlay anywhere: window controls, text fields, scrolling, resize handles, and the desktop all behave normally.
11. Move a window to a second display → the site follows and workers sit on its edge.
12. Change density / size / intensity in the menu → live sites change immediately.
13. Disable Lilliput → all overlays gone; enable → crews return.
14. Quit → no overlay windows remain (check with Mission Control).
15. Leave it running for an hour with windows opening and closing → memory in Activity Monitor stays flat (CI shows ~62 MB RSS during Demo autoplay).
