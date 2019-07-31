tool
extends Container

# When we load a file, keep a record of it so we can import it again with tweaked options.
var last_filename:String = ""

# Basic interface:
var editor_interface:EditorInterface
var open_file_dialog:FileDialog
var armature_name_input:LineEdit
var animation_player_name_input:LineEdit
var animation_name_input:LineEdit
# Tweaks
var show_tweaks_toggle:Button
var import_tweaks_group:VBoxContainer
var flip_x_rotation_checkbox:CheckBox
var flip_y_rotation_checkbox:CheckBox
var flip_z_rotation_checkbox:CheckBox
var axis_ordering_dropdown:OptionButton
# Import buttons
var import_button:Button
var reimport_button:Button

# Bones in the armature may not have the same name as in the BVH.
export(Dictionary) var bone_remapping:Dictionary = Dictionary()

# We keep in our bone_to_index_map a mapping of bone names (string) to an array of indices.  The index values are determined by this:
var channel_names = ["Xposition", "Yposition", "Zposition", "Xrotation", "Yrotation", "Zrotation"]
var channel_index_map = {
	"Xposition": 0,
	"Yposition": 1,
	"Zposition": 2,
	"Xrotation": 3,
	"Yrotation": 4,
	"Zrotation": 5
}
# Constants we use in our config.
const RIG_NAME = "rig_name"
const ANIM_PLAYER_NAME = "animation_player_name"
const NEW_ANIM_NAME = "new_animation_name"
var AXIS_ORDERING_NAMES = ["Native", "XYZ", "XZY", "YXZ", "YZX", "ZXY", "ZYX"]
enum AXIS_ORDERING { NATIVE = 0, XYZ, XZY, YXZ, YZX, ZXY, ZYX }
const AXIS_ORDER = "force_axis_ordering"

func _ready():
	open_file_dialog = get_node("FileDialog")
	open_file_dialog.add_filter("*.bvh ; Biovision Hierarchy")
	#open_file_dialog.mode = FileDialog.MODE_OPEN_FILE
	open_file_dialog.connect("file_selected", self, "_on_file_select")
	#get_editor_interface().get_base_control().add_child(open_file_dialog)
	
	armature_name_input = get_node("ArmatureNameInput")
	animation_player_name_input = get_node("AnimationPlayerNameInput")
	animation_name_input = get_node("AnimationNameInput")
	
	show_tweaks_toggle = get_node("ShowImportTweaks")
	show_tweaks_toggle.connect("toggled", self, "toggle_tweak_display")
	import_tweaks_group = get_node("ImportTweaks")
	flip_x_rotation_checkbox = get_node("ImportTweaks/FlipXInput")
	flip_y_rotation_checkbox = get_node("ImportTweaks/FlipYInput")
	flip_z_rotation_checkbox = get_node("ImportTweaks/FlipZInput")
	axis_ordering_dropdown = get_node("ImportTweaks/AxisOrderingOption")
	# TODO: I would rather not have to add options here.
	for i in AXIS_ORDERING.values():
		axis_ordering_dropdown.add_item(AXIS_ORDERING_NAMES[i], i)
	axis_ordering_dropdown.select(AXIS_ORDERING.NATIVE)
	
	import_button = get_node("ImportButton")
	import_button.connect("pressed", self, "_import")
	reimport_button = get_node("ReimportButton")
	reimport_button.connect("pressed", self, "_reimport")
	print("Signals connected.")

func toggle_tweak_display(toggle):
	import_tweaks_group.visible = show_tweaks_toggle.pressed

func get_config_data() -> Dictionary:
	# Reads from our UI and returns a dictionary of String -> Value.
	# This will do all of the node reading and accessing, next to ready.
	var config = Dictionary()
	config[RIG_NAME] = armature_name_input.text
	config[ANIM_PLAYER_NAME] = animation_player_name_input.text
	config[NEW_ANIM_NAME] = animation_name_input.text
	config[AXIS_ORDER] = axis_ordering_dropdown.selected
	return config

func _import():
	# Not open_file_dialog.show_modal(true)
	open_file_dialog.popup_centered()

func _reimport():
	_make_animation(last_filename)

func _on_file_select(file:String):
	if file == null or file == "":
		printerr("File is null")
		return
	last_filename = file
	_make_animation(file)
	reimport_button.disabled = false

#
# Ideally the material below should not touch UI.  Everything here is concerned with importing and manipulating BVH.
# The user interface and reading of config data should happen above here.
# Global configurations and tweaks should go into the config data.
#

func _make_animation(file:String):
	var config = get_config_data()
	var animation = load_bvh_filename(file)
	
	# Attach to the animation player.
	#var editor_selection = editor_interface.get_selection()
	#var selected_nodes = editor_selection.get_selected_nodes()
	#if len(selected_nodes) == 0:
	#	printerr("No nodes selected.  Please select the target animation player.")
	#	return
	var animation_player:AnimationPlayer = editor_interface.get_edited_scene_root().get_node(config[ANIM_PLAYER_NAME])
	if animation_player == null:
		printerr("AnimationPlayer is null.  Please ensure that the animation player to which you'd like to add is selected.")
		return
	
	var animation_name = config[NEW_ANIM_NAME]
	if animation_player.has_animation(animation_name):
		# TODO: Animation exists.  Prompt to overwrite.
		animation_player.remove_animation(animation_name)
	animation_player.add_animation(animation_name, animation)

func load_bvh_filename(filename:String) -> Animation:
	var config = get_config_data()
	
	#var plaintext = file.get_as_text()
	var file:File = File.new()
	if !file.file_exists(filename):
		printerr("Filename ", filename, " does not exist or cannot be accessed.")
	file.open(filename, File.READ) # "user://some_data"
	# file.store_string("lmao")
	var plaintext = file.get_as_text()
	
	var parsed_file = parse_bvh(plaintext)
	var hierarchy_lines = parsed_file[0]
	var motion_lines = parsed_file[1]
	
	var element_order_and_parent_map = parse_hierarchy(hierarchy_lines)
	var bone_names = element_order_and_parent_map[0]
	var bone_index_map:Dictionary = element_order_and_parent_map[1]
	
	return parse_motion(bone_names, bone_index_map, motion_lines)

func parse_bvh(fulltext:String) -> Array:
	# Split the fulltext by the elements from HIERARCHY to MOTION, and MOTION until the end of file.
	# Returns an array of [[hierarchy lines], [motion lines]]
	var lines = fulltext.split("\n", false)
	var hierarchy_lines:Array = Array()
	var motion_lines:Array = Array()
	var hierarchy_section = false
	var motion_section = false
	
	for line in lines:
		line = line.strip_edges()
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
	
	return [hierarchy_lines, motion_lines]

func parse_hierarchy(text:Array):# -> [Array, Dictionary]:
	# Given the plaintext HIERARCHY from HIERARCHY until MOTION,
	# pull out the bones AND the order of the features, 
	# returning a list of the order of the element names.
	# I.e., ["Armature:hips:rotation.x", "Armature:hips:rotation.y", ..., "Armature:hips/spine1/spine2/spine3:rotation.z"]
	# Will also return a map from bone to parent.
	# Will apply the bone remapping in bone_remapping if not null to the Element Names in the first return value.
	var bone_names:Array = Array()
	var bone_index_map:Dictionary = Dictionary() # Maps from bone name to array of [index of x trans (or -1), y trans, z trans, x rot, y rot, z rot]
		
	# NOTE: We are not keeping the structure of the hierarchy because we don't need it.
	# We only need the order of the channels and names of the bones.
	var line_index:int = 0
	var data_index:int = 0
	var current_bone = ""
	for line in text:
		var txt:String = line
		line = line.strip_edges()
		if line.begins_with("ROOT"):
			current_bone = line.split(" ", false)[1]
			bone_names.append(current_bone)
			bone_index_map[current_bone] = [-1, -1, -1, -1, -1, -1] # -1 means not in collection.
			print("Got bone: ", current_bone)
		elif line.begins_with("CHANNELS"):
			var data:Array = line.split(" ", false)
			var num_channels = data[1].to_int()
			for c in range(num_channels):
				var chan = data[2+c]
				bone_index_map[current_bone][channel_index_map[chan]] = data_index
				data_index += 1
				print("Channel: ", chan, " -> Idx: ", data_index)
		elif line.begins_with("JOINT"):
			current_bone = line.split(" ", false)[1]
			bone_names.append(current_bone)
			bone_index_map[current_bone] = [-1, -1, -1, -1, -1, -1] # -1 means not in collection.
			print("Got bone: ", current_bone)
	
	return [bone_names, bone_index_map]

# WARNING: This method will mutate the input text array.
func parse_motion(bone_names:Array, bone_index_map:Dictionary, text:Array, swap_yrot_zrot = true, invert_yup = false) -> Animation:
	var config = get_config_data()
	
	var num_frames = 0
	var timestep = 1.0/60.0 # TODO: Get from text.
	
	var rig_name = config[RIG_NAME]
	
	var read_header = true
	while read_header:
		read_header = false
		if text[0].begins_with("Frames:"):
			num_frames = text[0].split(" ")[1].to_int()
			text.pop_front()
			read_header = true
		if text[0].begins_with("Frame Time:"):
			timestep = text[0].split(" ")[2].to_float()
			text.pop_front()
			read_header = true
	# Timestep = 1/fps
	var animation:Animation = Animation.new()

	# Set the length of the animation to match the BVH length.
	# Create new tracks.
	var element_track_index_map:Dictionary = Dictionary()
	for i in range(len(bone_names)):
		var track_index = animation.add_track(Animation.TYPE_TRANSFORM)
		element_track_index_map[i] = track_index

	var step:int = 0
	for line in text:
		var values = line.split_floats(" ", false)
		for i in range(len(bone_names)):
			var bone_index_increment = 0
			var track_index = element_track_index_map[i]
			var bone_name = bone_names[i]
			
			var transformXIndex = bone_index_map[bone_name][0]
			var transformYIndex = bone_index_map[bone_name][1]
			var transformZIndex = bone_index_map[bone_name][2]
			var rotationXIndex = bone_index_map[bone_name][3]
			var rotationYIndex = bone_index_map[bone_name][4]
			var rotationZIndex = bone_index_map[bone_name][5]
			
			var translation = Vector3(0, 0, 0)
			if transformXIndex != -1:
				bone_index_increment += 1
				translation.x = values[transformXIndex]
			if transformYIndex != -1:
				bone_index_increment += 1
				translation.y = values[transformYIndex]
			if transformZIndex != -1:
				bone_index_increment += 1
				translation.z = values[transformZIndex]
			
			if swap_yrot_zrot and rotationZIndex != -1 and rotationYIndex != -1:
				var temp = values[rotationZIndex]
				values[rotationZIndex] = values[rotationYIndex]
				values[rotationYIndex] = temp
			
			var rotation = Basis()
			if rotationZIndex != -1:
				bone_index_increment += 1
				rotation = rotation.rotated(Vector3(0, 0, 1), deg2rad(values[rotationZIndex]))
			if rotationXIndex != -1:
				bone_index_increment += 1
				rotation = rotation.rotated(Vector3(1, 0, 0), deg2rad(values[rotationXIndex]))
			if rotationYIndex != -1:
				bone_index_increment += 1
				if invert_yup:
					rotation = rotation.rotated(Vector3(0, -1, 0), deg2rad(values[rotationYIndex]))
				else:
					rotation = rotation.rotated(Vector3(0, 1, 0), deg2rad(values[rotationYIndex]))

			# BVH uses vR = vYXZ rotation order. 
			
			#metarig:spine.006
			#animation.track_set_path(track_index, "Enemy:position.x")
			#animation.track_insert_key(track_index, step*timestep, values[i])
			animation.track_set_path(track_index, rig_name + ":" + bone_name)
			animation.transform_track_insert_key(track_index, step*timestep, translation, rotation.get_rotation_quat(), Vector3(1, 1, 1))
		step += 1
	
	return animation
