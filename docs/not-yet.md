# Not yet

What this game does not do yet, each with where the detail is.

- **A Workshop map is only a radius.** `provides.json` accepts subscribed maps of `map_kind` `arena` (maps only, no weapons or props). A pack's `map` entry names in `scene` a bowl document, JSON `{"radius": metres}`, clamped to 40 to 70 m (`BfhBowls.SMALL_RADIUS`, `WORKSHOP_MAX_RADIUS`); solo lists it in the map menu (M) as `Name [Pack]` and builds it through `change_bowl_now`, online lists none, and a document that does not load is not listed. A bowl here is `BfhArena.build` run on a radius, so a pack cannot yet bring its own obstacles, lanes or district: that needs an obstacle-list format that `_obstacles`, the gap rule and the bots all read, which is a second map source, not a loader. [map](map.md)
