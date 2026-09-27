module main

import ui2

fn find_icon_fonts_element(element ui2.Element, id string) ?ui2.Element {
	if element.id == id {
		return element
	}
	for child in element.children {
		if found := find_icon_fonts_element(child, id) {
			return found
		}
	}
	return none
}

// count_icon_images counts the elements carrying an icon as an image, which is
// every element whose image path is an `icon:` path. An icon drawn as a label is
// not one of these: a label draws its glyph as text, and has no image at all.
fn count_icon_images(element ui2.Element) int {
	mut count := if element.image_path.starts_with('icon:') { 1 } else { 0 }
	for child in element.children {
		count += count_icon_images(child)
	}
	return count
}

// count_icon_labels counts the labels drawing a glyph, which is every label
// whose font is the icon face rather than a text one.
fn count_icon_labels(element ui2.Element) int {
	mut count := if element.kind == .label && element.text_style.font_family.len > 0 {
		1
	} else {
		0
	}
	for child in element.children {
		count += count_icon_labels(child)
	}
	return count
}

fn test_icon_lookup_reports_the_code_point_a_name_draws_at() {
	mut app := IconFontsDemo{}
	app.look_up('home')
	assert app.found
	assert app.query == 'home'
	assert app.status == 'Material Icons carries "home" at U+e88a'
}

fn test_icon_lookup_says_so_when_the_face_carries_no_such_name() {
	mut app := IconFontsDemo{}
	// A name that is not in the table, and not a near miss either: the bundled
	// face has `home`, and nothing called `homes`.
	app.look_up('homes')
	assert !app.found
	assert app.status == 'Material Icons carries no "homes", so a question mark is drawn'
}

fn test_icon_lookup_trims_the_name_the_field_held() {
	mut app := IconFontsDemo{}
	app.look_up('  settings  ')
	assert app.found
	assert app.query == 'settings'
	assert app.status == 'Material Icons carries "settings" at U+e8b8'
}

fn test_icon_pick_records_which_name_was_tapped() {
	mut app := IconFontsDemo{}
	app.pick('favorite')
	assert app.picked == 'favorite'
}

fn test_icon_fonts_vml_draws_its_icons_from_names_and_asks_no_font_for_a_glyph() {
	app := IconFontsDemo{}
	root := ui2.element_from_vml_model(icon_fonts_vml_source, app,
		ui2.rect(0, 0, icon_fonts_width, icon_fonts_height)) or { panic(err) }
	ui2.validate_element_tree(root) or { panic(err) }
	// Five buttons carry an icon as an image. The labels carry one as a glyph:
	// sixteen in the grid, one showing the looked up name, three that can be
	// tapped, and one asking the bundled face from the other face's section.
	assert count_icon_images(root) == 5
	assert count_icon_labels(root) == 16 + 1 + 3 + 1
}

fn test_icon_fonts_vml_keeps_a_known_name_and_reports_an_unknown_one() {
	known := ui2.element_from_vml_model(icon_fonts_vml_source, IconFontsDemo{},
		ui2.rect(0, 0, icon_fonts_width, icon_fonts_height)) or { panic(err) }
	// The label's text is the glyph the name draws at, and nothing else: an
	// icon font carries no letters, so a name drawn in it would come out as one
	// box per letter.
	looked_up := find_icon_fonts_element(known, 'looked_up') or { panic('missing lookup glyph') }
	assert looked_up.text == '\ue88a'
	assert looked_up.text_style.font_family == ui2.material_icon_path
	assert ui2.icon_name('material', 'home') == '\ue88a'

	unknown := ui2.element_from_vml_model(icon_fonts_vml_source, IconFontsDemo{
		query:       'homes'
		found:       false
		lookup_icon: 'help-outline'
	}, ui2.rect(0, 0, icon_fonts_width, icon_fonts_height)) or { panic(err) }
	// A name the face does not carry is replaced by a name it does, rather than
	// drawn as a private use code point the face has no outline for.
	fallen_back := find_icon_fonts_element(unknown, 'looked_up') or { panic('missing lookup glyph') }
	assert fallen_back.text == '\ue8fd'
	assert fallen_back.text_style.font_family == ui2.material_icon_path
	assert ui2.icon_name('material', 'help-outline') == '\ue8fd'
}

fn test_icon_buttons_carry_their_icon_as_an_image_path() {
	root := ui2.element_from_vml_model(icon_fonts_vml_source, IconFontsDemo{},
		ui2.rect(0, 0, icon_fonts_width, icon_fonts_height)) or { panic(err) }
	save := find_icon_fonts_element(root, 'save') or { panic('missing save button') }
	assert save.kind == .button
	assert save.image_path == 'icon:material:save'
	assert save.text == 'Save'
	assert save.action_id == ''
	delete := find_icon_fonts_element(root, 'delete') or { panic('missing delete button') }
	assert delete.image_path == 'icon:material:delete'
}

fn test_an_icon_label_asks_the_font_it_names() {
	root := ui2.element_from_vml_model(icon_fonts_vml_source, IconFontsDemo{},
		ui2.rect(0, 0, icon_fonts_width, icon_fonts_height)) or { panic(err) }
	// The bundled face is asked by alias and answered with its file, which is
	// what a renderer loads. A text label keeps the family it was given, which
	// for most is none.
	pick := find_icon_fonts_element(root, 'pick_star') or { panic('missing pickable star') }
	assert pick.kind == .label
	assert pick.text_style.font_family == ui2.material_icon_path
	status := find_icon_fonts_element(root, 'status') or { panic('missing status line') }
	assert status.text_style.font_family.len == 0
}
