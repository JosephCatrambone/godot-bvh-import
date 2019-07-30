extends VBoxContainer

# DEV FLOW:
# 1) Add a new animation.
# 2) Add some elements to the new animation.
# 3) Load a file from the select file dialog.
# 4) Parse BVH and attach to bones.

# User flow:
# Select animation_player.
# (?) Select armature?  If we do this we might be able to remap animations.  Otherwise we have to rename bones.
# Select BVH file from disk.
# Edit the name mapping BVH bone -> armature bone. (Clear this if the bones don't match.  Otherwise, leave them.)
# Hit import or reimport.

export(Dictionary) var bone_remapping:Dictionary = Dictionary()
#var feature_order = [] # Index -> path to the bone attribute, like Armature:rotation.x or Armature:
#var hierarchy = Dictionary()

# BVH descriptor:
# HIERARCHY
# <hierarchy description>
# MOTION
# <motion description>

func _create_new_animation():
	var animation_player_node_path = $AnimationPlayer/PlayerPath
	var animation_player:AnimationPlayer = get_node(animation_player_node_path.text)
	if animation_player == null:
		printerr("Couldn't find animation player node with path ", animation_player_node_path)
		return
	
	var animation_name_input = $AnimationNameInput
	var animation_name = animation_name_input.text
	if animation_player.has_animation(animation_name):
		# TODO: Animation exists.  Prompt to overwrite.
		animation_player.remove_animation(animation_name)
	
	var filename_input = $BVHFile/FilenameInput
	var animation = load_bvh(filename_input.text)
	
	animation_player.add_animation(animation_name, animation)

func load_bvh(filename:String) -> Animation:
	var file = File.new()
	file.open(filename, File.READ) # "user://some_data"
	# file.store_string("lmao")
	var plaintext = file.get_as_text()
	return parse_bvh(plaintext)

func parse_bvh(fulltext:String) -> Animation:
	# Split the fulltext by the elements from HIERARCHY to MOTION, and MOTION until the end of file.
	var lines = fulltext.split("\n", false)
	var hierarchy_start_line:int = -1
	var motion_start_line:int = -1
	var i:int = 0
	
	
	for line in lines:
		i += 1
		if line.begins_with("HIERARCHY"):
			hierarchy_start_line = i+1
		elif line.begins_with("MOTION"):
			motion_start_line = i+1
			break
	
	var element_order_and_parent_map = parse_hierarchy(lines[hierarchy_start_line:motion_start_line-1])
	var element_order:Array = element_order_and_parent_map[0]
	var parent_map:Dictionary = element_order_and_parent_map[1]
	return parse_motion(element_order, parent_map, 60.0, lines[motion_start_line:])

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

func parse_motion(element_order:Array, parent_map:Dictionary, fps:float, text:Array) -> Animation:
	var animation:Animation = Animation.new()
	# Set the length of the animation to match the BVH length.
	#var animation = Animation.new()
	#var track_index = animation.add_track(Animation.TYPE_VALUE)
	#animation.track_set_path(track_index, "Enemy:position.x")
	#animation.track_insert_key(track_index, 0.0, 0)
	#animation.track_insert_key(track_index, 0.5, 100)
	
	return animation
