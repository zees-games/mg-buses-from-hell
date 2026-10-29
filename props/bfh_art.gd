extends RefCounted

const BfhPaths := preload("../game/bfh_paths.gd")

## Puts a Kenney model's atlas back on it when the engine could not find it.

const CHANNEL := "bfh.art"

## The two kits' atlases, rebased where they are defined. [method paint] rebases again, which is a
## no-op on these and is what makes an [code]atlas_path[/code] set in a scene safe too — the
## publisher has already rewritten that one onto the mount.
static var SURVIVAL_ATLAS := BfhPaths.rebase("res://assets/kenney/survival/Textures/colormap.png")
static var CAR_ATLAS := BfhPaths.rebase("res://assets/kenney/car/Textures/colormap.png")


## Gives every untextured material under [param root] the atlas at [param atlas_path].
static func paint(root: Node, atlas_path: String) -> int:
	if root == null:
		return 0

	var repaired := 0
	var atlas: Texture2D = null

	for mesh in _meshes(root):
		for surface in range(mesh.get_surface_override_material_count()):
			var material := mesh.get_active_material(surface) as BaseMaterial3D

			if material == null or material.albedo_texture != null:
				continue

			if atlas == null:
				# Loaded lazily: a build never gets here, and loading a texture to decide
				# it was not needed is the sort of cost that turns up on a phone.
				atlas = load(BfhPaths.rebase(atlas_path)) as Texture2D

				if atlas == null:
					DotLog.warn(CHANNEL, "the atlas is missing from this build", {
						"path": BfhPaths.rebase(atlas_path),
					})
					return repaired

			# On a DUPLICATE, and this is the line that stops one repair painting the whole game: an imported
			# scene's materials are shared between every instance of it, so writing into one is writing into
			# all of them — which is what is wanted here — but the surface override below is.
			var fixed: BaseMaterial3D = material.duplicate()
			fixed.albedo_texture = atlas
			mesh.set_surface_override_material(surface, fixed)
			repaired += 1

	return repaired


static func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var as_mesh := node as MeshInstance3D

	if as_mesh != null:
		out.append(as_mesh)

	for child in node.get_children():
		out.append_array(_meshes(child))

	return out
