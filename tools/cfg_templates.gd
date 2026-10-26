extends SceneTree

## Rewrites cfg/game/mg-buses-from-hell/config_*/game.yml from BfhConfig's fields: godot --headless --path . --script tools/cfg_templates.gd

const BfhConfig := preload("../game/bfh_config.gd")


func _init() -> void:
	var binder := BfhConfig.make_binder(BfhConfig.new())
	var files := binder.template_files()
	for path: String in files:
		var res := DotPaths.write_text("res://" + path, files[path])
		print("%s %s" % ["wrote" if res.ok else "FAILED", path])
	quit()
