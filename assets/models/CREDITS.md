# Models made for this game

## bus.glb (the bus)

Base: the "garbage-truck" from Kenney's Car Kit ([kenney.nl](https://kenney.nl), CC0, public domain), vendored as `assets/kenney/car/bus.glb`. Modified with `art-src/bus/build.py` (Blender 4.3, `blender -b --python art-src/bus/build.py`). Our changes are released under the repository's MIT licence; the base stays CC0.

What changed: the green paint is school-bus yellow; the open skip is capped with a roof and its heap of rubbish removed; a black belt line, a row of black windows down both sides, black roof rails, a red and amber lamp bar on the cab, red and orange flames up the cab's flanks, two exhaust stacks, four white roof spikes, red tail lamps and a rear bumper were added. All of it uses the kit's own colormap (`bus_colormap.png`, the same atlas as the base).

What did not change: the four `wheel-*` objects are the kit's, untouched (`props/bfh_bus.gd` finds them by name and spins them), and the body's bounds are within 3 cm of the original on the sides and 13 cm above, so the scene's scale, collision hull and wheel positions are unchanged. Renders for review are in `art-src/bus/renders/`.
