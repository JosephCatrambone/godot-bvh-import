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
var reverse_axis_order:CheckBox
var source_coordinate_system_dropdown:OptionButton
# Import buttons
var import_button:Button
var reimport_button:Button

# Bones in the armature may not have the same name as in the BVH.
export(Dictionary) var bone_remapping:Dictionary = Dictionary()

# We keep in our bone_to_index_map a mapping of bone names (string) to an array of indices.  The index values are determined by this:
const XPOS = "Xposition"
const YPOS = "Yposition"
const ZPOS = "Zposition"
const XROT = "Xrotation"
const YROT = "Yrotation"
const ZROT = "Zrotation"
var channel_names = [XPOS, YPOS, ZPOS, XROT, YROT, ZROT]
var channel_index_map = {
	XPOS: 0,
	YPOS: 1,
	ZPOS: 2,
	XROT: 3,
	YROT: 4,
	ZROT: 5
}
# Constants we use in our config.
const RIG_NAME = "rig_name"
const ANIM_PLAYER_NAME = "animation_player_name"
const NEW_ANIM_NAME = "new_animation_name"
var AXIS_ORDERING_NAMES = ["Native", "XYZ", "XZY", "YXZ", "YZX", "ZXY", "ZYX"]
enum AXIS_ORDERING { NATIVE = 0, XYZ, XZY, YXZ, YZX, ZXY, ZYX }
const AXIS_ORDER = "force_axis_ordering"
const REVERSE_AXIS_ORDER = "reverse_native_order"
const FLIP_X_ROTATION = "flip_x_rot"
const FLIP_Y_ROTATION = "flip_y_rot"
const FLIP_Z_ROTATION = "flip_z_rot"
var SOURCE_COORDINATE_SYSTEM_NAMES = ["Blender (Right +X, Up +Z, Forward +Y)", "Ignore", "Godot (Right +X, Up +Y, Forward -Z)"]
enum COORDINATE_SYSTEM { PX_PZ_PY, IGNORE, PX_PY_NZ } # Right/Up/Forward
const SRC_COORD_SYSTEM = "coordinate_system" # The key for our config.

# GX1 -> +X is right.
# GZ1 -> +Z is up.
# GY1 -> +Y is forward.

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
	reverse_axis_order = get_node("ImportTweaks/ReverseAxisOrder")
	source_coordinate_system_dropdown = get_node("ImportTweaks/SourceCoordinateSystem")
	for i in COORDINATE_SYSTEM.values():
		source_coordinate_system_dropdown.add_item(SOURCE_COORDINATE_SYSTEM_NAMES[i], i)
	source_coordinate_system_dropdown.select(COORDINATE_SYSTEM.PX_PZ_PY)
	
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
	config[FLIP_X_ROTATION] = flip_x_rotation_checkbox.pressed
	config[FLIP_Y_ROTATION] = flip_y_rotation_checkbox.pressed
	config[FLIP_Z_ROTATION] = flip_z_rotation_checkbox.pressed
	config[REVERSE_AXIS_ORDER] = reverse_axis_order.pressed
	config[SRC_COORD_SYSTEM] = source_coordinate_system_dropdown.selected
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
	
	var hdata = parse_hierarchy(hierarchy_lines)
	var bone_names:Array = hdata[0]
	var bone_index_map:Dictionary = hdata[1]
	var bone_offsets:Dictionary = hdata[2]
	
	return parse_motion(bone_names, bone_index_map, bone_offsets, motion_lines)

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

func parse_hierarchy(text:Array):# -> [Array, Dictionary, Dictionary]:
	# Given the plaintext HIERARCHY from HIERARCHY until MOTION,
	# pull out the bones AND the order of the features AND the bone offsets, 
	# returning a list of the order of the element names.
	# We don't apply any bone remapping in here.
	var bone_names:Array = Array()
	var bone_index_map:Dictionary = Dictionary() # Maps from bone name to array of [index of x trans (or -1), y trans, z trans, x rot, y rot, z rot]
	var bone_offsets:Dictionary = Dictionary()
		
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
			bone_offsets[current_bone] = [0, 0, 0]
		elif line.begins_with("CHANNELS"):
			var data:Array = line.split(" ", false)
			var num_channels = data[1].to_int()
			for c in range(num_channels):
				var chan = data[2+c]
				bone_index_map[current_bone][channel_index_map[chan]] = data_index
				data_index += 1
				#print("Channel: ", chan, " -> Idx: ", data_index)
		elif line.begins_with("JOINT"):
			current_bone = line.split(" ", false)[1]
			bone_names.append(current_bone)
			bone_index_map[current_bone] = [-1, -1, -1, -1, -1, -1] # -1 means not in collection.
		elif line.begins_with("OFFSET"):
			var data:Array = line.split(" ", false)
			bone_offsets[current_bone] = [data[1].to_float(), data[2].to_float(), data[3].to_float()]
	
	return [bone_names, bone_index_map, bone_offsets]

# WARNING: This method will mutate the input text array.
func parse_motion(bone_names:Array, bone_index_map:Dictionary, bone_offsets:Dictionary, text:Array) -> Animation:
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
		var values = line.strip_edges().split_floats(" ", false)
		for i in range(len(bone_names)):
			var track_index = element_track_index_map[i]
			var bone_name = bone_names[i]
			
			# TODO: I think the channel index map is superfluous.
			var transformXIndex = bone_index_map[bone_name][channel_index_map[XPOS]]
			var transformYIndex = bone_index_map[bone_name][channel_index_map[YPOS]]
			var transformZIndex = bone_index_map[bone_name][channel_index_map[ZPOS]]
			var rotationXIndex = bone_index_map[bone_name][channel_index_map[XROT]]
			var rotationYIndex = bone_index_map[bone_name][channel_index_map[YROT]]
			var rotationZIndex = bone_index_map[bone_name][channel_index_map[ZROT]]
					
			var translation = Vector3(0, 0, 0)
			if transformXIndex != -1:
				translation.x = values[transformXIndex] + bone_offsets[bone_name][0]
			if transformYIndex != -1:
				translation.y = values[transformYIndex] + bone_offsets[bone_name][1]
			if transformZIndex != -1:
				translation.z = values[transformZIndex] + bone_offsets[bone_name][2]
			
			print(step, " ", bone_name)
			var raw_rotation_values = Vector3(0, 0, 0)
			# NOTE: Not actually anything like axis-angle, just a convenient placeholder for a triple.
			if rotationXIndex != -1:
				raw_rotation_values.x = values[rotationXIndex]
			if rotationYIndex != -1:
				raw_rotation_values.y = values[rotationYIndex]
			if rotationZIndex != -1:
				raw_rotation_values.z = values[rotationZIndex]
			print("Starting Z rotation: ", raw_rotation_values.z)
			
			var transformed_values = _convert_coordinate_systems(translation.x, translation.y, translation.z, raw_rotation_values.x, raw_rotation_values.y, raw_rotation_values.z)
			translation.x = transformed_values[0]
			translation.y = transformed_values[1]
			translation.z = transformed_values[2]
			raw_rotation_values.x = transformed_values[3]
			raw_rotation_values.y = transformed_values[4]
			raw_rotation_values.z = transformed_values[5]
			print("Rearranged Y rotation: ", raw_rotation_values.y)
			
			var rotation = Basis(Quat.IDENTITY)
			if rotationXIndex != -1 and rotationYIndex != -1 and rotationZIndex != -1:
				var ordering:String = ""
				if config[AXIS_ORDER] == AXIS_ORDERING.NATIVE:
					# This is a bit messy.  'Native' rotation order means we apply the rotation in the order we read it.
					# That means picking the minimum index of XYZ and applying it, then the next index, etc.
					if rotationXIndex < rotationYIndex and rotationXIndex < rotationZIndex:
						ordering += "X"
						if rotationYIndex < rotationZIndex:
							ordering += "YZ"
						else:
							ordering += "ZY"
					elif rotationYIndex < rotationXIndex and rotationYIndex < rotationZIndex:
						ordering += "Y"
						if rotationXIndex < rotationZIndex:
							ordering += "XZ"
						else:
							ordering += "ZX"
					else: # Z is first.
						ordering += "Z"
						if rotationXIndex < rotationYIndex:
							ordering += "XY"
						else:
							ordering += "YX"
					if config[REVERSE_AXIS_ORDER]:
						var new_order:String = ""
						for axis in ordering:
							new_order = axis + new_order
						ordering = new_order
				else:
					ordering = AXIS_ORDERING_NAMES[config[AXIS_ORDER]]
				# Apply the rotations in the right order.
				for axis in ordering:
					rotation = _apply_rotation(rotation, raw_rotation_values.x, raw_rotation_values.y, raw_rotation_values.z, axis)
			
			print("Transformed Y rotation euler: ", rotation.get_euler().y)
			
			#metarig:spine.006
			#animation.track_set_path(track_index, "Enemy:position.x")
			#animation.track_insert_key(track_index, step*timestep, values[i])
			animation.track_set_path(track_index, rig_name + ":" + bone_name)
			animation.transform_track_insert_key(track_index, step*timestep, translation, rotation.get_rotation_quat(), Vector3(1, 1, 1))
			var quat = rotation.get_rotation_quat()
			print(bone_name, " ", translation.x, " ", translation.y, " ", translation.z, " ", quat.x, " ", quat.y, " ", quat.z, " ", quat.w)
		step += 1
	
	return animation

func _apply_rotation(rotation:Basis, x:float, y:float, z:float, axis:String) -> Basis:
	var config = get_config_data()
	
	print("Rotation before: ", rotation.get_euler())
	if x != 0.0 and axis == "X":
		var rot_scale = 1.0
		if config[FLIP_X_ROTATION]:
			rot_scale = -1.0
		var rot = deg2rad(x) * rot_scale
		print("Rotating basis by x = ", x, " / ", deg2rad(x), ".")
		rotation = rotation.rotated(Vector3(1, 0, 0), rot)
	elif y != 0.0 and axis == "Y":
		var rot_scale = 1.0
		if config[FLIP_Y_ROTATION]:
			rot_scale = -1.0
		var rot = deg2rad(y) * rot_scale
		print("Rotating basis by y = ", y, " / ", deg2rad(y), ".")
		rotation = rotation.rotated(Vector3(0, 1, 0), rot)
	elif z != 0.0 and axis == "Z":
		var rot_scale = 1.0
		if config[FLIP_Z_ROTATION]:
			rot_scale = -1.0
		var rot = deg2rad(z) * rot_scale
		print("Rotating basis by z = ", z, " / ", deg2rad(z), ".")
		rotation = rotation.rotated(Vector3(0, 0, 1), rot)
	print("Rotation after: ", rotation.get_euler())
	return rotation.orthonormalized()

func _convert_coordinate_systems(xpos:float, ypos:float, zpos:float, xrot:float, yrot:float, zrot:float) -> Array:
	# Our current system uses +X for right, +Y for up, -Z for forward
	var config = get_config_data()
	match config[SRC_COORD_SYSTEM]:
		# Right, up, forward.
		COORDINATE_SYSTEM.PX_PZ_PY:
			# TODO: Fix rotations, too.
			return [xpos, zpos, -ypos, xrot, zrot, yrot]
		COORDINATE_SYSTEM.PX_PY_NZ, COORDINATE_SYSTEM.IGNORE, _:
			return [xpos, ypos, zpos, xrot, yrot, zrot]
	printerr("_convert_coordinate_system: Fell through matching condition.  How did you get here?")
	return [xpos, ypos, zpos, xrot, yrot, zrot]