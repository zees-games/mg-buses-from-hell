# The client: bodies, camera, HUD, sound, effects, menus

Everything here is built only by `BfhClient`; a dedicated server draws and plays nothing. The client listens to its one world's signals, which a connected client's bridge re-emits from the server's events (see [netcode.md](netcode.md#what-crosses)), so nothing here knows whether it is offline or connected.

## Bodies

`bfh_figure.gd` is one of the family's animated people (dot-player-char's `DotHumanoidFigure`): six ordinary people for runners, chosen by face (or by player id) through the blocky kit's skin letters (`DotHumanoidLook.from_letter`, so every avatar document dresses the same person as before), and the uniform's colours (`DRIVER_ATLAS`, skin j) for a driver on foot, at the runner's 1.8 m hull. It animates from how far its node moves each frame (`auto_animate`), because the interpolator moves it and nothing here knows a speed.

**Who is drawn** is `BfhPlayer.present_body`: everybody except the player the camera belongs to (first person), a driver (drawn AS the bus: nothing moves a rider, so a body would stand where they sat down, which is also why `drawn_position` answers with the bus), and a runner who is out.

## Where a runner who is out looks

Out is out until the next round, so the part of the game a runner spends dead is most of a round on a bad one. `bfh_spectate.gd` is dot-spectate's `DotSpectatorManager` with this game's policy and this game's idea of where a bus's eyes are.

**The chain**: a death camera for a second from where they fell, looking at the bus; a freeze for two seconds from that bus's CAB (who got you, where they go next); then first person on somebody still up, sorted by key so "next" is stable. Left click next, right click back, space or middle button swaps eyes and a chase camera seven metres behind. `BfhHud.watching_line` says whose eyes; the crosshair goes.

**A bus's eyes are its cab**: `BfhSpectate.pose_of` answers with the bus, `CAB_EYE` over the cab roof (3.8 m up, 1.2 m forward), pitched down the road. A check about what a camera looks at must measure to the cab, not the hull's centre or origin; both were wrong once.

**The policy is the loosest in the family**, each line for a reason about this game:

- **Anybody may be watched, a bus included** (`force_camera 0`). Every player and bus is always relevant, so every client already has every position a camera could show; forbidding the bus protects nothing from a modified client and denies an honest one the most watchable thing on the server.
- **No delay**: a delay a client enforces over data it already has is theatre, and dot-spectate records delay history on the authority only, so a delayed mirror has no pose to draw.
- **Roaming is on** (G, `BfhBindings.ROAM`; decided family-wide 2026-10-21): the position argument above applies to it too, a modified client has every position whatever the camera shows. `mp_freeroam 0` switches it off, `mp_forcecamera` 1 or 2 restricts the camera and switches it off with it (the restriction wins silently), and `mp_freeroam_speed` is its speed. The module binds dot-spectate's `DotSpectatorRules` cvars REPLICATED and the client follows them. The key is `BfhSpectate.ASK_ROAM`, the fourth value of the WATCH ask's two bits; the server toggles (`toggle_roam`) and a refusal returns as a notice; the view comes back as ROAMING with no target (a mirror adopts it like any mode). The client flies a `DotSpectatorFreeCam` per frame in 3D (`BfhClient._drive_free_camera`; WASD, Space / Ctrl, Shift, Alt, mouse), and a roamer's movement command is zeroed online (`_physics_process`) and offline (`BfhPlayer.input_off`), so the keys that fly the camera do not walk the body. Clicks and Space mean nothing while roaming.
- The living do not watch, and a driver cannot be out.

The server decides and the client draws: the view is owner-only state, and `BfhClient.present_spectator_camera` (static, driven by `headless_net`) computes the camera from positions the frame is already drawing, so it is as smooth as the picture.

## The HUD and the admin overlays

`bfh_hud.gd`: the clock, health, runners up and crates left, and a dot. **Health and the clock are dot-ui's glance pieces** (`DotVitals` bottom left, under the chat box, which starts 120 pixels off the bottom; `DotScoreStrip` with the clock alone and the status line under it, red for the last ten seconds), coloured by `BfhHud.piece_theme()` (a warm dark plate, the sand as highlight), so the game reads like the rest of the family and the numbers keep the outline and plate this pale floor needs. Naming them makes the pack need a client shell with dot-ui API level 4; the derived `requires.json` asks for it and `headless_run` checks it. **A `CanvasLayer` does not lay out its children**: anchors on a `Label` parented straight to one resolve against nothing, and all four labels once landed on top of each other in a corner. Put a full-rect `Control` between them.

`BfhHud.blind_overlay` fades a near-black rect in **under** the four numbers, which stay with a "blinded by an admin" line, so it reads as something done to the player rather than a client that stopped drawing. The beacon is dot-fx's `DotFxBeacon`, built by `BfhPlayer.present_beacon`: a ring with a ripple once a second, a column drawn with no depth test (not on your own player), and a positional ping synthesised by dot-fx. Boarding or leaving a bus calls its `resize` (API level 4), which keeps the phase. A driver's beacon is round their bus (`BEACON_BUS_RING`): 5.2 m across so it circles a nine-metre hull, the column starting above the roof.

## Sound

`bfh_sounds.gd` is the document: ids positional for anything that happens somewhere (engine, horn, hammer swing and hit, crate shove and break, a runner bumped and flattened, a barrel) and flat on the interface bus for the round's cues and the interface's. **Won and lost are two sounds**: in an asymmetric game "the round ended" is good news for two people and bad news for six. `sound_recipes()` names the dot-audio synthesiser voice standing in for each, and every path is under `BfhPaths.root()`, because a pack's `res://audio/…` would otherwise resolve against the host and play another game's file. `sound_dir(root)` takes a root so the suite can ask that with a mount prefix; built in, it is a tautology.

- **Hearing is the one sense a tank does not block**, which is why the bus's sound matters here more than anywhere. **The engine is the one sound nobody sends**, and it is a pulse whose RATE rises with speed (2.2 to 11 a second), measured frame to frame from the drawn position (a mirrored bus is a frozen body whose `linear_velocity` is zero). A pulse rather than a looping pitch, because the rate says the speed more clearly through a tank. Only a DRIVEN bus has an engine.
- **The horn** is a driver's swing button, rate-limited on the authority (0.8 s; 6 s for a bot, which only sounds it at a runner squarely ahead within 22 m), because a held button would otherwise be a server-wide siren.
- **The swing sound comes from the server, a round trip late, on purpose**: it says the server swung; a predicted one would sound for a swing the server may refuse on its cooldown.
- No `tools/audio_probe.sh` here yet, so nothing has checked a speaker actually moving; headless has no sound device.

## Effects

`bfh_fx.gd` listens to the world's `barrel_exploded` and hands dot-fx an id and a place. `fx/bfh_blast.tscn` is built in code (no particle art): a fireball, a translucent disc and a ring on the sand out to **exactly the blast's reach** (what a runner reads: was I inside it), a flash and smoke. `configure(radius)` sizes it; unsized it is one metre, visibly wrong. **Alpha-blended, not additive**: additive over the bright sand saturated to white. The ring sits `GROUND_BELOW` the reported centre, because the server reports the blast at the barrel's middle. `BfhFx.setup` WARNs on `missing_scenes()`, since dot-fx logs a missing scene at DEBUG.

## Scoreboard, settings and the menu

**The scoreboard is two tables**, because the sides are not two teams of the same thing: drivers ("driving" / "on foot") and runners ("up" / "out", the living first). Held on Tab, and up on its own from `round_over` to the next `round_began`, naming the round just played. dot-match here scores rounds per side (`DotMatch.rounds_won` by team id), and no per-player column, for the reason in [services.md](services.md#a-players-numbers-and-what-they-earn). A `DotTableView` inside a container needs an explicit `custom_minimum_size` or it is laid out zero pixels tall.

`bfh_settings.gd` is dot-menu's `DotMenuSettings` with this game's schema; Escape opens it over the bowl. Every setting is read by something: `sensitivity` into every sampler's look tunables, `field_of_view` into the camera, the volumes into dot-audio's mixer. **A loaded setting has not changed**, so `apply_all()` runs after load and every `bind_*` applies the current value as it binds. Scopes are the family's: `sensitivity` is ACCOUNT, at the family's 0.022 degrees per unit; `field_of_view` is SERVER_CLAMPED. Walking is suspended while the cover is up, the menu is open or a line is typed, and the menu neither pauses (a networked round does not stop for one player's volume) nor manages the pointer itself.

**The platform layer is dot-game's `DotGameClient`**, a child `BfhClient` adds first in `_ready` (`platform`): the loading cover (the gate, held on `map` by the bowl and released when the first layout is in; `spawned_fn` is the local player, and the gate also waits for a current camera), the settings and Escape menu, the console, Tab (the menu holds its board on `bfh_scoreboard`; `BfhScoreboard` only dresses the board and raises it between rounds), M (the bowl list), the pointer (captured on a click, freed by any menu) and the browser's filesystem flush. `input_blocked_changed` suspends both samplers. `tools/shot.sh 1 cover.png --view=cover` renders the cover.

## Lighting and the grid

- **A scene with no light and no environment is not dark, it is flat**: every surface comes back its own albedo, and the depth a player judges distance by is gone. The bowl has a sun and a sky.
- **`uv1_triplanar` with no texture under it does nothing.** `bfh_textures.gd` generates the metre grid, because the only thing a player judges a bus's speed by is how fast a pattern of known size goes past.
- **The look is the family's sunny pastel one** (game-arena's built-in maps): `BfhArena`'s palette constants tint the grid per kind of thing (warm sand, a peach-pink wall, a lavender ledge and ramp, sky-blue tanks with a deeper band, mint pillars with a darker cap), so a place can be called out; Kenney's crates, barrels and buses keep their own colours as the saturated things on screen. A repaint is those constants, never the geometry.
- **The light is a dot-lighting document**, `BfhArena.DAYLIGHT`: a warm lowish sun from the side (long crate shadows are how a runner reads cover), a blue sky continued under the horizon, a pale cool fill, haze from 60 m that never hides the far wall, filmic and glow. Shadows stay on in the browser (a few hundred boxes). The old hand-built environment fogged the sky itself, so the whole sky rendered flat beige.
- Lighting is tuned under `gl_compatibility`, the renderer players get (see [delivery.md](delivery.md)): `BfhArena.light_profile()` is dot-lighting's `painted()` (API 3), which matches its light to the renderer, lowers the exposure, grades and adds a shadowless fill. Check Forward+ too (`GODOT=<a wrapper adding --rendering-method forward_plus> tools/shot.sh`).

## First and third person

F5 (`BfhBindings.VIEW`) switches views under the server's `mp_forceview` (dot-player-controller's `DotPlayerViewRules`, bound REPLICATED by the module and followed through the link). Third person sweeps the camera back from the eye (`THIRD_PERSON_OFFSET`) through a dot-core `DotCameraProbe` on layer one, so the rim, a stack or a bus stops it short; driving, the sweep starts `BUS_PIVOT_RISE` over the seated eye, above the roof, so the bus being driven is not what stops it, and goes further back (`THIRD_PERSON_BUS_OFFSET`). `present_frame`'s `own_seen` draws your own runner then. A `DotCameraFade` on the camera is handed the other players and hides one at the lens. This game binds no `mp_solidplayers`: runners and buses share layer one, and a hull on it would be something every bus hits. `tools/camera_check.sh [--render]` flies both cameras round the rim, stacks, colonnade, ledge and ramp (armed), checks the rule, and draws both views.

