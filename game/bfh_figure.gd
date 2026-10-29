extends Node3D

const BfhPaths := preload("bfh_paths.gd")

## What somebody ELSE looks like: a Kenney blocky character, scaled to the runner's hull and turned
## to face where they are looking. Client side only; a server never builds one.

const CHANNEL := "bfh.figure"

## Runners are drawn as a crowd, one of six ordinary people chosen by their id, so two
## runners standing together can be told apart. Only the atlas letter is read.
static var RUNNER_ATLASES: Array[String] = [
	BfhPaths.rebase("res://assets/kenney/characters/Textures/texture-a.png"),
	BfhPaths.rebase("res://assets/kenney/characters/Textures/texture-b.png"),
	BfhPaths.rebase("res://assets/kenney/characters/Textures/texture-c.png"),
	BfhPaths.rebase("res://assets/kenney/characters/Textures/texture-e.png"),
	BfhPaths.rebase("res://assets/kenney/characters/Textures/texture-f.png"),
	BfhPaths.rebase("res://assets/kenney/characters/Textures/texture-k.png"),
]

## A driver on foot wears the uniform. Rare — a driver is drawn AS the bus for almost the
## whole round — but a driver whose bus is wrecked, or who is between seats, is on the
## other side from every runner near them and should not look like one.
static var DRIVER_ATLAS := BfhPaths.rebase("res://assets/kenney/characters/Textures/texture-j.png")

## Which atlas this figure is wearing. Read by the suite.
var atlas: String = ""

## Whether the people's art loaded, or a capsule stands in.
var from_art: bool = false

## The person, under this node.
var person: DotHumanoidFigure = null


## Builds the figure to stand [param height] metres tall, feet at this node's origin.
func build(height: float, atlas_path: String) -> void:
	atlas = atlas_path
	var look := DotHumanoidLook.from_letter(atlas_path)
	if look == null:
		look = DotHumanoidLook.stock(hash(atlas_path))
	if person != null:
		remove_child(person)
		person.queue_free()
	person = DotHumanoidFigure.new()
	person.name = "Person"
	add_child(person)
	person.build(look, height)
	person.auto_animate = true
	from_art = person.from_art
	if not from_art:
		DotLog.warn(CHANNEL, "the person's art did not load; a capsule stands in", {"atlas": atlas.get_file()})


## Turns the figure to face [param yaw_radians], the controller's own yaw.
func face(yaw_radians: float) -> void:
	rotation = Vector3(0.0, yaw_radians, 0.0)


func describe() -> Dictionary:
	return {
		"art": from_art,
		"atlas": atlas.get_file(),
		"visible": visible,
		"at": str(global_position.snapped(Vector3.ONE * 0.01)) if is_inside_tree() else "-",
	}
