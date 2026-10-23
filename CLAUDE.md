# mg-buses-from-hell

Two people drive buses at everybody else in a walled sand bowl. Everybody else has a hammer that cannot hurt them: it breaks and shoves crates, so the only thing either side can change is the shape of the bowl between them. The family's first asymmetric game, the first whose module and services subclass dot-game, and the first to vendor art, so its pack-delivery reasoning is referenced family-wide.

Read the family [CLAUDE.md](../../CLAUDE.md) first; this file is only what is specific to this game. **The detail is in [docs/](docs/README.md)**: open the file for what you are touching.

## Read before

| Read | Before |
| --- | --- |
| [docs/README.md](docs/README.md) | the index |
| [docs/design.md](docs/design.md) | changing a rule of the game, the sides, the bus's damage, the bowl vote, or why something is deliberately absent |
| [docs/map.md](docs/map.md) | touching `bfh_arena.gd`: any obstacle, lane, radius, the scaffold, the ramp, the scatter, a climb |
| [docs/bots.md](docs/bots.md) | the autopilot, `steer_around`, the stuck rule, the ramp turn, bot knobs, route bots |
| [docs/netcode.md](docs/netcode.md) | `game/net/`, the module, what is predicted, anything sent or replicated |
| [docs/services.md](docs/services.md) | chat, voice, moderation tools, stats and awards, identity, the addon manifest |
| [docs/client.md](docs/client.md) | bodies, the spectator camera, HUD, sound, effects, scoreboard, settings, lighting |
| [docs/delivery.md](docs/delivery.md) | any `res://` path, art, a new script, project settings: what breaks in a delivered pack |
| [docs/testing.md](docs/testing.md) | adding a check, believing a green run, rendering |
| [docs/history.md](docs/history.md) | a bug that "cannot be happening"; what this game found and how it looked |

## Layout

| Path | What |
| --- | --- |
| `game/bfh_game.gd` | the simulation: rounds, sides, props, buses, damage, the autopilot. Headless |
| `game/bfh_arena.gd`, `bfh_reach.gd`, `bfh_textures.gd`, `bfh_bowls.gd`, `bfh_districts.gd` | the bowl in code and its one obstacle description; what a runner can reach; the generated metre grid; the bowls (radii) and the three town districts on the players' ballot |
| `game/bfh_config.gd`, `bfh_content.gd`, `bfh_paths.gd` | every setting (metres and seconds, layered like every DotConfig); prop and vehicle catalogues; `rebase` for pack delivery |
| `game/bfh_player.gd`, `bfh_hammer.gd` | one person (controller, health, hammer, riding a crate); the only weapon |
| `game/bfh_module.gd`, `bfh_server.gd`, `bfh_services.gd`, `bfh_vote.gd` | the dot-server module over `DotGameModule`, the game scene, chat/voice/moderation over `DotGameServices`, the bowl vote over dot-vote |
| `game/net/` | the wire: codec, messages, link, net behaviours, and `bfh_net_bridge.gd`, the only file naming both halves |
| `game/bfh_client.gd`, `bfh_client_chat.gd`, `bfh_hud.gd`, `bfh_figure.gd`, `bfh_spectate.gd`, `bfh_audio.gd`, `bfh_sounds.gd`, `bfh_fx.gd`, `bfh_scoreboard.gd`, `bfh_settings.gd`, `bfh_avatars.gd`, `bfh.tscn` | the client: never built by a dedicated server |
| `game/bfh_stats.gd`, `bfh_awards.gd`, `bfh_progress.gd` | per-player numbers and achievements, authority only |
| `props/` | crate, barrel and bus scenes, `bfh_prop_body.gd`, `bfh_bus.gd`, and `bfh_art.gd` (the atlas repair for delivered packs) |
| `fx/` | the barrel's blast, built in code |
| `assets/kenney/` | vendored CC0 models and atlases, one folder per kit (see its README) |
| `assets/models/`, `art-src/` | our own models, each a modified CC0 base: the bus is Kenney's garbage truck rebuilt by `art-src/bus/build.py` (wheels untouched, bounds held; `art-src/.gdignore` stops Godot importing the script and renders); credits in `assets/models/CREDITS.md` |
| `scenes/bfh_server.tscn`, `game.yml` | what a deployed server instantiates; the descriptor in the pack |
| `examples/` | `headless_mapcfg`, `headless_run`, `headless_net`, `headless_workshop`, `dedicated` |
| `tools/` | `shot.sh` / `shot.gd` / `net_shot.gd`: render a frame, and the network jitter and prediction probes; `drive_shot.sh`: a person driving a bus, from above, as a contact sheet; `soak.tscn` (`./game.sh soak [bowl] [min]`, [soak](docs/soak.md)) |

## Running and testing

- `./game.sh` plays offline; `./game.sh online` runs a local server and browser client; `./game.sh test` parses everything and runs the four suites; `./game.sh test <suite>` runs one; `./game.sh shot` renders. Addon links come from `.gitignore` through dot-bootstrap.
- `headless_run -- --only=<method>` runs one section. [testing](docs/testing.md)
- After touching a camera or the view key: `tools/camera_check.sh` (cameras round the bowl, armed; `--render` for both views). [client](docs/client.md#first-and-third-person)
- **Render after any change to what is drawn** (`tools/shot.sh`, flags per feature). Four bugs here were only visible in a picture. [testing](docs/testing.md#renders-what-no-assertion-reaches)
- **Runners step and the bowl has wind** (dot-audio's stock, `BfhAudio`); drivers make the engine instead. Levels are measured with `addons/dot_audio/tools/loudness.sh` (−17 LUFS band, `loudness_trim_db`); stock ids have files, so the suite's stand-in checks skip them.
- **The loopback suites cannot see delivery.** After touching paths, art, scripts' types or project settings, pack it and join with a real client. [testing](docs/testing.md#the-deployment-is-the-only-test-of-this)

## Rules

- A dead body falls as dot-player-char's ragdoll: the server picks the fall (`BfhGame.decide_death`, on `player.death`; a bus or a barrel always throws it), it rides DEATH last and optional, and the client copies it from the figure it draws (`BfhClient._fall`, from the world's `player_died` in both halves). The `sv_ragdoll*` cvars are bound in the module, REPLICATED, and followed by the client. Sounds in a pack are under its root except an addon's own (`res://addons/`). See dot-player-char's [docs/ragdolls.md](../dot-player-char/docs/ragdolls.md).
**Delivery** ([delivery](docs/delivery.md))
- **Every key is a `BfhBindings` row read through its action** (the board's Tab and the spectator's jump fall back to the keycode only with no table, for the suites); H is help (dot-menu's stock key; `BfhSettings._fill_help` writes the rules), so no row may default to H. `headless_run` checks it and the Escape menu's Help and Leave.
- **M is the bowl list** (dot-menu's map menu): `BfhGame.bowl_rows()` and `change_bowl_now()` (the next bowl plus dot-match's `begin_round_now`) serve both solo and the server, where dot-vote's map menu lets the owner's `sv_map_menu_flag` change it now and gives anybody else a vote. No row may default to M; `headless_run` and `dedicated` check it. **A subscribed Workshop map is a bowl document** (`{"radius": m}`, `accepts` in `provides.json`): solo lists it as `Name [Pack]` and plays it, online lists none, the game's own ids win. [not-yet](docs/not-yet.md)
- No `class_name` anywhere in this repository; scripts are reached by relative `preload`. `dot-server-deploy/tools/check.sh` refuses one.
- Every `res://` path of this game's own goes through `BfhPaths.rebase()` **where it is defined** (`static var X := BfhPaths.rebase(...)`), never a bare `const`. `headless_run` fails on a bare one.
- `rebase` must stay idempotent: exported paths in a `.tscn` arrive already rewritten. Test the mounted case through `rebase_onto`, never `rebase` built in (a tautology).
- Kenney art: each kit in its own folder, atlas beside the GLB at the path it names, `bfh_art.gd` paints only materials with no texture. Kenney models face +Z; this family's forward is -Z.
- **A round the buses win ends on its last moment** (`BfhKillcam`, `game/bfh_killcam.gd`): every drawn frame (bodies and ridden buses) goes into dot-replay's `DotKillcamBuffer`, a runner's death is noted, and `round_over` replays it from the driver's cab (a blast from the runner's eyes) before dot-ui's `DotWinnerReveal` (the winning side's first three) and then the Tab board (`BfhScoreboard.hold_after_round` keeps it down until `release_after_round`). `mp_killcam_time` (REPLICATED, 7, 0 off) is added to the intermission on the server (`BfhGame.apply_intermission`, not when the intermission is 0, as in the suites); `reduce_motion` (General, Comfort) shows the reveal's last frame at once. `headless_run` forbids a `requires.floor.json`; the floor is derived. `tools/shot.sh 2 kill.png --view=killcam` (7.5 for the reveal) renders both.
- Gravity is `BfhConfig.gravity`, written onto the world's own physics space; the project renders with `gl_compatibility`, and lighting is tuned under it. Neither project setting travels in a pack.
- `project.godot` carries no comments: the editor drops them, and any key left at its default, the first time it saves the file, so the reasons for its settings live here (the line above; `gl_compatibility` was set after a delivered client showed the bowl blown out to white under it while it looked like sand under Forward+). Texture imports keep `detect_3d/compress_to=0` (`[importer_defaults]` starts new ones that way) so the editor never re-imports one VRAM-compressed on a first open.
- Colour is `BfhArena`'s palette constants over the metre grid, and the light is `BfhArena.DAYLIGHT` (dot-lighting), turned down under Compatibility. [client](docs/client.md#lighting-and-the-grid)
- Spell types explicitly in client scripts where `:=` would infer from a host class; inference fails inside a mount.

**Netcode** ([netcode](docs/netcode.md))
- Only a runner's own feet are predicted. Props and buses are server-authoritative rigid bodies; a driver's keys go round trip, by dot-vehicle's decision.
- Event, request and chat kinds go out in fixed fields (`KIND_BITS`, `CHAT_KIND_BITS`) that the writer masks without a word, so a kind past the field aliases a smaller one; `fits()` on each and headless_net's wire section check every enum fits. Widen the field, never reuse a number.
- The local mirror is owned through `_mirror_owner(session_id)`; owner 0 for it means nothing is predicted and every position check still passes.
- A client world re-emits the server's signals (`noise`, `round_began`, `round_over`, `player_died`, `barrel_exploded`, `sides_swapped`); client-side code listens to its world and never asks which half it is in.
- Owner-only state for anything that would tell the other side something: `net_blind`, `net_watch`. A spectate click names next/back/view, never a player.
- **A runner who is out can free-roam (G, `BfhSpectate.ASK_ROAM`) by default**: `mp_freeroam`, `mp_forcecamera` and `mp_freeroam_speed` are dot-spectate's rules, bound REPLICATED by the module and followed by the client; the server holds the mode, the client flies a `DotSpectatorFreeCam`, and a roamer's command is zeroed online and offline. [client](docs/client.md)
- **A READY before the player is seated is kept** (`_ready_unseated` in the bridge) and answered by `add_player`: over ENet with loss it overtakes the link's `loaded`, and a dropped READY left the client waiting for ever. `headless_net` sends it first (armed). [history](docs/history.md)
- The CLOCK carries crates left and both rounds-won tallies, and on a round's end it is sent **before** the ROUND.
- A `DotNetMessage` script must never preload its own file (leaks the whole script graph at exit on a deployed server). `dedicated` checks the source.
- `remove_player` forgets the entity in dot-combat and closes it before the node goes.
- Layout settings that shape the map (`arena_radius`, `courtyard_west_lane`, `hook_layout`, and the `district` a voted map names) travel in the HELLO and are not cvars; a live change would move geometry under connected players. A voted bowl is rebuilt only at a round's start and sent as BOWL between the PROP_GONEs and the PROPs. [netcode](docs/netcode.md#what-crosses)

**The map** ([map](docs/map.md))
- One obstacle description (`_obstacles`, from `PILLAR_LAYOUT`, `TANK_LAYOUT`, the colonnade); steering, scatter and gap rules read only that. Never add a second list.
- Measure to surfaces, per obstacle radius, never centre distances against a constant.
- No gap under `BUS_GAP` (4.8 m clear), checked by `narrowest_gap()` on the built arena at the shipped and every minimum radius. A lane under `LANE_THROUGH` (7.2 m) is a door the bot cannot follow through; a place where a runner standing still is never reached is a refuge, and no lane may be one.
- Every bowl on the ballot (`BfhBowls`) is held to the gap rule by `headless_run`; a new bowl is a new map. [map](docs/map.md#minimum-radii)
- **A bowl may carry settings** (dot-game's `DotGameMapConfig`): `cfg/game/mg-buses-from-hell/dot_map/map/<bowl>.yml` (`bfh_*.yml` is the commented starter; `cfg/server/...` overrides), only the `BfhMapConfig.KEYS` tunables, applied by `BfhModule` on `bowl_changed` and restored on the next, and on the client for the three it uses (`CLIENT_KEYS`). The game has no BSP-imported maps, so there is no converter output; `headless_mapcfg` checks apply and restore.
- Known refuge, pinned by the suite and left as Christian's call: the hook's two gaps against a bot (`hook_layout`, nightly `runner-standing-1`).
- Spawn props dropped from a few centimetres, never touching the floor. The scatter keeps out of obstacles, the scaffold margin, the bus start lanes, and the toys.
- Six loose dot-props toys on a ring (`BfhArena.toy_placements`, a pure function of the build) on their own bit (`TOY_LAYER`): buses and crates hit them, a hammer whacks them, a person walks through; a client registers every toy mirror on TOYS before its bowl is built. [map](docs/map.md#toys)

**Bots** ([bots](docs/bots.md))
- A bus "sent home" is almost always a steering wedge read by the stuck rule; look at `steer_around` first.
- `steer_around` is a nudge, not a path; its ceiling is `LANE_THROUGH`. A lane-threading exemption was tried and wedges the stacks.
- A detour is passed as a route `[detour, past the quarry]`, never as the driver's last waypoint (it brakes into it).
- A bus's brakes are newtons (dot-vehicle 4f4afaf): 30 kN foot brake (the bot's, and a person's S until the bus stops, then reverse: `brake_then_reverse` in `_drive_buses`, persons only), 40 kN handbrake (Ctrl) with the rear grip at 0.15 while held so it slides. `headless_run`'s "a bus's brakes" and "a handbrake turn" measure them; the deck chase is what a weaker foot brake slows. `tools/drive_shot.sh stop|handbrake|turn` draws them. [history](docs/history.md#s-was-reverse-thrust-and-the-handbrake-never-slid-2026-10-12)
- Bot knobs (`bfh_bot_aim_past`, `bfh_bot_steer_clearance`, `bfh_bot_route_clearance`, `bfh_bot_route_replan`, `bfh_bot_unwedge_after`, `bfh_bot_unwedge_seconds`, `bfh_bus_stuck_break`, `bfh_bus_stuck_reset`) are authority-only live cvars.

**The game** ([design](docs/design.md), [services](docs/services.md))
- The hammer cannot hurt a person; it is not a `DotWeapon`. No auto-hop. Damage is by closing speed; nothing above the bus's roof is hit.
- dot-match's teams: `max_difference` 0, swaps through `switch_team`, a leaver leaves dot-match too. A side with nobody in it must not start a round.
- The bowl vote opens `bfh_vote_after` into a round and applies at its end (MANUAL, `END_OF_ROUND`), rocked votes too; under MANUAL `BfhVote` opens a passed rock-the-vote itself, or `!rtv` does nothing. The match answers dot-vote's `round_in_progress_fn` (`world.match_node.is_live()`, set by name because an older shell's dot-vote lacks it), so a `time_up: finish_round` limit that runs out in warmup or between rounds changes at once instead of holding for `finish_round_max_sec`; `dedicated` checks both halves. [design](docs/design.md#the-bowl-vote)
- The HUD follows the menu's theme and HUD size (`BfhHud.follow_menu`, dot-menu's `follow_hud` by name); `BfhHud.piece_theme()` is the accent only (sand highlight and edge, the pillar colour as good), never plate, text or ink, and the HUD's Labels set no colour of their own except the accent lines. `headless_run` checks a theme change reaches the pieces and the lines.
- `DotRandomManager` is not registered as a service (two worlds in one process).
- Progress is counted on the authority only, never for a bot (`is_bot` is `add_player`'s argument), and kept in memory while guests' keys are session ids.
- Team is the channel that matters: voice defaults to it, no backlog on it, push to talk. Refused moderation tools are refused for a reason `modtools` prints.

**Tests** ([testing](docs/testing.md))
- Every suite counts sections (`SECTIONS`, `_done()`) as well as checks.
- Each test world has its own physics space; move a runner with `_put`, never `global_position` alone; assert a bot's pace and a bus's lethal speed, not arrival; arm every new check.
