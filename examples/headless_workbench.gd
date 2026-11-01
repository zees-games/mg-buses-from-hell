extends DotGameWorkbenchSuite

## mg-buses-from-hell: the workbench over the config binder, one edit per profile set, the export and its cfg round trip.
## Run: godot --headless --path . res://examples/headless_workbench.tscn

const BfhConfig := preload("../game/bfh_config.gd")


func _make_config() -> DotConfig:
	return BfhConfig.new()


func _make_binder(config: DotConfig) -> DotGameConfigBinder:
	return BfhConfig.make_binder(config)
