extends Node3D

const BfhPaths := preload("bfh_paths.gd")
const BfhViewmodel := preload("bfh_viewmodel.gd")

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
var person: GSHumanoidFigure = null

## The hammer in the right hand, or null when the figure holds nothing (a driver on foot).
var hammer: Node3D = null

## The hammer's size in the hand mount, which is itself [member GSHumanoidFigure.held_scale]
## times life size: this brings the drawn hammer back to about life size.
const HAMMER_SCALE := 0.6

var _holds_hammer: bool = false


## Builds the figure to stand [param height] metres tall, feet at this node's origin.
func build(height: float, atlas_path: String) -> void:
	atlas = atlas_path
	var look := GSHumanoidLook.from_letter(atlas_path)
	if look == null:
		look = GSHumanoidLook.stock(hash(atlas_path))
	if person != null:
		remove_child(person)
		person.queue_free()
	person = GSHumanoidFigure.new()
	person.name = "Person"
	add_child(person)
	person.build(look, height)
	person.auto_animate = true
	from_art = person.from_art
	hammer = null
	hold_hammer(_holds_hammer)
	if not from_art:
		GSLog.warn(CHANNEL, "the person's art did not load; a capsule stands in", {"atlas": atlas.get_file()})


## Puts the hammer in the right hand (and the arms in the melee hold), or takes it away. Kept over
## a rebuild.
func hold_hammer(on: bool) -> void:
	_holds_hammer = on
	if person == null:
		return
	if not on:
		if hammer != null and is_instance_valid(hammer):
			hammer.queue_free()
		hammer = null
		person.set_hold(GSHumanoidFigure.Hold.NONE)
		return
	person.set_hold(GSHumanoidFigure.Hold.MELEE)
	if hammer != null and is_instance_valid(hammer):
		return
	var hand := person.attachment(&"right_hand")
	if hand == null:
		return
	hammer = BfhViewmodel.build_hammer(hand, true)
	hammer.scale = Vector3.ONE * HAMMER_SCALE


## A hammer blow over whatever the legs are doing; an empty hand punches.
func swing() -> void:
	if person != null:
		person.swing()


## Turns the figure to face [param yaw_radians], the controller's own yaw.
func face(yaw_radians: float) -> void:
	rotation = Vector3(0.0, yaw_radians, 0.0)


func describe() -> Dictionary:
	return {
		"art": from_art,
		"atlas": atlas.get_file(),
		"visible": visible,
		"hammer": hammer != null,
		"at": str(global_position.snapped(Vector3.ONE * 0.01)) if is_inside_tree() else "-",
	}
