# Pack delivery: what a delivered game may not do

This game is delivered as a signed dot-cloud pack and mounted into the client shell, which is the same build whatever it joins. It was the first game in the family to vendor art, and the first deployed on dot-game, so several forms of the family's one delivery bug were found here. The family view is dot-cloud's [mounting](../../dot-cloud/docs/mounting.md) and [publishing](../../dot-cloud/docs/publishing.md) docs; this is what each rule means in this repository.

Every bug in this file was invisible to every suite here and was found by publishing the pack and connecting a real client to a real server. Re-check that way after touching anything below (see [testing.md](testing.md#the-deployment-is-the-only-test-of-this)).

## No `class_name`, anywhere in this repository

**A mounted pack's `class_name` globals are not registered in the host**, so a delivered game that used one would mount, load its scenes, and have every script dead with nothing reporting it. Every script is reached by a relative `preload`. This game was written with seven and converted when it was deployed; `dot-server-deploy/tools/check.sh` refuses a new one in any game repository.

## Every `res://` path goes through `BfhPaths.rebase()`, where it is DEFINED

`static var CRATE_SCENE := BfhPaths.rebase("res://…")`, not a `const` wrapped at every call site. Both are correct today; the second is one new call site away from a prop that does not spawn in a delivered round, and `check.sh` cannot follow a `const` to its uses. `headless_run`'s "a delivered pack's own paths" scans every shipped script for a bare `"res://…"` naming one of this game's own directories and fails naming the line.

**`rebase` is idempotent (the seventh form).** The publisher rewrites every `res://` string inside a `.tscn`, `.tres` and `.import` onto the mount prefix, and not the ones inside a `.gd`. So a delivered game holds both: a `const` in a script that still needs rebasing, and an exported property on a node (`bfh_prop_body.atlas_path`) that arrives already absolute and must not be rebased again, or it becomes `res://dot_cloud/<id>/<version>/dot_cloud/<id>/<version>/…`. `rebase_onto(path, here)` returns a path already under the root unchanged. It is split from `rebase()` so the mounted case can be **tested from a build**: built in, the root is `res://` and every such check is a tautology that passes with the guard removed. mg-smash-copter found this form; its write-up is [mg-smash-copter/docs/delivery.md](../../mg-smash-copter/docs/delivery.md).

## An imported model's own texture dependency (the sixth form)

**A Kenney GLB references its texture by relative URI** (`Textures/colormap.png`), and Godot imports it into a binary scene whose external dependency is recorded as a **UID plus the absolute path** the file had at import. Inside a mounted pack the UID was not registered and the path is `res://assets/…`, which in the host is another game's directory or nothing. The mesh loads; the texture does not; every crate is plain white, or the model's node appears to vanish. It is the one form nothing rewrites, because the publisher rewrites text resources and a binary `.scn` is not one.

dot-cloud now registers a mounted pack's own UIDs (`DotCloudMounter._register_uids`). `props/bfh_art.gd` is the game's belt to those braces: `paint(root, atlas_path)` sets the atlas only on a material that has none, so in a build, where the import worked, it does nothing, and the picture a developer sees is the one a player gets. Not an unconditional `material_override`, which would be a second definition of how the models look.

**Each Kenney kit gets its own folder**: the Survival Kit and the Car Kit each ship a `Textures/colormap.png` and they are different files. Flattening them paints the bus in the survival kit's palette, a plausible-looking wrong answer. The atlas must sit beside the model at exactly the path the GLB names, or the mesh loads untextured, silently.

## Project settings do not travel

Two things in `project.godot` are not in the pack, and both made a delivered game look broken with nothing to act on:

- **Gravity.** `physics/3d/default_gravity` is 20 here (what the character movement wants, and every 3D game here uses) and 9.8 in the shell, so delivered, everything floated and the bus's suspension was tuned against twice the real force. `BfhConfig.gravity` is the number, and `BfhGame._apply_gravity` writes it onto the world's **own physics space**, not the global setting, because a server and a client in one process are two worlds and a global would be one deciding for the other.
- **The renderer.** The shell renders with `gl_compatibility` because the browser is its target. Lighting tuned under Forward+ was blown out to white on every delivered client. The project is on `gl_compatibility` and the sun, ambient and exposure are tuned under it.

## Smaller traps the deployment found

- **A `:=` that infers a type from a host class fails inside a pack.** `var config := BfhServices.voice_format()` compiles in this project and fails in a mount, because a script whose base class lives in the host build cannot hand its return type to a script in the pack. Spell the type explicitly in any client-side script.
- **A stale class cache three repositories away.** Adding a `class_name` to a shared addon leaves every project that links it (dot-server-deploy included) failing to resolve this game's scripts until that project is re-imported. The addon and the game are fine; re-import.
- **Model facing.** Kenney's vehicles and characters face +Z and this family's forward is -Z. The bus once chased people cab-last; screenshots did not show the direction of travel. Check facing in motion.
- **Collision shapes stay primitive** (box, cylinder, box). A convex hull off the model would be more faithful and much worse: dot-props documents what loose triangles do to a sliding body, and a bus is the thing sliding.
