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
var autoscale_bvh_option:CheckBox
var ignore_offsets_option:CheckBox
var transform_scaling_spinbox:SpinBox
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
var bone_retargeting_group:VBoxContainer
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
const IGNORE_OFFSETS = "ignore_offsets"
const TRANSFORM_SCALING = "transform_scaling"
const BONE_REMAPPING_JSON = "bone_remapping_json"
var AXIS_ORDERING_NAMES = ["Native", "XYZ", "XZY", "YXZ", "YZX", "ZXY", "ZYX", "Reverse Native"]
enum AXIS_ORDERING { NATIVE = 0, XYZ, XZY, YXZ, YZX, ZXY, ZYX, REVERSE }
const AXIS_ORDER = "force_axis_ordering"
const FORWARD_VECTOR = "forward_vector"
const UP_VECTOR = "up_vector"
const RIGHT_VECTOR = "right_vector"

# Godot + OpenGL are left-handed.  -Z is forward.  +Y is up.
# Blender:
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
	import_tweaks_group = get_node("ImportTweaksGroup")
	ignore_offsets_option = get_node("ImportTweaksGroup/IgnoreOffsetsOption")
	transform_scaling_spinbox = get_node("ImportTweaksGroup/TransformScaleTweak/TransformScaleSpinBox")
	axis_ordering_dropdown = get_node("ImportTweaksGroup/AxisOrderingOption")
	# TODO: I would rather not have to add options here.
	#for i in AXIS_ORDERING.values():
	#	axis_ordering_dropdown.add_item(AXIS_ORDERING_NAMES[i], i)
	axis_ordering_dropdown.select(AXIS_ORDERING.NATIVE)	
	x_axis_remap_x = get_node("ImportTweaksGroup/XBasisTweak/x")
	x_axis_remap_y = get_node("ImportTweaksGroup/XBasisTweak/y")
	x_axis_remap_z = get_node("ImportTweaksGroup/XBasisTweak/z")
	y_axis_remap_x = get_node("ImportTweaksGroup/YBasisTweak/x")
	y_axis_remap_y = get_node("ImportTweaksGroup/YBasisTweak/y")
	y_axis_remap_z = get_node("ImportTweaksGroup/YBasisTweak/z")
	z_axis_remap_x = get_node("ImportTweaksGroup/ZBasisTweak/x")
	z_axis_remap_y = get_node("ImportTweaksGroup/ZBasisTweak/y")
	z_axis_remap_z = get_node("ImportTweaksGroup/ZBasisTweak/z")
	
	show_retargeting_button = get_node("ShowBoneRetargeting")
	show_retargeting_button.connect("toggled", self, "toggle_bone_retargeting_display")
	bone_retargeting_group = get_node("BoneRetargetingGroup")
	remapping_json_input = get_node("BoneRetargetingGroup/BoneMapJSONEditor")
	generate_from_skeleton_button = get_node("BoneRetargetingGroup/GenerateFromSkeletonButton")
	generate_from_skeleton_button.connect("pressed", self, "_generate_json_skeleton_map")
	
	import_button = get_node("ImportButton")
	import_button.connect("pressed", self, "_import")
	reimport_button = get_node("ReimportButton")
	reimport_button.connect("pressed", self, "_reimport")

func toggle_tweak_display(toggle):
	import_tweaks_group.visible = show_tweaks_toggle.pressed

func toggle_bone_retargeting_display(toggle):
	bone_retargeting_group.visible = show_retargeting_button.pressed

func get_config_data() -> Dictionary:
	# Reads from our UI and returns a dictionary of String -> Value.
	# This will do all of the node reading and accessing, next to ready.
	var config = Dictionary()
	config[SKELETON_PATH] = skeleton_path_input.text
	config[ANIM_PLAYER_NAME] = animation_player_name_input.text
	config[NEW_ANIM_NAME] = animation_name_input.text
	config[IGNORE_OFFSETS] = ignore_offsets_option.pressed
	config[TRANSFORM_SCALING] = transform_scaling_spinbox.value
	config[AXIS_ORDER] = axis_ordering_dropdown.selected
	config[RIGHT_VECTOR] = Vector3(x_axis_remap_x.value, x_axis_remap_y.value, x_axis_remap_z.value)
	config[UP_VECTOR] = Vector3(y_axis_remap_x.value, y_axis_remap_y.value, y_axis_remap_z.value)
	config[FORWARD_VECTOR] = Vector3(z_axis_remap_x.value, z_axis_remap_y.value, z_axis_remap_z.value)
	config[BONE_REMAPPING_JSON] = JSON.parse(remapping_json_input.text).result
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
	# This method feels hacky.  Would be good to clean it up.
	var config = get_config_data()
	var rig_name = config[SKELETON_PATH]
	var skeleton:Skeleton = editor_interface.get_edited_scene_root().get_node(rig_name)
	if skeleton == null:
		remapping_json_input.text = "{}"
		printerr("Failed to find Skeleton/Rig with name ", rig_name + ".")
		return
	remapping_json_input.text = "{\n"
	for bid in range(skeleton.get_bone_count()):
		if bid > 0:
			remapping_json_input.text += ",\n"
		var bone_name = skeleton.get_bone_name(bid)
		remapping_json_input.text += "\t\"\": \"" + bone_name + "\""
	remapping_json_input.text += "\n}"

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
		return null
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
				print(current_bone + " " + chan + ": " + str(data_index))
				data_index += 1
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
			var translation_x_index = bone_index_map[bone_name].get(XPOS, -1)
			var translation_y_index = bone_index_map[bone_name].get(YPOS, -1)
			var translation_z_index = bone_index_map[bone_name].get(ZPOS, -1)
			var rotation_x_index = bone_index_map[bone_name].get(XROT, -1)
			var rotation_y_index = bone_index_map[bone_name].get(YROT, -1)
			var rotation_z_index = bone_index_map[bone_name].get(ZROT, -1)
			
			var translation = Vector3()
			if not config[IGNORE_OFFSETS]: # These are the _starting_ offsets, not the translations.
				translation = Vector3(
					bone_offsets[bone_name].x,
					bone_offsets[bone_name].y,
					bone_offsets[bone_name].z
				) # Clone this vector so we don't change it between steps.
			if translation_x_index != -1:
				translation.x += values[translation_x_index]
			if translation_y_index != -1:
				translation.y += values[translation_y_index]
			if translation_z_index != -1:
				translation.z += values[translation_z_index]
			translation *= config[TRANSFORM_SCALING]
			
			# Godot: +X right, -Z forward, +Y up.
			# BVH: +Y up.
			var raw_rotation_values:Vector3 = Vector3(0, 0, 0)
			# NOTE: raw_rot is Not actually anything like axis-angle, just a convenient placeholder for a triple.
			raw_rotation_values.x = values[rotation_x_index]
			raw_rotation_values.y = values[rotation_y_index]
			raw_rotation_values.z = values[rotation_z_index]

			# Apply joint rotations.
			if config[AXIS_ORDER] == AXIS_ORDERING.REVERSE:
				# Something of a hack.  We take the indices in order and sort them, by flipping the index sign we take them in reverse order.
				rotation_x_index = -rotation_x_index
				rotation_y_index = -rotation_y_index
				rotation_z_index = -rotation_z_index
			elif config[AXIS_ORDER] != AXIS_ORDERING.NATIVE:
				rotation_x_index = AXIS_ORDERING_NAMES[config[AXIS_ORDER]].find('X')
				rotation_y_index = AXIS_ORDERING_NAMES[config[AXIS_ORDER]].find('Y')
				rotation_z_index = AXIS_ORDERING_NAMES[config[AXIS_ORDER]].find('Z')
			var rotation = _bvh_zxy_to_quaternion(raw_rotation_values.x, raw_rotation_values.y, raw_rotation_values.z, rotation_x_index, rotation_y_index, rotation_z_index)
			# CAVEAT SCRIPTOR: rotation_*_index is not valid after this operation!
			
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

class FirstIndexSort:
	static func sort_ascending(a, b):
		if a[0] > b[0]:
			return true
		return false

func _bvh_zxy_to_quaternion(x:float, y:float, z:float, x_idx:int, y_idx:int, z_idx:int) -> Quat:
	# From BVH documentation: "it goes Z rotation, followed by the X rotation and finally the Y rotation."
	# But there are some applications which change the ordering.  
	var config = get_config_data()
	var rotation := Quat.IDENTITY
	var x_rot = Quat(config[RIGHT_VECTOR], deg2rad(x))
	var y_rot = Quat(config[UP_VECTOR], deg2rad(y))
	var z_rot = Quat(config[FORWARD_VECTOR], deg2rad(z))
	# This is a lazy way of sorting the actions into appropriate order.
	var rotation_matrices = [[x_idx, x_rot], [y_idx, y_rot], [z_idx, z_rot]]
	rotation_matrices.sort_custom(FirstIndexSort, "sort_ascending")
	for r in rotation_matrices:
		rotation *= r[1]
	return rotation
