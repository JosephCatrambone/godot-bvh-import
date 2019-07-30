tool
extends EditorPlugin

#
# Plugin boilerplate and housekeeping.
#

var dock

func _enter_tree():
	# Initialization of the plugin goes here
	# Load the dock scene and instance it
	dock = preload("res://addons/bvh_import/dock.tscn").instance()
	dock.editor_interface = get_editor_interface()
	
	# Add the loaded scene to the docks
	add_control_to_dock(DOCK_SLOT_LEFT_UL, dock)
	
func _exit_tree():
	# Free memory.  Clean up signals.
	if dock == null:
		print("Dock is null.")
	#dock.queue_free()
	remove_control_from_docks(dock)


