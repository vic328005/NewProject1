extends Node
class_name GameManager

const WORLD_SCENE_UID := "uid://d1md2xh0j3x36"

var event_bus: EventBus
var beat_conductor: BeatConductor
var current_world: World = null


func _init() -> void:
	_ensure_event_bus()
	_ensure_beat_conductor()


func _ready() -> void:
	_ensure_world()


func setup() -> void:
	_ensure_event_bus()
	_ensure_beat_conductor()
	_ensure_world()


func emit_event(event_name: StringName, payload: Variant = null) -> void:
	_ensure_event_bus().emit_event(event_name, payload)


func _ensure_event_bus() -> EventBus:
	if is_instance_valid(event_bus):
		return event_bus

	event_bus = EventBus.new()
	event_bus.name = "EventBus"
	add_child(event_bus)
	return event_bus


func _ensure_beat_conductor() -> BeatConductor:
	if is_instance_valid(beat_conductor):
		return beat_conductor

	beat_conductor = BeatConductor.new()
	beat_conductor.name = "BeatConductor"
	add_child(beat_conductor)
	return beat_conductor


func _ensure_world() -> World:
	if is_instance_valid(current_world):
		return current_world

	var existing_world := get_node_or_null("World") as World
	if existing_world != null:
		current_world = existing_world
		return current_world

	var world_scene := load(WORLD_SCENE_UID) as PackedScene
	if world_scene == null:
		push_error("Failed to load world scene: %s" % WORLD_SCENE_UID)
		return null

	var world := world_scene.instantiate() as World
	if world == null:
		push_error("World scene root is not a World: %s" % WORLD_SCENE_UID)
		return null

	world.name = "World"
	add_child(world)
	current_world = world
	return world
