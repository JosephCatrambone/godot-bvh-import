tool
extends Container

var editor_interface:EditorInterface
var open_file_dialog:FileDialog
var armature_name_input:LineEdit
var animation_player_name_input:LineEdit
var animation_name_input:LineEdit
var import_button:Button

# Bones in the armature may not have the same name as in the BVH.
export(Dictionary) var bone_remapping:Dictionary = Dictionary()

func _ready():
	open_file_dialog = get_node("FileDialog")
	open_file_dialog.add_filter("*.bvh ; Biovision Hierarchy")
	#open_file_dialog.mode = FileDialog.MODE_OPEN_FILE
	open_file_dialog.connect("file_selected", self, "_finish_new_animation")
	#get_editor_interface().get_base_control().add_child(open_file_dialog)
	
	armature_name_input = get_node("ArmatureNameInput")
	animation_player_name_input = get_node("AnimationPlayerNameInput")
	animation_name_input = get_node("AnimationNameInput")
	import_button = get_node("ImportButton")
	import_button.connect("pressed", self, "_create_new_animation")
	print("Signals connected.")

func _create_new_animation():
	#open_file_dialog.show_modal(true)
	open_file_dialog.popup_centered()

func _finish_new_animation(file:String):
	if file == null or file == "":
		printerr("File is null")
		return
	var animation = load_bvh_filename(file)
	
	# Attach to the animation player.
	#var editor_selection = editor_interface.get_selection()
	#var selected_nodes = editor_selection.get_selected_nodes()
	#if len(selected_nodes) == 0:
	#	printerr("No nodes selected.  Please select the target animation player.")
	#	return
	var animation_player:AnimationPlayer = editor_interface.get_edited_scene_root().get_node(animation_player_name_input.text)
	if animation_player == null:
		printerr("AnimationPlayer is null.  Please ensure that the animation player to which you'd like to add is selected.")
		return
	
	var animation_name = animation_name_input.text
	if animation_player.has_animation(animation_name):
		# TODO: Animation exists.  Prompt to overwrite.
		animation_player.remove_animation(animation_name)
	animation_player.add_animation(animation_name, animation)

func load_bvh_file(file:File) -> Animation:
	var plaintext = file.get_as_text()
	return parse_bvh(plaintext)

func load_bvh_filename(filename:String) -> Animation:
	var file:File = File.new()
	if !file.file_exists(filename):
		printerr("Filename ", filename, " does not exist or cannot be accessed.")
	file.open(filename, File.READ) # "user://some_data"
	# file.store_string("lmao")
	var plaintext = file.get_as_text()
	return parse_bvh(plaintext)

func parse_bvh(fulltext:String) -> Animation:
	# Split the fulltext by the elements from HIERARCHY to MOTION, and MOTION until the end of file.
	var lines = fulltext.split("\n", false)
	var hierarchy_lines:Array = Array()
	var motion_lines:Array = Array()
	var hierarchy_section = false
	var motion_section = false
	
	
	for line in lines:
		# As written, we'll skip the 'hierarchy' and 'motion' lines.
		if line.begins_with("HIERARCHY"):
			hierarchy_section = true
			motion_section = false
			continue
		elif line.begins_with("MOTION"):
			motion_section = true
			hierarchy_section = false
			continue
		
		if hierarchy_section:
			hierarchy_lines.append(line)
		elif motion_section:
			motion_lines.append(line)
	
	var element_order_and_parent_map = parse_hierarchy(hierarchy_lines)
	var element_order:Array = element_order_and_parent_map[0]
	var parent_map:Dictionary = element_order_and_parent_map[1]
	return parse_motion(element_order, parent_map, 60.0, motion_lines)

func parse_hierarchy(text:Array):# -> [Array, Dictionary]:
	# Given the plaintext HIERARCHY from HIERARCHY until MOTION,
	# pull out the bones AND the order of the features, 
	# returning a list of the order of the element names.
	# I.e., ["Armature:hips:rotation.x", "Armature:hips:rotation.y", ..., "Armature:hips/spine1/spine2/spine3:rotation.z"]
	# Will also return a map from bone to parent.
	# Will apply the bone remapping in bone_remapping if not null to the Element Names in the first return value.
	var element_ordering = Array()
	var parent = Dictionary()
	
	return [element_ordering, parent]

func parse_motion(element_order:Array, parent_map:Dictionary, timestep:float, text:Array) -> Animation:
	# Timestep = 1/fps
	var animation:Animation = Animation.new()
	# Set the length of the animation to match the BVH length.
	var element_track_index_map:Dictionary = Dictionary()
	for i in range(len(element_order)):
		#var track_index = animation.add_track(Animation.TYPE_VALUE)
		var track_index = animation.add_track(Animation.TYPE_TRANSFORM)
		element_track_index_map[i] = track_index
	var step:int = 0
	for line in text:
		var values = line.split_floats(" ", false)
		for i in range(len(element_order)):
			var track_index = element_track_index_map[i]
			var track_name = element_order[i]
			animation.track_set_path(track_index, "Enemy:position.x")
			animation.track_insert_key(track_index, step*timestep, values[i])
			#animation.track_insert_key(track_index, 0.5, 100)
		step += 1
	
	return animation
