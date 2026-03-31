@tool
extends EditorPlugin

const BRIDGE_VERSION := "1.0.0"
const POLL_INTERVAL_MSEC := 100
const HEARTBEAT_INTERVAL_MSEC := 1000
const PLUGIN_CONFIG_PATH := "res://addons/qq_editor_bridge/plugin.cfg"

var _project_root := ""
var _state_file := ""
var _console_file := ""
var _request_dir := ""
var _response_dir := ""
var _last_poll_msec := 0
var _last_heartbeat_msec := 0
var _request_count := 0
var _last_request_id := ""
var _last_command := ""


func _enter_tree() -> void:
	_project_root = _normalize_dir(ProjectSettings.globalize_path("res://"))
	_state_file = _join_path(_project_root, ".qq/state/qq-godot-editor-bridge.json")
	_console_file = _join_path(_project_root, ".qq/state/qq-godot-editor-console.jsonl")
	_request_dir = _join_path(_project_root, ".qq/state/qq-godot-editor/requests")
	_response_dir = _join_path(_project_root, ".qq/state/qq-godot-editor/responses")
	_ensure_dir(_join_path(_project_root, ".qq/state"))
	_ensure_dir(_request_dir)
	_ensure_dir(_response_dir)
	_append_console("info", "bridge_loaded", {"project_root": _project_root})
	_write_state(true)
	set_process(true)


func _exit_tree() -> void:
	var payload := _build_state_payload(false)
	payload["message"] = "Godot editor bridge stopped"
	_write_json(_state_file, payload)
	_append_console("info", "bridge_unloaded", {})


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_poll_msec >= POLL_INTERVAL_MSEC:
		_last_poll_msec = now
		_poll_requests()
	if now - _last_heartbeat_msec >= HEARTBEAT_INTERVAL_MSEC:
		_last_heartbeat_msec = now
		_write_state(true)


func _poll_requests() -> void:
	for filename in DirAccess.get_files_at(_request_dir):
		if not filename.ends_with(".json"):
			continue
		_handle_request(_join_path(_request_dir, filename))


func _handle_request(path: String) -> void:
	var payload = _read_json(path)
	var request_id := str(payload.get("requestId", ""))
	var command := str(payload.get("command", ""))
	var args = payload.get("args", {})
	if not (args is Dictionary):
		args = {}

	var response: Dictionary
	if request_id.is_empty() or command.is_empty():
		response = _error_response(request_id, command, "INVALID_REQUEST", "requestId and command are required")
	else:
		response = _dispatch_command(command, args)
		response["requestId"] = request_id
		response["command"] = command
		response["handledAtUnix"] = Time.get_unix_time_from_system()

	_request_count += 1
	_last_request_id = request_id
	_last_command = command
	_write_json(_join_path(_response_dir, "%s.json" % request_id), response)
	DirAccess.remove_absolute(path)
	_append_console("info" if bool(response.get("ok")) else "error", command, {"requestId": request_id, "response": response})


func _dispatch_command(command: String, args: Dictionary) -> Dictionary:
	match command:
		"status":
			return _ok("Editor status loaded", _status_payload())
		"hierarchy":
			return _hierarchy(args)
		"find":
			return _find_nodes(args)
		"inspect":
			return _inspect_node(args)
		"get-selection":
			return _get_selection()
		"list-scenes":
			return _list_scenes(args)
		"list-assets":
			return _list_assets(args)
		"play":
			get_editor_interface().play_current_scene()
			return _ok("Playing current scene", _status_payload())
		"stop":
			get_editor_interface().stop_playing_scene()
			return _ok("Stopped current scene", _status_payload())
		"pause":
			get_tree().paused = not get_tree().paused
			return _ok("Toggled tree pause", {"paused": get_tree().paused})
		"save-scene":
			return _save_scene(args)
		"open-scene":
			return _open_scene(args)
		"new-scene":
			return _new_scene(args)
		"reload-scene":
			return _reload_scene(args)
		"create-node":
			return _create_node(args)
		"instantiate-scene":
			return _instantiate_scene(args)
		"destroy-node":
			return _destroy_node(args)
		"duplicate-node":
			return _duplicate_node(args)
		"set-transform":
			return _set_transform(args)
		"set-parent":
			return _set_parent(args)
		"set-active":
			return _set_active(args)
		"set-property":
			return _set_property(args)
		"add-script":
			return _add_script(args)
		"select-node":
			return _select_node(args)
		"refresh-filesystem":
			get_editor_interface().get_resource_filesystem().scan()
			return _ok("Editor filesystem scan started", {})
		"create-scene-asset":
			return _create_scene_asset(args)
		"create-material":
			return _create_material(args)
		"inject-action":
			return _inject_action(args)
		"release-action":
			return _release_action(args)
		"inject-key":
			return _inject_key(args)
		"inject-mouse-button":
			return _inject_mouse_button(args)
		"release-all-actions":
			return _release_all_actions()
		"list-controls":
			return _list_controls(args)
		"inspect-control":
			return _inspect_control(args)
		"create-control":
			return _create_control(args)
		"remove-control":
			return _remove_control(args)
		"set-control-property":
			return _set_control_property(args)
		"list-animation-players":
			return _list_animation_players(args)
		"inspect-animation":
			return _inspect_animation(args)
		"create-animation-player":
			return _create_animation_player(args)
		"create-animation":
			return _create_animation(args)
		"add-track":
			return _add_animation_track(args)
		"insert-key":
			return _insert_animation_key(args)
		"capture-screenshot":
			return _capture_screenshot(args)
		_:
			return _error_response("", command, "UNKNOWN_COMMAND", "Unknown bridge command: %s" % command)


func _status_payload() -> Dictionary:
	var editor := get_editor_interface()
	var root := editor.get_edited_scene_root()
	var selection := []
	for node in editor.get_selection().get_selected_nodes():
		selection.append(_serialize_node_summary(node))
	return {
		"bridgeVersion": BRIDGE_VERSION,
		"engineVersion": Engine.get_version_info(),
		"pluginEnabled": editor.is_plugin_enabled(PLUGIN_CONFIG_PATH),
		"isPlayingScene": editor.is_playing_scene(),
		"playingScene": editor.get_playing_scene(),
		"openScenes": editor.get_open_scenes(),
		"currentPath": editor.get_current_path(),
		"editedSceneRoot": _serialize_node_summary(root) if root != null else {},
		"selection": selection,
		"filesystemScanning": editor.get_resource_filesystem().is_scanning(),
	}


func _hierarchy(args: Dictionary) -> Dictionary:
	var root := _scene_root()
	if root == null:
		return _error_response("", "hierarchy", "NO_SCENE", "No edited scene is open")
	var depth := int(args.get("depth", 3))
	return _ok("Hierarchy loaded", {"hierarchy": _serialize_hierarchy(root, root, max(depth, 1), 0)})


func _find_nodes(args: Dictionary) -> Dictionary:
	var root := _scene_root()
	if root == null:
		return _error_response("", "find", "NO_SCENE", "No edited scene is open")
	var matches := []
	_collect_matching_nodes(root, root, args, matches)
	return _ok("Found %d matching node(s)" % matches.size(), {"nodes": matches})


func _inspect_node(args: Dictionary) -> Dictionary:
	var node := _resolve_node(str(args.get("path", "")))
	if node == null:
		return _error_response("", "inspect", "NODE_NOT_FOUND", "Node not found")
	return _ok("Node inspected", {"node": _serialize_node_details(node)})


func _get_selection() -> Dictionary:
	var nodes := []
	for node in get_editor_interface().get_selection().get_selected_nodes():
		nodes.append(_serialize_node_details(node))
	return _ok("Selection loaded", {"nodes": nodes})


func _list_scenes(args: Dictionary) -> Dictionary:
	var items := _collect_project_files("res://", str(args.get("filter", "")), [".tscn", ".scn"])
	return _ok("Listed %d scene asset(s)" % items.size(), {"assets": items})


func _list_assets(args: Dictionary) -> Dictionary:
	var items := _collect_project_files("res://", str(args.get("filter", "")), [])
	return _ok("Listed %d asset(s)" % items.size(), {"assets": items})


func _save_scene(args: Dictionary) -> Dictionary:
	var editor := get_editor_interface()
	var path := str(args.get("path", ""))
	if path.is_empty():
		editor.save_scene()
		return _ok("Saved current scene", _status_payload())
	editor.save_scene_as(path, true)
	return _ok("Saved current scene as %s" % path, _status_payload())


func _open_scene(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", ""))
	if path.is_empty():
		return _error_response("", "open-scene", "INVALID_ARGUMENT", "path is required")
	if not ResourceLoader.exists(path):
		return _error_response("", "open-scene", "SCENE_NOT_FOUND", "Scene does not exist: %s" % path)
	get_editor_interface().open_scene_from_path(path)
	if not _activate_scene_by_path(path):
		return _error_response("", "open-scene", "SCENE_NOT_ACTIVE", "Scene opened but could not be activated: %s" % path)
	return _ok("Opened scene %s" % path, _status_payload())


func _new_scene(args: Dictionary) -> Dictionary:
	var node_type := str(args.get("node_type", "Node2D"))
	var root = _instantiate_node_type(node_type)
	if root == null:
		return _error_response("", "new-scene", "INVALID_NODE_TYPE", "Unable to instantiate node type: %s" % node_type)
	root.name = str(args.get("name", "Root"))
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		root.queue_free()
		return _error_response("", "new-scene", "SCENE_PACK_FAILED", "Failed to pack temporary scene")
	var path := str(args.get("path", ""))
	if not path.is_empty():
		_ensure_res_parent_dir(path)
		var save_error := ResourceSaver.save(packed, path)
		root.queue_free()
		if save_error != OK:
			return _error_response("", "new-scene", "SCENE_SAVE_FAILED", "Failed to save scene: %s" % path)
		get_editor_interface().get_resource_filesystem().update_file(path)
		get_editor_interface().open_scene_from_path(path)
		if not _activate_scene_by_path(path):
			return _error_response("", "new-scene", "SCENE_NOT_ACTIVE", "Scene created but could not be activated: %s" % path)
		return _ok("Created scene %s" % path, _status_payload())
	root.queue_free()
	return _error_response("", "new-scene", "INVALID_ARGUMENT", "path is required for new-scene")


func _reload_scene(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", ""))
	if path.is_empty():
		var root := _scene_root()
		if root == null or root.scene_file_path.is_empty():
			return _error_response("", "reload-scene", "NO_SCENE", "No saved scene is open")
		path = root.scene_file_path
	get_editor_interface().reload_scene_from_path(path)
	if not _activate_scene_by_path(path):
		return _error_response("", "reload-scene", "SCENE_NOT_ACTIVE", "Scene reloaded but could not be activated: %s" % path)
	return _ok("Reloaded scene %s" % path, _status_payload())


func _create_node(args: Dictionary) -> Dictionary:
	var parent := _resolve_parent(str(args.get("parent", "")))
	if parent == null:
		return _error_response("", "create-node", "PARENT_NOT_FOUND", "Parent node not found")
	var node_type := str(args.get("node_type", "Node"))
	var node = _instantiate_node_type(node_type)
	if node == null:
		return _error_response("", "create-node", "INVALID_NODE_TYPE", "Unable to instantiate node type: %s" % node_type)
	node.name = str(args.get("name", node_type))
	parent.add_child(node)
	node.owner = _scene_root()
	_apply_transform(node, args)
	_mark_unsaved()
	return _ok("Created node %s" % node.name, {"node": _serialize_node_details(node)})


func _instantiate_scene(args: Dictionary) -> Dictionary:
	var parent := _resolve_parent(str(args.get("parent", "")))
	if parent == null:
		return _error_response("", "instantiate-scene", "PARENT_NOT_FOUND", "Parent node not found")
	var scene_path := str(args.get("scene", ""))
	if scene_path.is_empty():
		return _error_response("", "instantiate-scene", "INVALID_ARGUMENT", "scene is required")
	var packed = ResourceLoader.load(scene_path)
	if packed == null or not (packed is PackedScene):
		return _error_response("", "instantiate-scene", "SCENE_NOT_FOUND", "Unable to load scene: %s" % scene_path)
	var node = packed.instantiate()
	if node == null:
		return _error_response("", "instantiate-scene", "SCENE_INSTANTIATE_FAILED", "Failed to instantiate scene: %s" % scene_path)
	parent.add_child(node)
	node.owner = _scene_root()
	if args.has("name"):
		node.name = str(args.get("name", node.name))
	_apply_transform(node, args)
	_mark_unsaved()
	return _ok("Instantiated scene %s" % scene_path, {"node": _serialize_node_details(node)})


func _destroy_node(args: Dictionary) -> Dictionary:
	var node := _resolve_node(str(args.get("path", "")))
	if node == null or node == _scene_root():
		return _error_response("", "destroy-node", "NODE_NOT_FOUND", "Node not found or root deletion blocked")
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.queue_free()
	_mark_unsaved()
	return _ok("Destroyed node", {})


func _duplicate_node(args: Dictionary) -> Dictionary:
	var node := _resolve_node(str(args.get("path", "")))
	if node == null:
		return _error_response("", "duplicate-node", "NODE_NOT_FOUND", "Node not found")
	var parent := node.get_parent()
	if parent == null:
		return _error_response("", "duplicate-node", "INVALID_STATE", "Node has no parent")
	var clone = node.duplicate()
	if clone == null:
		return _error_response("", "duplicate-node", "DUPLICATE_FAILED", "Failed to duplicate node")
	parent.add_child(clone)
	clone.owner = _scene_root()
	if args.has("name"):
		clone.name = str(args.get("name", clone.name))
	_mark_unsaved()
	return _ok("Duplicated node", {"node": _serialize_node_details(clone)})


func _set_transform(args: Dictionary) -> Dictionary:
	var node := _resolve_node(str(args.get("path", "")))
	if node == null:
		return _error_response("", "set-transform", "NODE_NOT_FOUND", "Node not found")
	_apply_transform(node, args)
	_mark_unsaved()
	return _ok("Updated node transform", {"node": _serialize_node_details(node)})


func _set_parent(args: Dictionary) -> Dictionary:
	var node := _resolve_node(str(args.get("path", "")))
	var parent := _resolve_parent(str(args.get("parent", "")))
	if node == null or parent == null or node == _scene_root():
		return _error_response("", "set-parent", "NODE_NOT_FOUND", "Node or parent not found")
	var old_parent := node.get_parent()
	if old_parent != null:
		old_parent.remove_child(node)
	parent.add_child(node)
	node.owner = _scene_root()
	_mark_unsaved()
	return _ok("Updated node parent", {"node": _serialize_node_details(node)})


func _set_active(args: Dictionary) -> Dictionary:
	var node := _resolve_node(str(args.get("path", "")))
	if node == null:
		return _error_response("", "set-active", "NODE_NOT_FOUND", "Node not found")
	var active := bool(args.get("active", true))
	node.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if node is CanvasItem:
		node.visible = active
	_mark_unsaved()
	return _ok("Updated node active state", {"node": _serialize_node_details(node), "active": active})


func _set_property(args: Dictionary) -> Dictionary:
	var node := _resolve_node(str(args.get("path", "")))
	var property := str(args.get("property", ""))
	if node == null:
		return _error_response("", "set-property", "NODE_NOT_FOUND", "Node not found")
	if property.is_empty():
		return _error_response("", "set-property", "INVALID_ARGUMENT", "property is required")
	node.set(property, args.get("value"))
	_mark_unsaved()
	return _ok("Updated property %s" % property, {"node": _serialize_node_details(node)})


func _add_script(args: Dictionary) -> Dictionary:
	var node := _resolve_node(str(args.get("path", "")))
	var script_path := str(args.get("script_path", ""))
	if node == null:
		return _error_response("", "add-script", "NODE_NOT_FOUND", "Node not found")
	if script_path.is_empty():
		return _error_response("", "add-script", "INVALID_ARGUMENT", "script_path is required")
	var script = ResourceLoader.load(script_path)
	if script == null:
		return _error_response("", "add-script", "SCRIPT_NOT_FOUND", "Unable to load script: %s" % script_path)
	node.set_script(script)
	_mark_unsaved()
	return _ok("Attached script %s" % script_path, {"node": _serialize_node_details(node)})


func _select_node(args: Dictionary) -> Dictionary:
	var node := _resolve_node(str(args.get("path", "")))
	if node == null:
		return _error_response("", "select-node", "NODE_NOT_FOUND", "Node not found")
	var selection := get_editor_interface().get_selection()
	selection.clear()
	selection.add_node(node)
	get_editor_interface().edit_node(node)
	return _ok("Selected node", {"node": _serialize_node_details(node)})


func _create_scene_asset(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", ""))
	if path.is_empty():
		return _error_response("", "create-scene-asset", "INVALID_ARGUMENT", "path is required")
	var source_path := str(args.get("source", ""))
	var scene := PackedScene.new()
	var pack_error := OK
	if not source_path.is_empty():
		var node := _resolve_node(source_path)
		if node == null:
			return _error_response("", "create-scene-asset", "NODE_NOT_FOUND", "Source node not found")
		pack_error = scene.pack(node)
	else:
		var node_type := str(args.get("node_type", "Node2D"))
		var temp_root = _instantiate_node_type(node_type)
		if temp_root == null:
			return _error_response("", "create-scene-asset", "INVALID_NODE_TYPE", "Unable to instantiate node type: %s" % node_type)
		temp_root.name = str(args.get("name", "Root"))
		pack_error = scene.pack(temp_root)
		temp_root.queue_free()
	if pack_error != OK:
		return _error_response("", "create-scene-asset", "SCENE_PACK_FAILED", "Failed to pack scene asset")
	_ensure_res_parent_dir(path)
	var save_error := ResourceSaver.save(scene, path)
	if save_error != OK:
		return _error_response("", "create-scene-asset", "SCENE_SAVE_FAILED", "Failed to save scene: %s" % path)
	get_editor_interface().get_resource_filesystem().update_file(path)
	return _ok("Created scene asset %s" % path, {"path": path})


func _create_material(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", ""))
	if path.is_empty():
		return _error_response("", "create-material", "INVALID_ARGUMENT", "path is required")
	var material_type := str(args.get("material_type", "StandardMaterial3D"))
	var material: Resource = null
	match material_type:
		"CanvasItemMaterial":
			material = CanvasItemMaterial.new()
		"ShaderMaterial":
			material = ShaderMaterial.new()
			var shader_path := str(args.get("shader", ""))
			if not shader_path.is_empty():
				var shader = ResourceLoader.load(shader_path)
				if shader != null:
					material.shader = shader
		_:
			material = StandardMaterial3D.new()
	_ensure_res_parent_dir(path)
	var save_error := ResourceSaver.save(material, path)
	if save_error != OK:
		return _error_response("", "create-material", "MATERIAL_SAVE_FAILED", "Failed to save material: %s" % path)
	get_editor_interface().get_resource_filesystem().update_file(path)
	return _ok("Created material %s" % path, {"path": path, "type": material_type})


func _inject_action(args: Dictionary) -> Dictionary:
	var input_action := str(args.get("input_action", ""))
	if input_action.is_empty():
		return _error_response("", "inject-action", "INVALID_ARGUMENT", "input_action is required")
	var known_action := _project_input_action_exists(input_action)
	_ensure_input_action_available(input_action, known_action)
	var strength := clampf(float(args.get("strength", 1.0)), 0.0, 1.0)
	Input.action_press(input_action, strength)
	return _ok("Injected action %s" % input_action, {
		"inputAction": input_action,
		"knownAction": known_action,
		"pressed": Input.is_action_pressed(input_action),
		"strength": Input.get_action_strength(input_action),
	})


func _release_action(args: Dictionary) -> Dictionary:
	var input_action := str(args.get("input_action", ""))
	if input_action.is_empty():
		return _error_response("", "release-action", "INVALID_ARGUMENT", "input_action is required")
	var known_action := _project_input_action_exists(input_action)
	_ensure_input_action_available(input_action, known_action)
	Input.action_release(input_action)
	return _ok("Released action %s" % input_action, {
		"inputAction": input_action,
		"knownAction": known_action,
		"pressed": Input.is_action_pressed(input_action),
		"strength": Input.get_action_strength(input_action),
	})


func _inject_key(args: Dictionary) -> Dictionary:
	var keycode := int(args.get("keycode", 0))
	if keycode <= 0:
		return _error_response("", "inject-key", "INVALID_ARGUMENT", "keycode is required")
	var event := InputEventKey.new()
	event.keycode = keycode
	event.unicode = int(args.get("unicode", 0))
	event.pressed = bool(args.get("pressed", true))
	Input.parse_input_event(event)
	return _ok("Injected key event", {
		"keycode": keycode,
		"pressed": event.pressed,
		"isPressed": Input.is_key_pressed(keycode),
	})


func _inject_mouse_button(args: Dictionary) -> Dictionary:
	var button_index := int(args.get("button_index", 0))
	if button_index <= 0:
		return _error_response("", "inject-mouse-button", "INVALID_ARGUMENT", "button_index is required")
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = bool(args.get("pressed", true))
	var position = args.get("position", [])
	if position is Array and position.size() >= 2:
		event.position = Vector2(float(position[0]), float(position[1]))
		event.global_position = event.position
	Input.parse_input_event(event)
	return _ok("Injected mouse button event", {
		"buttonIndex": button_index,
		"pressed": event.pressed,
		"isPressed": Input.is_mouse_button_pressed(button_index),
		"position": [event.position.x, event.position.y],
	})


func _release_all_actions() -> Dictionary:
	var released := []
	for input_action in InputMap.get_actions():
		Input.action_release(input_action)
		released.append(str(input_action))
	return _ok("Released %d action(s)" % released.size(), {"actions": released})


func _list_controls(_args: Dictionary) -> Dictionary:
	var root := _scene_root()
	if root == null:
		return _error_response("", "list-controls", "NO_SCENE", "No edited scene is open")
	var controls := []
	_collect_controls(root, controls)
	return _ok("Listed %d control node(s)" % controls.size(), {"controls": controls})


func _inspect_control(args: Dictionary) -> Dictionary:
	var node := _resolve_node(str(args.get("path", "")))
	if node == null or not (node is Control):
		return _error_response("", "inspect-control", "CONTROL_NOT_FOUND", "Control node not found")
	return _ok("Control inspected", {"control": _serialize_control_details(node)})


func _create_control(args: Dictionary) -> Dictionary:
	var parent := _resolve_parent(str(args.get("parent", "")))
	if parent == null:
		return _error_response("", "create-control", "PARENT_NOT_FOUND", "Parent node not found")
	var node_type := str(args.get("node_type", "Control"))
	var node = _instantiate_node_type(node_type)
	if node == null or not (node is Control):
		return _error_response("", "create-control", "INVALID_NODE_TYPE", "Unable to instantiate Control node type: %s" % node_type)
	node.name = str(args.get("name", node_type))
	parent.add_child(node)
	node.owner = _scene_root()
	_apply_transform(node, args)
	_apply_control_fields(node, args)
	_mark_unsaved()
	return _ok("Created control %s" % node.name, {"control": _serialize_control_details(node)})


func _remove_control(args: Dictionary) -> Dictionary:
	var node := _resolve_node(str(args.get("path", "")))
	if node == null or not (node is Control) or node == _scene_root():
		return _error_response("", "remove-control", "CONTROL_NOT_FOUND", "Control node not found or root deletion blocked")
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.queue_free()
	_mark_unsaved()
	return _ok("Removed control", {})


func _set_control_property(args: Dictionary) -> Dictionary:
	var node := _resolve_node(str(args.get("path", "")))
	var property := str(args.get("property", ""))
	if node == null or not (node is Control):
		return _error_response("", "set-control-property", "CONTROL_NOT_FOUND", "Control node not found")
	if property.is_empty():
		return _error_response("", "set-control-property", "INVALID_ARGUMENT", "property is required")
	node.set(property, _coerce_property_value(property, args.get("value")))
	_mark_unsaved()
	return _ok("Updated control property %s" % property, {"control": _serialize_control_details(node)})


func _list_animation_players(_args: Dictionary) -> Dictionary:
	var root := _scene_root()
	if root == null:
		return _error_response("", "list-animation-players", "NO_SCENE", "No edited scene is open")
	var players := []
	_collect_nodes_by_class(root, "AnimationPlayer", players)
	var payload := []
	for player in players:
		payload.append(_serialize_animation_player(player))
	return _ok("Listed %d animation player(s)" % payload.size(), {"players": payload})


func _inspect_animation(args: Dictionary) -> Dictionary:
	var player := _resolve_animation_player(str(args.get("player_path", "")))
	if player == null:
		return _error_response("", "inspect-animation", "PLAYER_NOT_FOUND", "AnimationPlayer not found")
	var animation_name := str(args.get("animation", ""))
	if animation_name.is_empty():
		return _error_response("", "inspect-animation", "INVALID_ARGUMENT", "animation is required")
	var animation = _find_animation(player, animation_name)
	if animation == null:
		return _error_response("", "inspect-animation", "ANIMATION_NOT_FOUND", "Animation not found: %s" % animation_name)
	return _ok("Animation inspected", {"player": _serialize_animation_player(player), "animation": _serialize_animation_details(animation_name, animation)})


func _create_animation_player(args: Dictionary) -> Dictionary:
	var parent := _resolve_parent(str(args.get("parent", "")))
	if parent == null:
		return _error_response("", "create-animation-player", "PARENT_NOT_FOUND", "Parent node not found")
	var player := AnimationPlayer.new()
	player.name = str(args.get("name", "AnimationPlayer"))
	parent.add_child(player)
	player.owner = _scene_root()
	_mark_unsaved()
	return _ok("Created animation player %s" % player.name, {"player": _serialize_animation_player(player)})


func _create_animation(args: Dictionary) -> Dictionary:
	var player := _resolve_animation_player(str(args.get("player_path", "")))
	if player == null:
		return _error_response("", "create-animation", "PLAYER_NOT_FOUND", "AnimationPlayer not found")
	var animation_name := str(args.get("animation", ""))
	if animation_name.is_empty():
		return _error_response("", "create-animation", "INVALID_ARGUMENT", "animation is required")
	if _find_animation(player, animation_name) != null:
		return _error_response("", "create-animation", "ANIMATION_EXISTS", "Animation already exists: %s" % animation_name)
	var library = _ensure_default_animation_library(player)
	if library == null:
		return _error_response("", "create-animation", "LIBRARY_ERROR", "Unable to create the default animation library")
	var animation := Animation.new()
	animation.length = maxf(float(args.get("length", 0.5)), 0.01)
	animation.loop_mode = Animation.LOOP_LINEAR if bool(args.get("loop", false)) else Animation.LOOP_NONE
	var add_error := library.add_animation(animation_name, animation)
	if add_error != OK:
		return _error_response("", "create-animation", "ANIMATION_CREATE_FAILED", "Failed to create animation: %s" % animation_name)
	_mark_unsaved()
	return _ok("Created animation %s" % animation_name, {"player": _serialize_animation_player(player), "animation": _serialize_animation_details(animation_name, animation)})


func _add_animation_track(args: Dictionary) -> Dictionary:
	var player := _resolve_animation_player(str(args.get("player_path", "")))
	if player == null:
		return _error_response("", "add-track", "PLAYER_NOT_FOUND", "AnimationPlayer not found")
	var animation_name := str(args.get("animation", ""))
	var target_node := _resolve_node(str(args.get("target_path", "")))
	var property := str(args.get("property", ""))
	if animation_name.is_empty() or target_node == null or property.is_empty():
		return _error_response("", "add-track", "INVALID_ARGUMENT", "animation, target_path, and property are required")
	var animation = _find_animation(player, animation_name)
	if animation == null:
		return _error_response("", "add-track", "ANIMATION_NOT_FOUND", "Animation not found: %s" % animation_name)
	var relative_path := str(player.get_path_to(target_node))
	if relative_path.is_empty():
		relative_path = "."
	var track_path := "%s:%s" % [relative_path, property]
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath(track_path))
	_mark_unsaved()
	return _ok("Added animation track", {
		"track": track,
		"trackPath": track_path,
		"animation": _serialize_animation_details(animation_name, animation),
	})


func _insert_animation_key(args: Dictionary) -> Dictionary:
	var player := _resolve_animation_player(str(args.get("player_path", "")))
	if player == null:
		return _error_response("", "insert-key", "PLAYER_NOT_FOUND", "AnimationPlayer not found")
	var animation_name := str(args.get("animation", ""))
	var track := int(args.get("track", -1))
	if animation_name.is_empty() or track < 0:
		return _error_response("", "insert-key", "INVALID_ARGUMENT", "animation and track are required")
	var animation = _find_animation(player, animation_name)
	if animation == null:
		return _error_response("", "insert-key", "ANIMATION_NOT_FOUND", "Animation not found: %s" % animation_name)
	if track >= animation.get_track_count():
		return _error_response("", "insert-key", "TRACK_NOT_FOUND", "Track index is out of range")
	var track_path := str(animation.track_get_path(track))
	var value = _coerce_animation_value(track_path, args.get("value"))
	var time_sec := maxf(float(args.get("time", 0.0)), 0.0)
	animation.track_insert_key(track, time_sec, value)
	_mark_unsaved()
	return _ok("Inserted animation key", {
		"track": track,
		"trackPath": track_path,
		"time": time_sec,
		"keyCount": animation.track_get_key_count(track),
		"animation": _serialize_animation_details(animation_name, animation),
	})


func _capture_screenshot(args: Dictionary) -> Dictionary:
	var output_path := str(args.get("path", ".qq/state/screenshots/godot-editor.png"))
	var absolute_path := _resolve_output_path(output_path)
	var viewport := get_editor_interface().get_base_control().get_viewport()
	var texture = viewport.get_texture()
	if texture == null:
		return _error_response("", "capture-screenshot", "CAPTURE_UNAVAILABLE", "Editor viewport texture is not available")
	var image := texture.get_image()
	if image == null or image.get_width() <= 0 or image.get_height() <= 0:
		return _error_response("", "capture-screenshot", "CAPTURE_UNAVAILABLE", "Editor viewport image is empty")
	var width := int(args.get("width", 0))
	var height := int(args.get("height", 0))
	if width > 0 and height > 0 and (image.get_width() != width or image.get_height() != height):
		image.resize(width, height, Image.INTERPOLATE_BILINEAR)
	_ensure_dir(absolute_path.get_base_dir())
	var save_error := image.save_png(absolute_path)
	if save_error != OK:
		return _error_response("", "capture-screenshot", "CAPTURE_SAVE_FAILED", "Failed to save screenshot: %s" % output_path)
	return _ok("Captured screenshot", {
		"path": output_path,
		"absolutePath": absolute_path,
		"size": [image.get_width(), image.get_height()],
	})


func _scene_root() -> Node:
	return get_editor_interface().get_edited_scene_root()


func _activate_scene_by_path(path: String) -> bool:
	var editor := get_editor_interface()
	for root in editor.get_open_scene_roots():
		if root == null:
			continue
		if root.scene_file_path != path:
			continue
		_activate_scene_root(root)
		var current := editor.get_edited_scene_root()
		return current != null and current.scene_file_path == path
	var current := editor.get_edited_scene_root()
	return current != null and current.scene_file_path == path


func _activate_scene_root(root: Node) -> void:
	if root == null:
		return
	var editor := get_editor_interface()
	var selection := editor.get_selection()
	selection.clear()
	selection.add_node(root)
	editor.edit_node(root)


func _resolve_animation_player(path: String) -> AnimationPlayer:
	var node := _resolve_node(path)
	if node == null and path.is_empty():
		var root := _scene_root()
		if root != null:
			var players := []
			_collect_nodes_by_class(root, "AnimationPlayer", players)
			if not players.is_empty():
				node = players[0]
	if node is AnimationPlayer:
		return node
	return null


func _find_animation(player: AnimationPlayer, animation_name: String) -> Animation:
	var library = player.get_animation_library("")
	if library == null or not library.has_animation(animation_name):
		return null
	return library.get_animation(animation_name)


func _resolve_parent(path: String) -> Node:
	if path.is_empty():
		return _scene_root()
	return _resolve_node(path)


func _resolve_node(path: String) -> Node:
	var root := _scene_root()
	if root == null:
		return null
	var trimmed := path.strip_edges()
	if trimmed.is_empty() or trimmed == "." or trimmed == root.name:
		return root
	var node = root.get_node_or_null(NodePath(trimmed))
	if node != null:
		return node
	for candidate in root.find_children("*", "", true, false):
		if _relative_node_path(candidate, root) == trimmed:
			return candidate
	return null


func _instantiate_node_type(node_type: String) -> Node:
	if node_type.is_empty():
		return Node.new()
	if ClassDB.class_exists(node_type) and ClassDB.can_instantiate(node_type):
		var node = ClassDB.instantiate(node_type)
		if node is Node:
			return node
	return null


func _apply_transform(node: Node, args: Dictionary) -> void:
	if node is Node2D:
		if args.has("position") and args["position"] is Array and args["position"].size() >= 2:
			node.position = Vector2(float(args["position"][0]), float(args["position"][1]))
		if args.has("rotation") and args["rotation"] is Array and args["rotation"].size() >= 1:
			node.rotation_degrees = float(args["rotation"][0])
		if args.has("scale") and args["scale"] is Array and args["scale"].size() >= 2:
			node.scale = Vector2(float(args["scale"][0]), float(args["scale"][1]))
	elif node is Node3D:
		if args.has("position") and args["position"] is Array and args["position"].size() >= 3:
			node.position = Vector3(float(args["position"][0]), float(args["position"][1]), float(args["position"][2]))
		if args.has("rotation") and args["rotation"] is Array and args["rotation"].size() >= 3:
			node.rotation_degrees = Vector3(float(args["rotation"][0]), float(args["rotation"][1]), float(args["rotation"][2]))
		if args.has("scale") and args["scale"] is Array and args["scale"].size() >= 3:
			node.scale = Vector3(float(args["scale"][0]), float(args["scale"][1]), float(args["scale"][2]))
	elif node is Control:
		if args.has("position") and args["position"] is Array and args["position"].size() >= 2:
			node.position = Vector2(float(args["position"][0]), float(args["position"][1]))
		if args.has("scale") and args["scale"] is Array and args["scale"].size() >= 2:
			node.scale = Vector2(float(args["scale"][0]), float(args["scale"][1]))


func _apply_control_fields(node: Control, args: Dictionary) -> void:
	if args.has("text") and _node_has_property(node, "text"):
		node.set("text", str(args.get("text", "")))
	if args.has("size") and args["size"] is Array and args["size"].size() >= 2:
		node.size = Vector2(float(args["size"][0]), float(args["size"][1]))
	if args.has("custom_minimum_size") and args["custom_minimum_size"] is Array and args["custom_minimum_size"].size() >= 2:
		node.custom_minimum_size = Vector2(float(args["custom_minimum_size"][0]), float(args["custom_minimum_size"][1]))


func _collect_controls(node: Node, out: Array) -> void:
	if node is Control:
		out.append(_serialize_control_summary(node))
	for child in node.get_children():
		_collect_controls(child, out)


func _collect_nodes_by_class(node: Node, class_id: String, out: Array) -> void:
	if node.is_class(class_id):
		out.append(node)
	for child in node.get_children():
		_collect_nodes_by_class(child, class_id, out)


func _collect_matching_nodes(node: Node, root: Node, args: Dictionary, out: Array) -> void:
	if _matches_node(node, args):
		out.append(_serialize_node_summary(node))
	for child in node.get_children():
		_collect_matching_nodes(child, root, args, out)


func _matches_node(node: Node, args: Dictionary) -> bool:
	var name_filter := str(args.get("name", ""))
	if not name_filter.is_empty() and name_filter.to_lower() not in node.name.to_lower():
		return false
	var type_filter := str(args.get("type", ""))
	if not type_filter.is_empty() and type_filter != node.get_class():
		return false
	var group_filter := str(args.get("group", ""))
	if not group_filter.is_empty() and not node.is_in_group(group_filter):
		return false
	var path_filter := str(args.get("path", ""))
	if not path_filter.is_empty() and path_filter.to_lower() not in _relative_node_path(node, _scene_root()).to_lower():
		return false
	var generic_filter := str(args.get("filter", ""))
	if not generic_filter.is_empty():
		var blob := "%s %s %s" % [node.name, node.get_class(), _relative_node_path(node, _scene_root())]
		if generic_filter.to_lower() not in blob.to_lower():
			return false
	return true


func _serialize_hierarchy(node: Node, root: Node, max_depth: int, depth: int) -> Dictionary:
	var payload := _serialize_node_summary(node)
	if depth >= max_depth:
		payload["children"] = []
		return payload
	var children := []
	for child in node.get_children():
		children.append(_serialize_hierarchy(child, root, max_depth, depth + 1))
	payload["children"] = children
	return payload


func _serialize_node_summary(node: Node) -> Dictionary:
	if node == null:
		return {}
	var root := _scene_root()
	return {
		"name": node.name,
		"type": node.get_class(),
		"path": _relative_node_path(node, root) if root != null else str(node.get_path()),
		"childCount": node.get_child_count(),
	}


func _serialize_node_details(node: Node) -> Dictionary:
	var payload := _serialize_node_summary(node)
	payload["sceneFilePath"] = node.scene_file_path
	payload["owner"] = _relative_node_path(node.owner, _scene_root()) if node.owner != null and _scene_root() != null else ""
	payload["processMode"] = int(node.process_mode)
	payload["visible"] = node.visible if node is CanvasItem else null
	payload["groups"] = node.get_groups()
	if node is Node2D:
		payload["position"] = [node.position.x, node.position.y]
		payload["rotationDegrees"] = node.rotation_degrees
		payload["scale"] = [node.scale.x, node.scale.y]
	elif node is Node3D:
		payload["position"] = [node.position.x, node.position.y, node.position.z]
		payload["rotationDegrees"] = [node.rotation_degrees.x, node.rotation_degrees.y, node.rotation_degrees.z]
		payload["scale"] = [node.scale.x, node.scale.y, node.scale.z]
	elif node is Control:
		payload["position"] = [node.position.x, node.position.y]
		payload["scale"] = [node.scale.x, node.scale.y]
	return payload


func _serialize_control_summary(node: Control) -> Dictionary:
	var payload := _serialize_node_summary(node)
	payload["text"] = str(node.get("text")) if _node_has_property(node, "text") else ""
	payload["size"] = [node.size.x, node.size.y]
	return payload


func _serialize_control_details(node: Control) -> Dictionary:
	var payload := _serialize_node_details(node)
	payload["size"] = [node.size.x, node.size.y]
	payload["customMinimumSize"] = [node.custom_minimum_size.x, node.custom_minimum_size.y]
	payload["anchors"] = [node.anchor_left, node.anchor_top, node.anchor_right, node.anchor_bottom]
	payload["offsets"] = [node.offset_left, node.offset_top, node.offset_right, node.offset_bottom]
	payload["sizeFlagsHorizontal"] = node.size_flags_horizontal
	payload["sizeFlagsVertical"] = node.size_flags_vertical
	payload["text"] = str(node.get("text")) if _node_has_property(node, "text") else ""
	return payload


func _serialize_animation_player(player: AnimationPlayer) -> Dictionary:
	return {
		"name": player.name,
		"path": _relative_node_path(player, _scene_root()),
		"currentAnimation": str(player.current_animation),
		"libraries": player.get_animation_library_list(),
		"animations": player.get_animation_list(),
	}


func _serialize_animation_details(animation_name: String, animation: Animation) -> Dictionary:
	var tracks := []
	for track_idx in animation.get_track_count():
		tracks.append({
			"index": track_idx,
			"type": int(animation.track_get_type(track_idx)),
			"path": str(animation.track_get_path(track_idx)),
			"keyCount": animation.track_get_key_count(track_idx),
		})
	return {
		"name": animation_name,
		"length": animation.length,
		"loopMode": int(animation.loop_mode),
		"trackCount": animation.get_track_count(),
		"tracks": tracks,
	}


func _node_has_property(node: Object, property_name: String) -> bool:
	for item in node.get_property_list():
		if item is Dictionary and str(item.get("name", "")) == property_name:
			return true
	return false


func _ensure_default_animation_library(player: AnimationPlayer) -> AnimationLibrary:
	var library = player.get_animation_library("")
	if library != null:
		return library
	library = AnimationLibrary.new()
	if player.add_animation_library("", library) != OK:
		return null
	return library


func _project_input_action_exists(input_action: String) -> bool:
	return ProjectSettings.has_setting("input/%s" % input_action)


func _ensure_input_action_available(input_action: String, known_action: bool = false) -> void:
	if InputMap.has_action(input_action):
		return
	var deadzone := 0.2
	if known_action:
		var payload = ProjectSettings.get_setting("input/%s" % input_action)
		if payload is Dictionary:
			deadzone = float(payload.get("deadzone", deadzone))
	InputMap.add_action(input_action, deadzone)


func _coerce_property_value(property_name: String, value):
	match property_name:
		"position", "size", "custom_minimum_size", "scale":
			if value is Array and value.size() >= 2:
				return Vector2(float(value[0]), float(value[1]))
		"modulate", "self_modulate":
			if value is Array and value.size() >= 4:
				return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return value


func _coerce_animation_value(track_path: String, value):
	if value is Array:
		var lower := track_path.to_lower()
		if value.size() >= 4 and ("color" in lower or "modulate" in lower):
			return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
		if value.size() >= 3:
			return Vector3(float(value[0]), float(value[1]), float(value[2]))
		if value.size() >= 2:
			return Vector2(float(value[0]), float(value[1]))
	return value


func _relative_node_path(node: Node, root: Node) -> String:
	if node == null:
		return ""
	if root == null or node == root:
		return "."
	return str(root.get_path_to(node))


func _collect_project_files(base_path: String, filter_text: String, extensions: Array) -> Array:
	var items := []
	_collect_project_files_recursive(base_path, filter_text.to_lower(), extensions, items)
	return items


func _collect_project_files_recursive(current_path: String, filter_text: String, extensions: Array, items: Array) -> void:
	for directory in DirAccess.get_directories_at(current_path):
		if directory in [".git", ".godot", ".qq"]:
			continue
		_collect_project_files_recursive(_join_res(current_path, directory), filter_text, extensions, items)
	for filename in DirAccess.get_files_at(current_path):
		var res_path := _join_res(current_path, filename)
		if not extensions.is_empty():
			var matched := false
			for ext in extensions:
				if filename.ends_with(ext):
					matched = true
					break
			if not matched:
				continue
		if not filter_text.is_empty() and filter_text not in res_path.to_lower():
			continue
		items.append({"path": res_path, "type": get_editor_interface().get_resource_filesystem().get_file_type(res_path)})


func _build_state_payload(running: bool) -> Dictionary:
	var editor := get_editor_interface()
	return {
		"ok": true,
		"running": running,
		"pid": OS.get_process_id(),
		"bridgeVersion": BRIDGE_VERSION,
		"engineVersion": Engine.get_version_info(),
		"projectRoot": _project_root,
		"pluginEnabled": editor.is_plugin_enabled(PLUGIN_CONFIG_PATH),
		"lastHeartbeatUnix": Time.get_unix_time_from_system(),
		"requestCount": _request_count,
		"lastRequestId": _last_request_id,
		"lastCommand": _last_command,
		"openScenes": editor.get_open_scenes(),
		"playingScene": editor.get_playing_scene(),
		"selectionCount": editor.get_selection().get_selected_nodes().size(),
	}


func _write_state(running: bool) -> void:
	_write_json(_state_file, _build_state_payload(running))


func _ok(message: String, data: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"message": message,
		"data": data,
	}


func _error_response(request_id: String, command: String, category: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"requestId": request_id,
		"command": command,
		"category": category,
		"message": message,
		"data": {},
	}


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return {}
	var payload = JSON.parse_string(handle.get_as_text())
	return payload if payload is Dictionary else {}


func _write_json(path: String, payload: Dictionary) -> void:
	_ensure_dir(path.get_base_dir())
	var handle := FileAccess.open(path, FileAccess.WRITE)
	if handle == null:
		return
	handle.store_string(JSON.stringify(payload, "\t") + "\n")


func _append_console(level: String, event: String, payload: Dictionary) -> void:
	_ensure_dir(_console_file.get_base_dir())
	var record := {
		"timeUnix": Time.get_unix_time_from_system(),
		"level": level,
		"event": event,
		"payload": payload,
	}
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(_console_file) else FileAccess.WRITE
	var handle = FileAccess.open(_console_file, mode)
	if handle == null:
		return
	handle.seek_end()
	handle.store_string(JSON.stringify(record) + "\n")


func _ensure_dir(path: String) -> void:
	if path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(path)


func _resolve_output_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.begins_with("/"):
		return path
	return _join_path(_project_root, path)


func _ensure_res_parent_dir(res_path: String) -> void:
	var absolute := ProjectSettings.globalize_path(res_path).get_base_dir()
	DirAccess.make_dir_recursive_absolute(absolute)


func _mark_unsaved() -> void:
	get_editor_interface().mark_scene_as_unsaved()


func _join_path(base: String, relative: String) -> String:
	if base.ends_with("/"):
		return base + relative
	return base + "/" + relative


func _join_res(base: String, relative: String) -> String:
	if base.ends_with("/"):
		return base + relative
	return base + "/" + relative


func _normalize_dir(path: String) -> String:
	return path.rstrip("/")
