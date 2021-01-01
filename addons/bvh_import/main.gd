tool
extends Container

# When we load a file, keep a record of it so we can import it again with tweaked options.
var last_filename:String = ""

# Basic interface:
var editor_interface:EditorInterface
var open_file_dialog:FileDialog
var skeleton_path_input:LineEdit
var animation_player_name_input:LineEdit
var animation_name_input:LineEdit
# Tweaks
var show_tweaks_toggle:Button
var import_tweaks_group:VBoxContainer
var axis_ordering_dropdown:OptionButton
var reverse_axis_order:CheckBox
var x_axis_remap_x:SpinBox # TODO: This should be compacted.  Easy enough to do with indices.
var x_axis_remap_y:SpinBox
var x_axis_remap_z:SpinBox
var y_axis_remap_x:SpinBox
var y_axis_remap_y:SpinBox
var y_axis_remap_z:SpinBox
var z_axis_remap_x:SpinBox
var z_axis_remap_y:SpinBox
var z_axis_remap_z:SpinBox
# Retargeting
var show_retargeting_button:Button
var remapping_json_input:TextEdit
var generate_from_skeleton_button:Button
# Import buttons
var import_button:Button
var reimport_button:Button

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
const SKELETON_PATH = "skeleton_path"
const ANIM_PLAYER_NAME = "animation_player_name"
const NEW_ANIM_NAME = "new_animation_name"
var AXIS_ORDERING_NAMES = ["Native", "XYZ", "XZY", "YXZ", "YZX", "ZXY", "ZYX"]
enum AXIS_ORDERING { NATIVE = 0, XYZ, XZY, YXZ, YZX, ZXY, ZYX }
const AXIS_ORDER = "force_axis_ordering"
const REVERSE_AXIS_ORDER = "reverse_native_order"
const FORWARD_VECTOR = "forward_vector"
const UP_VECTOR = "up_vector"
const RIGHT_VECTOR = "right_vector"
const IGNORE_OFFSETS = "ignore_offsets"
const BONE_REMAPPING_JSON = "bone_remapping_json"

# GX1 -> +X is right.
# GZ1 -> +Z is up.
# GY1 -> +Y is forward.

func _ready():
	open_file_dialog = get_node("FileDialog")
	open_file_dialog.add_filter("*.bvh ; Biovision Hierarchy")
	#open_file_dialog.mode = FileDialog.MODE_OPEN_FILE
	open_file_dialog.connect("file_selected", self, "_on_file_select")
	#get_editor_interface().get_base_control().add_child(open_file_dialog)
	
	skeleton_path_input = get_node("SkeletonPathInput")
	animation_player_name_input = get_node("AnimationPlayerNameInput")
	animation_name_input = get_node("AnimationNameInput")
	
	show_tweaks_toggle = get_node("ShowImportTweaks")
	show_tweaks_toggle.connect("toggled", self, "toggle_tweak_display")
	import_tweaks_group = get_node("ImportTweaks")
	axis_ordering_dropdown = get_node("ImportTweaks/AxisOrderingOption")
	# TODO: I would rather not have to add options here.
	for i in AXIS_ORDERING.values():
		axis_ordering_dropdown.add_item(AXIS_ORDERING_NAMES[i], i)
	axis_ordering_dropdown.select(AXIS_ORDERING.NATIVE)
	reverse_axis_order = get_node("ImportTweaks/ReverseAxisOrder")
	
	x_axis_remap_x = get_node("ImportTweaks/RightAxisOption/x")
	x_axis_remap_y = get_node("ImportTweaks/RightAxisOption/y")
	x_axis_remap_z = get_node("ImportTweaks/RightAxisOption/z")
	y_axis_remap_x = get_node("ImportTweaks/UpAxisOption/x")
	y_axis_remap_y = get_node("ImportTweaks/UpAxisOption/y")
	y_axis_remap_z = get_node("ImportTweaks/UpAxisOption/z")
	z_axis_remap_x = get_node("ImportTweaks/ForwardAxisOption/x")
	z_axis_remap_y = get_node("ImportTweaks/ForwardAxisOption/y")
	z_axis_remap_z = get_node("ImportTweaks/ForwardAxisOption/z")
	
	show_retargeting_button = get_node("ShowBoneRetargeting")
	remapping_json_input = get_node("BoneRetargetingGroup/BoneMapJSONEditor")
	generate_from_skeleton_button = get_node("BoneRetargetingGroup/GenerateFromSkeletonButton")
	generate_from_skeleton_button.connect("pressed", self, "_generate_json_skeleton_map")
	
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
	config[SKELETON_PATH] = skeleton_path_input.text
	config[ANIM_PLAYER_NAME] = animation_player_name_input.text
	config[NEW_ANIM_NAME] = animation_name_input.text
	config[AXIS_ORDER] = axis_ordering_dropdown.selected
	config[REVERSE_AXIS_ORDER] = reverse_axis_order.pressed
	config[RIGHT_VECTOR] = Vector3(x_axis_remap_x.value, x_axis_remap_y.value, x_axis_remap_z.value)
	config[UP_VECTOR] = Vector3(y_axis_remap_x.value, y_axis_remap_y.value, y_axis_remap_z.value)
	config[FORWARD_VECTOR] = Vector3(z_axis_remap_x.value, z_axis_remap_y.value, z_axis_remap_z.value)
	config[IGNORE_OFFSETS] = false
	config[BONE_REMAPPING_JSON] = JSON.parse(remapping_json_input.text)
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

func _generate_json_skeleton_map():
	# Make an 'easy to edit' JSON that we use at import time to remap the bones.
	# It's effectively a dictionary of bvh bone name -> skeleton bone name.
	var result_json = ""
	
	

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
	var root_bone_name:String = hdata[0]
	var bone_names:Array = hdata[1]
	var bone_index_map:Dictionary = hdata[2]
	var bone_offsets:Dictionary = hdata[3]
	
	return parse_motion(root_bone_name, bone_names, bone_index_map, bone_offsets, motion_lines)

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

func parse_hierarchy(text:Array):# -> [String, Array, Dictionary, Dictionary]:
	# Given the plaintext HIERARCHY from HIERARCHY until MOTION,
	# pull out the bones AND the order of the features AND the bone offsets, 
	# returning a list of the order of the element names.
	# We don't apply any bone remapping in here.
	var bone_names:Array = Array()
	var bone_index_map:Dictionary = Dictionary() # Maps from bone name to a map of *POS -> value.
	var bone_offsets:Dictionary = Dictionary()
		
	# NOTE: We are not keeping the structure of the hierarchy because we don't need it.
	# We only need the order of the channels and names of the bones.
	var line_index:int = 0
	var data_index:int = 0
	var root_bone = ""
	var current_bone = ""
	for line in text:
		var txt:String = line
		line = line.strip_edges()
		if line.begins_with("ROOT"):
			current_bone = line.split(" ", false)[1]
			bone_names.append(current_bone)
			bone_index_map[current_bone] = Dictionary()
			bone_offsets[current_bone] = Vector3()
			root_bone = current_bone
		elif line.begins_with("CHANNELS"):
			var data:Array = line.split(" ", false)
			var num_channels = data[1].to_int()
			print("Reading " + str(num_channels) + " data channel(s) for bone " + current_bone)
			for c in range(num_channels):
				var chan = data[2+c]
				bone_index_map[current_bone][chan] = data_index
				data_index += 1
				print(current_bone + " " + chan + ": " + str(data_index))
		elif line.begins_with("JOINT"):
			current_bone = line.split(" ", false)[1]
			bone_names.append(current_bone)
			bone_index_map[current_bone] = Dictionary() # -1 means not in collection.
			bone_offsets[current_bone] = Vector3()
		elif line.begins_with("OFFSET"):
			var data:Array = line.split(" ", false)
			bone_offsets[current_bone].x = data[1].to_float()
			bone_offsets[current_bone].y = data[2].to_float()
			bone_offsets[current_bone].z = data[3].to_float()
	
	return [root_bone, bone_names, bone_index_map, bone_offsets]

# WARNING: This method will mutate the input text array.
func parse_motion(root:String, bone_names:Array, bone_index_map:Dictionary, bone_offsets:Dictionary, text:Array) -> Animation:
	var config = get_config_data()
		
	# Precompute our axises.
	# -Z forward, +Y up, +x right
	var up_axis:Vector3 = config[UP_VECTOR] # Locally, +Y
	var forward_axis:Vector3 = config[FORWARD_VECTOR]
	var right_axis:Vector3 = config[RIGHT_VECTOR] # Locally +X
	
	var rig_name = config[SKELETON_PATH]
	
	var num_frames = 0
	var timestep = 0.033333
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
	
	var animation:Animation = Animation.new()
	
	# Set the length of the animation to match the BVH length.
	animation.length = num_frames * timestep
	
	# Create new tracks.
	var element_track_index_map:Dictionary = Dictionary()
	for i in range(len(bone_names)):
		var track_index = animation.add_track(Animation.TYPE_TRANSFORM)
		# Note: Hitting the keyframe button on the pose data will insert a value track with bones/##/pose,
		# but this doesn't appear to work for the replay.  Use a transform track instead of Animation.TYPE_VALUE.
		element_track_index_map[i] = track_index
	
	var step:int = 0
	for line in text:
		var values = line.strip_edges().split_floats(" ", false)
		for bone_index in range(len(bone_names)):
			var track_index = element_track_index_map[bone_index]
			var bone_name = bone_names[bone_index]
			
			# Use negative one so that if we forget a check we fail early and get an index error, rather than bad data.
			var transformXIndex = bone_index_map[bone_name].get(XPOS, -1)
			var transformYIndex = bone_index_map[bone_name].get(YPOS, -1)
			var transformZIndex = bone_index_map[bone_name].get(ZPOS, -1)
			var rotationXIndex = bone_index_map[bone_name].get(XROT, -1)
			var rotationYIndex = bone_index_map[bone_name].get(YROT, -1)
			var rotationZIndex = bone_index_map[bone_name].get(ZROT, -1)
			
			var translation = Vector3()
			if not config[IGNORE_OFFSETS]: # These are the _starting_ offsets, not the translations.
				translation = -Vector3( # Note the negation.
					bone_offsets[bone_name].x,
					bone_offsets[bone_name].y,
					bone_offsets[bone_name].z
				) # Clone this vector so we don't change it between steps.
			if bone_index_map[bone_name].has(XPOS):
				translation.x += values[bone_index_map[bone_name][XPOS]]
			if bone_index_map[bone_name].has(YPOS):
				translation.y += values[bone_index_map[bone_name][YPOS]]
			if bone_index_map[bone_name].has(ZPOS):
				translation.z += values[bone_index_map[bone_name][ZPOS]]
			translation = _remap_vector_components(translation)
			
			# Godot: +X right, -Z forward, +Y up.	
			var rotation:Quat = Quat.IDENTITY
			var raw_rotation_values:Vector3 = Vector3(0, 0, 0)
			# NOTE: raw_rot is Not actually anything like axis-angle, just a convenient placeholder for a triple.
			if bone_index_map[bone_name].has(XROT):
				raw_rotation_values.x = values[bone_index_map[bone_name][XROT]]
			if bone_index_map[bone_name].has(YROT):
				raw_rotation_values.y = values[bone_index_map[bone_name][YROT]]
			if bone_index_map[bone_name].has(ZROT):
				raw_rotation_values.z = values[bone_index_map[bone_name][ZROT]]
			raw_rotation_values = _remap_vector_components(raw_rotation_values)
			
			# Apply joint rotations.
			if not bone_index_map[bone_name].has(XROT) and bone_index_map[bone_name].has(YROT) and bone_index_map[bone_name].has(ZROT):
				print("Bone ", bone_name, " is missing rotation information.")
			else:
				var ordering:String = ""
				if config[AXIS_ORDER] == AXIS_ORDERING.NATIVE:
					# 'Native' rotation order means we apply the rotation in the order we read it.
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
				else:
					ordering = AXIS_ORDERING_NAMES[config[AXIS_ORDER]]
				# Potentially flip order.  This is the difference from applying left-to-right and right-to-left.
				# TODO: rotation.transpose?
				if config[REVERSE_AXIS_ORDER]:
					var new_order:String = ""
					for axis in ordering:
						new_order = axis + new_order
					ordering = new_order
				# Apply the rotations in the right order.
				for axis in ordering:
					rotation = _apply_rotation(rotation, raw_rotation_values.x, raw_rotation_values.y, raw_rotation_values.z, axis)
			
			# Apply bone-name remapping _just_ before we actually set the track.
			if config[BONE_REMAPPING_JSON].has(bone_name):
				bone_name = config[BONE_REMAPPING_JSON][bone_name]
				# TODO: Option to skip unmapped bones.  Leaving as is for now because people can remove them manually.
			
			animation.track_set_path(track_index, rig_name + ":" + bone_name)
			animation.transform_track_insert_key(track_index, step*timestep, translation, rotation, Vector3(1, 1, 1))
			#animation.transform_track_insert_key(track_index, step*timestep, translation, Quat(raw_rotation_values.x, raw_rotation_values.y, raw_rotation_values.z, 0), Vector3(1, 1, 1))
			#animation.transform_track_insert_key(track_index, step*timestep, transform.origin, transform.basis.get_rotation_quat(), Vector3(1, 1, 1))
			#animation.track_set_path(track_index, rig_name + ":" + "bones/" + str(bone_index) + "/pose")
			#animation.track_insert_key(track_index, step*timestep, transform)
		step += 1
	
	return animation

func _apply_rotation(rotation:Quat, x:float, y:float, z:float, axis:String) -> Quat:
	if axis == "X":
		rotation *= Quat(Vector3(1, 0, 0), deg2rad(x))
	elif axis == "Y":
		rotation *= Quat(Vector3(0, 1, 0), deg2rad(y))
	elif axis == "Z":
		rotation *= Quat(Vector3(0, 0, 1), deg2rad(z))
	return rotation.normalized()

func _remap_vector_components(xyz:Vector3) -> Vector3:
	var config = get_config_data()
	return config[RIGHT_VECTOR]*xyz.x + config[UP_VECTOR]*xyz.y + config[FORWARD_VECTOR]*xyz.z

func _euler_to_quaternion(yaw:float, pitch:float, roll:float) -> Quat: # Z Y X
	var cy = cos(yaw * 0.5)
	var sy = sin(yaw * 0.5)
	var cp = cos(pitch * 0.5)
	var sp = sin(pitch * 0.5)
	var cr = cos(roll * 0.5)
	var sr = sin(roll * 0.5)
	
	var x = cy * cp * sr - sy * sp * cr
	var y = sy * cp * sr + cy * sp * cr
	var z = sy * cp * cr - cy * sp * sr
	var w = cy * cp * cr + sy * sp * sr
	return Quat(x, y, z, w)
