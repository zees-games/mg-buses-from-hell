Buses From Hell is a 3D multiplayer game. A few players drive buses, and everybody else is on foot and trying to survive. The drivers try to run the runners over before the clock runs out. It is inspired by a classic Counter-Strike: Source MiniGames map called [**buses_from_hell**](https://gamebanana.com/mods/127607) ([gameplay video](https://www.youtube.com/watch?v=wnY1eu890k4)).

![Preview](https://github.com/zees-games/mg-buses-from-hell/blob/main/images/preview.gif?raw=true)

[Play on the test server](https://moddingcommunity.com/godot/s/bfh01/play).

It is built on [Godot 4](https://godotengine.org/), the [Gamespice](https://gamespice.net) platform and addon collection.

Everything in this repository is open source under the MIT license. The only closed part is the website back-end it can sign in through. If you do not want to use Gamespice, you can plug in your own sign-in back-end.

The game was built with Claude Code and is maintained with it. It has a full automated test suite, but few real players have tried it yet, so expect rough edges. Please report what you find.

## How it plays

By default four players drive buses (`bfh_drivers`). Everybody else is on foot in a walled sand bowl full of crates and exploding barrels. The drivers try to run the runners over before the clock runs out; the runners win if anybody is still standing at the end. Sides swap every three rounds by default, so everybody gets a turn driving.

The runners have a hammer, and **the hammer can't hurt anybody**. It breaks crates and shoves them. So the only thing a runner can change is the shape of the bowl: break the crate a driver is hiding behind, shove one into a bus's path, open a gap or close one. You can stand on a crate, and it carries you when it moves.

| | |
| --- | --- |
| **Crate** | 100 health. Three hammer swings, or one bus hit at speed. You can stand on it. |
| **Barrel** | Explodes when anything hits it, throwing runners into the air and crates across the bowl. |
| **Concrete block** | Can't be broken or pushed, so there is always some cover left. |

The bowl always has three landmarks: a lane of concrete pillars in the west, four tanks round a courtyard in the east, and a staircase of crates in the south-east that is the only high ground a runner can climb (and a bus can knock down). The rest of the crates and barrels are scattered from a seed, so two servers on the same seed get the same layout.

Three more maps are on the ballot. Each is a kind of place rather than a bowl of landmarks, designed by hand and built in code, and every street between buildings is wide enough for a bus, the same rule as the bowl.

| Map | What it is |
| --- | --- |
| Sand bowl | The default: a walled bowl with a lane of concrete pillars, four tanks round a courtyard and a staircase of crates |
| Downtown | A grid of tower blocks with a painted one-way loop round the middle four |
| Hill Town | A road that winds in an S-bend and a switchback, with houses stepping along it |
| The Suburbs | A ring road with three roundabouts and a cul-de-sac |

When you are run over, you watch the bus that got you for a moment, then whoever is still up until the next round.

## Controls

| Key | Runner | Driver |
| --- | --- | --- |
| **WASD** | Move | Drive and steer |
| **Space** | Jump | |
| **Mouse 1** | Swing the hammer | Horn |
| **G** | While out: a free camera (WASD, Space / Ctrl up and down, Shift fast, Alt slow, mouse to look), and back onto a player | |
| **F** | Flashlight, while still up (starts off: the bowl is in daylight). A lit beam is seen by everyone who can see you | Flashlight, from the cab |
| **Tab** (hold) | Scoreboard | Scoreboard |
| **Y** / **U** | Chat / chat to your side | Chat / chat to your side |
| **V** | Push to talk (to your side) | Push to talk |
| **H** | Help: the rules and every key as you have it bound | Help |
| **Esc** | Menu: settings (every key can be rebound), help, and leave | Menu |

While you are out: **Mouse 1** / **Mouse 2** watch the next or previous player, and **Space** switches between their eyes and behind them.

## Getting started

You need [Godot 4.7](https://godotengine.org/download). The game is built from many Gamespice addons, each in its own repository, so the easiest way to get everything is [dot-bootstrap](https://github.com/gamespice-platform/bootstrap). It clones every project and links the addons into each one:

```bash
git clone https://github.com/gamespice-platform/bootstrap.git
cd dot-bootstrap
./bootstrap.sh
cd projects/mg-buses-from-hell
./game.sh
```

On Windows, run `bootstrap.ps1` instead and open the project in Godot.

`game.sh` does everything else:

| Command | What it does |
| --- | --- |
| `./game.sh` | Play offline (bots drive the buses) |
| `./game.sh online` | Start a local server and the browser client, and print the link to open |
| `./game.sh online down` | Stop them |
| `./game.sh server` | Start a local dedicated server only |
| `./game.sh test` | Check every script and run every test suite |
| `./game.sh shot` | Save a screenshot to `screenshots/`. `./game.sh shot --help` lists the views |
| `./game.sh help` | All of the options |

`online` and `server` use [dot-server-deploy](https://github.com/gamespice-platform/server-deploy), which bootstrap clones next to this one. Run its `./setup.sh` once first.

## Running a server

Settings are cvars. Set them in the server's config, on the command line, or live from the console. Changes to the layout take effect from the next round.

Every `BfhConfig` field is also a `bfh_<field>` cvar and a key in a file under `cfg/game/mg-buses-from-hell/config_<group>/game.yml` (or the same file under `cfg/server/`); a typo stops a dedicated server's boot. `bfh_config_diff save` writes what differs from the defaults, ready to copy back as shipped defaults, and F9 (or the `workbench` console command) opens the tuning panel, off on a dedicated server unless `workbench: enabled: true` is in `cfg/server.yml`. The buses' feel (mass, engine, brakes, steering, springs) is server-side, so it is a config field too and a change reaches buses built from then on. `mp_teamblock` (0) and `mp_enemyblock` (1) with `!block` and `!noblock` come from dot-team through dot-game; players are not solid to each other in this game, so they change nothing physical yet.

| Setting | Default | What it does |
| --- | --- | --- |
| `bfh_round_seconds` | 180 | Length of a round |
| `bfh_drivers` | 4 | How many buses (and, with nobody in a seat, bots). Any value from 1 |
| `bfh_crates` | 34 | Crates in the next round |
| `bfh_barrels` | 9 | Barrels in the next round |
| `bfh_bus_top_speed` | 22 | Bus top speed, metres per second |
| `bfh_bus_lethal_speed` | 9 | Closing speed at which a bus kills outright, metres per second |
| `bfh_bus_lane_width` | 6 | Metres kept clear in front of each bus start (0 = none) |
| `bfh_bots` | 1 | 0 = no automatic bots at all |
| `bot_quota` | same as `bfh_drivers` (4) | Driving seats kept full: bots plus people driving. A person who takes a seat replaces a bot. |
| `bot_quota_mode` | `fill` | `fill`, `fixed` (that many bots), `per_player` (that many per driver) or `off` |
| `bot_difficulty` | `medium` | `easy`, `medium`, `hard` or `nightmare`: how far ahead of a runner a bot bus aims and how fast it drives. Every `bot_*` setting is also a cvar. |
| `bfh_bot_aim_past` | 8 | Metres past a runner a bot bus aims, so it arrives at speed |
| `bfh_bot_steer_clearance` | 3.6 | Metres a bot bus keeps off a pillar or drum |
| `bfh_bot_route_clearance` | 3.4 | Metres a route keeps off a building, wall or ramp |
| `bfh_bot_route_replan` | 0.5 | Seconds between a bot bus's route replans |
| `bfh_bot_unwedge_after` | 0.5 | Seconds against something before a bot bus reverses off it |
| `bfh_bot_unwedge_seconds` | 1.4 | Seconds it reverses for |
| `bfh_bus_stuck_break` | 1 | Seconds a bus may push against something before what is under it breaks |
| `bfh_bus_stuck_reset` | 5 | Seconds before a stuck bus is put back on its start line |

Runners who are run over or blown up fly as ragdolls ([dot-player-char](https://github.com/gamespice-platform/player-char)); the server picks how each one goes down and everybody sees the same fall. `sv_ragdoll 0` makes it a quick fall with no physics, `sv_ragdoll_style` picks ragdoll, stiff, topple or hide, `sv_ragdoll_time` and `sv_ragdoll_max` say how long and how many, and `sv_ragdoll_reactions` weights the falls (`limp`, `face_plant`, `crumple`, `headshot_launch`, `power_launch`; 0 turns one off).

A runner who is out can fly a free camera (G); `mp_freeroam 0` keeps them on players, `mp_forcecamera 1` or `2` restricts the camera and switches it off, and `mp_freeroam_speed` (metres a second) sets the speed.

The bot cvars are the family's shared ones (dot-server's `DotBotQuota`), counted here in driving seats because a bot only ever drives: `bfh_drivers` is how many seats there are and caps the quota.

Two settings are the map itself, so they are read when the bowl is built and are not cvars: set them in the JSON config, the environment (`BFH_HOOK_LAYOUT`, `BFH_COURTYARD_WEST_LANE`) or the command line (`--bfh-hook-layout`, `--bfh-courtyard-west-lane`) and restart. Connected clients are told them when they join.

| Setting | Default | What it does |
| --- | --- | --- |
| `hook_layout` | `tight` | The three pillars past the stacks: `tight` (as built) or `wide` (5.6 m gaps opened to 7.4 to 7.6 m) |
| `courtyard_west_lane` | 7.6 | Metres of floor in the tank farm's west lane (6.6 is the farm as first built) |

Console commands:

| Command | |
| --- | --- |
| `bfh_status` | The round, the bowl and the buses |
| `bfh_stats <userid>` | A player's numbers this session and what they have earned |
| `bfh_say <text>` | Say something to everybody, as the server |
| `bfh_net` | What the network code is doing |

### Admin commands
These come from [dot-moderation](https://github.com/gamespice-platform/moderation). Type them in the console, or in chat with a `!` in front. `@team:drivers` and `@team:runners` work as targets, and `modtools` lists what is supported.

| Command | |
| --- | --- |
| `noclip`, `freeze`, `speed`, `gravity` | Runners only (a driver's bus is what moves) |
| `god`, `buddha`, `hp`, `slay`, `slap`, `rename` | |
| `blind <player> [on\|off\|seconds]` | Blacks out that player's screen |
| `beacon <player> [on\|off]` | A ring and a ping on that player (round the bus, for a driver) |
| `bring`, `goto`, `send`, `return` | Runners only |

`respawn`, `give`, `strip` and `burn` are turned off: a runner who is out stays out until the next round, and the hammer is the only thing anybody holds.

## Stats and achievements

Five numbers are counted per player (runners flattened, rounds survived, seconds survived, crates broken, and crates you shoved that a bus then hit) and there are eight achievements built on them. They only last for the session for now, because the game has no accounts yet.

## Testing

```bash
./game.sh test                  # every script parses, then every suite runs
./game.sh test headless_run     # one suite
```

| Suite | What it covers |
| --- | --- |
| `headless_run` | The game itself: rounds, buses, crates, barrels, the hammer and bots driving |
| `headless_net` | A server and a client in one process, over the network code |
| `headless_config`, `headless_workbench`, `headless_mapcfg` | Settings, the workbench and per-map config |
| `headless_touch` | Phone controls |
| `headless_workshop` | The workshop (content) flow |
| `dedicated` | A real server: boots, loads the game, runs its commands |

[`CLAUDE.md`](CLAUDE.md) has the design decisions and the reasoning behind them.

## Credits

| Asset | Author / source | License | Where |
| --- | --- | --- | --- |
| Bus, crate, barrel | Kenney ([kenney.nl](https://kenney.nl)) | CC0 | `assets/kenney/` |
| Runners | Quaternius, [Zombie Apocalypse Kit](https://quaternius.com/packs/zombieapocalypsekit.html), skinned from Kenney's blocky characters | CC0 1.0 | dot-player-char |
| Bowl, town buildings and roads | Drawn in code (`game/bfh_districts.gd`) | none | in code |
| Game sounds | Generated; the game ships no audio files | none | in code |
| Footsteps | Kenney, Impact Sounds | CC0 | `addons/dot_audio/stock/CREDITS.md` |
| Wind | Generated by dot-audio | CC0 | `addons/dot_audio/stock/CREDITS.md` |
| Beach balls, barrels, tyre | [dot-props](https://github.com/gamespice-platform/props), drawn in code; sounds by Kenney | CC0 | `addons/dot_props/toys/sounds/CREDITS.md` |

If you made one of these assets and want it removed, open an issue.

## License

MIT. See [LICENSE](LICENSE). The Kenney art is CC0, which is public domain.
