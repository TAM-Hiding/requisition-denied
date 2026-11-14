class_name ScrapPanel
extends MarginContainer

var supply: ScrapSupply
var stock := ItemList.new()
var detail := Label.new()
var feedback := Label.new()
var dispense_button := Button.new()
var selected := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_" + side, 22)
	var appearance := Theme.new()
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["DejaVu Sans Mono", "monospace"])
	appearance.default_font = mono
	appearance.default_font_size = 19
	for kind in ["Label", "Button", "ItemList"]:
		appearance.set_color("font_color", kind, Color("bed7aa"))
	theme = appearance
	var column := VBoxContainer.new()
	add_child(column)
	var heading := Label.new()
	heading.text = "FACILITY / DEVELOPMENT SCRAP"
	heading.add_theme_font_size_override("font_size", 28)
	column.add_child(heading)
	var layout := HBoxContainer.new()
	layout.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(layout)
	stock.custom_minimum_size.x = 345
	layout.add_child(stock)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	layout.add_child(right)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.size_flags_vertical = SIZE_EXPAND_FILL
	right.add_child(detail)
	dispense_button.text = "DISPENSE ONE"
	right.add_child(dispense_button)
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(feedback)
	var exit_hint := Label.new()
	exit_hint.text = "ESC EXIT   /   DELIVERY PAD BESIDE RACK"
	column.add_child(exit_hint)
	for entry in supply.catalog:
		stock.add_item("%s  %s" % [entry.icon, entry.title])
	stock.item_selected.connect(select_stock)
	stock.item_activated.connect(func(index: int) -> void:
		select_stock(index)
		dispense_selected())
	dispense_button.pressed.connect(dispense_selected)
	stock.select(0)
	select_stock(0)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("10180f"))

func select_stock(index: int) -> void:
	selected = index
	var entry := supply.catalog[index]
	detail.text = "%s\n\n%s\n\n%s\n%.2f kg" % [
		entry.icon, String(entry.category).to_upper(), ScrapSupply.dimensions(entry.size), entry.mass]
	feedback.text = ""

func dispense_selected() -> void:
	var part := supply.dispense(selected)
	feedback.text = "Dispensed %s." % part.definition.display_name if part != null else "Delivery pad occupied. Clear it and try again."
