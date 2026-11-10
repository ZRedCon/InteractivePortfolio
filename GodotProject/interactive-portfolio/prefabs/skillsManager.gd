class_name SkillsManager extends PanelContainer

const SKILL_PREFAB := preload("res://prefabs/skill_widget.tscn")

@onready var container := $Flow

func add_from_index(index: int) -> void:
	var child = SKILL_PREFAB.instantiate() as Skill
	child.set_values(Entry.SKILLS[ index ], Entry.color_from_index( index ))
	container.add_child(child)

## @deprecated
func add_skill(skill_name: String, skill_color: Color) -> void:
	var child = SKILL_PREFAB.instantiate() as Skill
	child.set_values(skill_name, skill_color)
	container.add_child(child)

func remove_skills() -> void:
	for child in container.get_children():
		child.queue_free()
