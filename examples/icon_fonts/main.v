// Icon fonts, as a VML document.
//
// Every icon here is named rather than typed: `icon: home` is looked up in the
// bundled Material Icons face, whose names live in `ui/icons_material.v`. No
// private use code point is written anywhere in this file, and no font is
// installed on the machine running it.

import ui2

@[heap]
pub struct IconFontsDemo {
pub mut:
	// query is the name being looked up, which the text field edits.
	query string = 'home'
	// lookup_icon is the name the document draws beside the field. It is the
	// name asked for when the face carries it, and a question mark when it does
	// not, because a name the face cannot draw is not drawn at all.
	lookup_icon string = 'home'
	// found says whether the bundled face carries `query`.
	found bool
	// status is the line drawn under the field, and is also the label a
	// screen reader reads for the icon the query drew.
	status string = 'Material Icons carries "home"'
	// picked is the name of the icon row below, which a button changes.
	picked string = 'star'
}

const icon_fonts_state = &IconFontsDemo{}

// icon_names is the row of names drawn side by side. They are written the way
// the Material Icons package writes them, which is how `tools/icond.v` read
// them out of that package's list in the first place.
const icon_names = ['home', 'search', 'settings', 'favorite', 'delete', 'add',
	'edit', 'person', 'mail', 'star', 'shopping-cart', 'info', 'warning',
	'cloud', 'lock', 'thumb-up']

// icon_buttons pairs a name with the title a button carries beside it.
const icon_buttons = {
	'save':       'Save'
	'delete':     'Delete'
	'share':      'Share'
	'print':      'Print'
	'cloud-done': 'Upload'
}

const icon_fonts_width = 760
const icon_fonts_height = 520
const icon_fonts_vml_source = $embed_file('icon_fonts.vml').to_string()

pub fn (mut app IconFontsDemo) look_up(query string) {
	name := query.trim_space()
	// The bundled face, read through the same API an application would use for
	// a font of its own after registering it under an alias.
	font := ui2.material_icon_font()
	app.query = name
	// The option is what says whether the face carries the name: an icon font
	// is a mapping, and a name missing from it is a name not to draw.
	if code := font.lookup(name) {
		app.found = true
		app.lookup_icon = name
		app.status = 'Material Icons carries "${name}" at U+${code.hex()}'
	} else {
		app.found = false
		app.lookup_icon = 'help-outline'
		app.status = 'Material Icons carries no "${name}", so a question mark is drawn'
	}
}

pub fn (mut app IconFontsDemo) pick(name string) {
	app.picked = name
}

fn build_icon_fonts_screen() ui2.Element {
	state := unsafe { icon_fonts_state }
	return ui2.element_from_vml_model(icon_fonts_vml_source, *state, ui2.bounds()) or {
		eprintln('icon-fonts VML failed: ${err}')
		ui2.screen(0xf1f5f9, [])
	}
}

fn handle_icon_fonts_event(event string) {
	mut state := unsafe { icon_fonts_state }
	if event == 'lookup' {
		state.look_up(ui2.text('query'))
	} else if event.starts_with('pick:') {
		state.pick(event['pick:'.len..])
	}
	ui2.refresh()
}

fn main() {
	ui2.run_window('Icon fonts', icon_fonts_width, icon_fonts_height,
		build_icon_fonts_screen, handle_icon_fonts_event)
}
