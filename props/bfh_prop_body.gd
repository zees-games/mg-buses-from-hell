extends RigidBody3D

const BfhArt := preload("bfh_art.gd")

## A crate or a barrel: a rigid body with a Kenney model under it.

const CHANNEL := "bfh.prop"

## Which kit this body's model came from. Set per scene, because the two atlases are
## different files with the same name.
@export var atlas_path: String = BfhArt.SURVIVAL_ATLAS


func _ready() -> void:
	var repaired := BfhArt.paint(self, atlas_path)

	if repaired > 0:
		DotLog.debug(CHANNEL, "the art was repainted from the mount", {
			"materials": repaired, "body": name,
		})
