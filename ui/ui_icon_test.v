module ui2

import os

// icon_test_font_path is the icon face every build of `ui2` ships.
const icon_test_font_path = @VMODROOT + '/assets/fonts/MaterialIcons-Regular.ttf'

// A stylesheet as Font Awesome 4 writes one: a class per icon, and the code
// point in the content.
const fa4_css = '@font-face{font-family:"FontAwesome";src:url(fa.woff2)}\n' +
	'.fa{font-family:FontAwesome}\n' +
	'.fa-comment:before{content:"\\f0e5"}\n' +
	'.fa-star:before{content:"\\f005"}\n' +
	'.fa-user:before{content:"\\f007"}\n' +
	'.fa-lg{font-size:1.333em}\n' +
	'.fa-spin{-webkit-animation:fa-spin 2s infinite linear}\n'

// Font Awesome 5 writes a class per weight beside the icon's own, so a selector
// carries two names and only one of them is the icon.
const fa5_css = '.fas{font-family:"Font Awesome 5 Free"}\n' +
	'.fas.fa-star:before{content:"\\f005"}\n' +
	'.fas.fa-comment-alt:before{content:"\\f075"}\n' +
	'.far.fa-star:before{content:"\\f006"}\n'

// IcoMoon writes a `content` per class but the escape after the `u`.
const icomoon_css = '.icon-home:before{content:"\\ue900"}\n' +
	'.icon-user:before{content:"\\ue901"}\n'

fn test_parse_icon_css_reads_a_font_awesome_4_stylesheet() {
	icons := parse_icon_css(fa4_css)
	assert icons['comment'] == 0xf0e5
	assert icons['star'] == 0xf005
	assert icons['user'] == 0xf007
}

fn test_parse_icon_css_reads_a_font_awesome_5_stylesheet() {
	icons := parse_icon_css(fa5_css)
	// `fas` is the weight, `fa-star` the icon, and `far` is a second weight
	// drawing the same name from a different face.
	assert icons['star'] == 0xf005
	assert icons['comment-alt'] == 0xf075
}

fn test_parse_icon_css_reads_a_stylesheet_that_escapes_with_a_u() {
	icons := parse_icon_css(icomoon_css)
	assert icons['home'] == 0xe900
	assert icons['user'] == 0xe901
}

// The face itself, the sizes and the animations share the stylesheet with the
// icons, and none of them names a glyph.
fn test_parse_icon_css_ignores_the_rules_that_do_not_name_a_glyph() {
	icons := parse_icon_css(fa4_css)
	assert icons.len == 3
}

fn test_parse_icon_css_reads_a_comment_as_nothing() {
	source := '.fa-star:before{content:"\\f005"}\n' +
		'/* .fa-user:before{content:"\\f007"} */\n'
	icons := parse_icon_css(source)
	assert icons['star'] == 0xf005
	assert icons.len == 1, 'a commented-out rule was read as an icon'
}

fn test_parse_icon_css_keeps_the_first_of_a_repeated_name() {
	// A stylesheet that lists a name twice means one icon, and the later rule
	// only repeats it for a state.
	source := '.fa-star:before{content:"\\f005"}\n' +
		'.fa-star:hover:before{content:"\\f005"}\n'
	icons := parse_icon_css(source)
	assert icons['star'] == 0xf005
	assert icons.len == 1
}

fn test_parse_icon_css_does_not_read_a_state_as_part_of_the_name() {
	// `:hover` and `:focus` are states of the icon, not names of other icons.
	source := '.fa-star:hover:before{content:"\\f005"}\n' +
		'.fa-star:focus:before{content:"\\f006"}\n'
	icons := parse_icon_css(source)
	assert icons.len == 1
	assert icons['star'] == 0xf005
}

// A font that spells its icons as ligature text carries no code point in its
// stylesheet, so there is nothing here to read a name from. Saying so is the
// honest answer: such a font is registered with a map of its own instead.
fn test_parse_icon_css_reads_nothing_out_of_a_ligature_content() {
	icons := parse_icon_css('.fa-star:before{content:"star home"}')
	assert icons.len == 0
}

fn test_parse_icon_css_names_every_icon_a_grouped_selector_holds() {
	// A package that cuts one glyph under two old names writes both classes
	// against one content.
	source := '.fa-cut:before,.fa-scissors:before{content:"\\f0c4"}\n'
	icons := parse_icon_css(source)
	assert icons['cut'] == 0xf0c4
	assert icons['scissors'] == 0xf0c4
	assert icons.len == 2
}

fn test_parse_icon_css_reads_a_content_without_quotes() {
	// CSS allows the quotes to be left off the escape.
	icons := parse_icon_css('.fa-star:before{content:\\f005}')
	assert icons['star'] == 0xf005
}

fn test_parse_icon_css_ignores_a_content_that_is_neither() {
	// A counter is a number, not a glyph, and reading it as one would answer
	// every name a rule counts with.
	icons := parse_icon_css('.fa-item:before{content:counter(item)}')
	assert icons.len == 0
}

fn test_parse_icon_css_survives_a_truncated_stylesheet() {
	assert parse_icon_css('.fa-star:before{content:"\\f005"').len == 0
	assert parse_icon_css('').len == 0
	assert parse_icon_css('not a stylesheet').len == 0
}

// ── Names ──────────────────────────────────────────────────────────

// The three packages write the same icon's name three ways, and the name a
// caller writes has to reach the same glyph whichever package it came from.
fn test_icon_names_ignore_the_package_prefix() {
	icons := map[string]int{
		'comment': 0xf0e5
	}
	font := IconFont{
		alias: 'fa'
		icons: icons
	}
	assert code_of(font, 'comment') == 0xf0e5
	assert code_of(font, 'fa-comment') == 0xf0e5
	assert code_of(font, 'icon-comment') == 0xf0e5
	assert code_of(font, 'glyphicon-comment') == 0xf0e5
}

fn test_icon_names_are_normalized() {
	icons := map[string]int{
		'home': 0xe88a
	}
	font := IconFont{
		alias: 'mi'
		icons: icons
	}
	assert code_of(font, 'Home') == 0xe88a
	assert code_of(font, ' home ') == 0xe88a
	// A name the font does not carry is a name, not a near miss: `home` is the
	// icon, and `my-home` is a different one whether it was written with a dash
	// or with a separator.
	if _ := font.lookup('my-home') {
		assert false, 'a name the font does not carry was answered'
	}
	if _ := font.lookup('my_home') {
		assert false, 'a name the font does not carry was answered'
	}
}

fn test_icon_lookup_reports_a_name_the_font_does_not_carry() {
	font := IconFont{
		alias: 'fa'
		icons: map[string]int{
			'star': 0xf005
		}
	}
	if _ := font.lookup('nonexistent') {
		assert false, 'a name the font does not carry was answered'
	}
}

fn test_parse_icon_hex_reads_the_digits_of_an_escape() {
	assert parse_icon_hex('f0e5') == 0xf0e5
	assert parse_icon_hex('ue900') == 0xe900
	assert parse_icon_hex('005f') == 0x005f
	// CSS allows six digits and stops at anything that is not one of them.
	assert parse_icon_hex('f0e5;') == 0xf0e5
	assert parse_icon_hex('z') == 0
	assert parse_icon_hex('') == 0
}

fn test_icon_text_codepoint_reads_a_escaped_string() {
	assert icon_text_codepoint('"\\f0e5"') == 0xf0e5
	assert icon_text_codepoint('\\f0e5') == 0xf0e5
	// The same value written as the character itself, which is the way a table
	// held in V rather than read from CSS spells it.
	assert icon_text_codepoint(rune(0xf0e5).str()) == 0xf0e5
	assert icon_text_codepoint('') == 0
}

fn test_icon_name_key_normalizes_to_letters_and_dashes() {
	assert icon_name_key('Home') == 'home'
	assert icon_name_key('my_icon') == 'my-icon'
	assert icon_name_key('  Home  ') == 'home'
	assert icon_name_key('a.b') == 'a-b'
	assert icon_name_key('---') == ''
}

// code_of unwraps a name lookup, so a test can compare a code point without
// repeating the guard at every call.
fn code_of(font IconFont, name string) int {
	return font.lookup(name) or { panic('the font does not carry ${name}') }
}

// ── Registry ───────────────────────────────────────────────────────

// register_test_font registers the bundled Material Icons face under `alias`.
// That file is in every build of `ui2`, so a test does not have to ship a font
// of its own, and it reports whether it could: a checkout without the assets
// skips the test rather than failing it.
fn register_test_font(alias string) bool {
	path := icon_test_font_path
	if !os.is_file(path) {
		return false
	}
	register_icon_font(alias, path) or { return false }
	return true
}

fn test_register_icon_font_reads_the_family_out_of_the_file() {
	// The bundled Material Icons face is the one font every build of `ui2` has,
	// so a test does not have to ship a file of its own to register one.
	if !os.is_file(icon_test_font_path) {
		return
	}
	font := register_icon_font('test_material', icon_test_font_path) or {
		assert false, 'the bundled icon font was not registered'
		return
	}
	assert font.alias == 'test_material'
	assert font.family == 'Material Icons'
	assert font.path == icon_test_font_path
	assert code_of(font, 'home') == 0xe88a
}

fn test_register_icon_font_rejects_a_file_it_cannot_read() {
	if _ := register_icon_font('test_missing', 'does/not/exist.ttf') {
		assert false, 'a missing font file was registered'
	}
	if _ := register_icon_font('test_text', '/etc/hostname') {
		assert false, 'a file that is not a font was registered'
	}
	if _ := register_icon_font('', '/etc/hostname') {
		assert false, 'an empty alias was accepted'
	}
}

fn test_icon_font_reports_a_registered_font_and_nothing_else() {
	_ := icon_font('no_such_alias')
	if _ := icon_font('no_such_alias') {
		assert false, 'a font that was never registered was found'
	}
	assert 'test_material' in icon_families()
}

fn test_icon_codepoint_is_nothing_for_an_unknown_name() {
	if !register_test_font('test_codepoint') {
		return
	}
	if home := icon_codepoint('test_codepoint', 'home') {
		assert home == 0xe88a
	} else {
		assert false, 'the bundled face does not carry home'
	}
	if _ := icon_codepoint('test_codepoint', 'no_such_icon') {
		assert false, 'a name the font does not carry was answered'
	}
	if _ := icon_codepoint('no_such_alias', 'home') {
		assert false, 'a font that was never registered was answered'
	}
}

// ── Elements ───────────────────────────────────────────────────────

// An icon is a label whose text is one private use code point, so the element
// needs no kind of its own and every measure, align and clip already written
// for a label applies to it.
fn test_icon_label_is_a_label_drawn_in_the_icon_font() {
	if !register_test_font('test_label') {
		return
	}
	el := icon_label('star', 'test_label', 'star', rect(0, 0, 24, 24), TextStyle{
		size: 20
	})
	assert el.kind == .label
	assert el.id == 'star'
	assert el.text == rune(0xe838).str()
	assert el.text_style.size == 20
	assert el.text_style.font_family == icon_test_font_path
	assert el.frame.width == 24.0
}

fn test_icon_label_of_an_unknown_name_draws_nothing() {
	if !register_test_font('test_unknown') {
		return
	}
	el := icon_label('star', 'test_unknown', 'no_such_icon', rect(0, 0, 24, 24), TextStyle{})
	// An empty label rather than a stray private use character, which would
	// draw whatever glyph happens to sit at that code point.
	assert el.text == ''
	assert el.text_style.font_family == ''
}

fn test_icon_run_puts_a_glyph_among_other_text() {
	if !register_test_font('test_run') {
		return
	}
	run := icon_run('test_run', 'star', TextStyle{
		size: 15
	})
	assert run.text == rune(0xe838).str()
	assert run.style.font_family == icon_test_font_path
	// The size is the caller's: an icon font is cut to fill its em square, so
	// the caller scales it, not this.
	assert run.style.size == 15.0
}

fn test_icon_run_of_an_unknown_name_is_empty() {
	if !register_test_font('test_run_missing') {
		return
	}
	run := icon_run('test_run_missing', 'no_such_icon', TextStyle{
		size: 15
	})
	assert run.text == ''
	assert run.style.font_family == ''
}

fn test_icon_image_path_round_trips() {
	path := icon_image_path('fa', 'star')
	assert path == 'icon:fa:star'
	if ref := parse_icon_image_path(path) {
		assert ref.alias == 'fa'
		assert ref.name == 'star'
	} else {
		assert false, 'an icon path did not parse'
	}
}

// A path that is not an icon is a file to load, and a caller has to be able to
// tell the two apart.
fn test_parse_icon_image_path_leaves_other_paths_alone() {
	if _ := parse_icon_image_path('symbol:gearshape') {
		assert false, 'a platform symbol was read as an icon font'
	}
	if _ := parse_icon_image_path('assets/logo.png') {
		assert false, 'an image file was read as an icon font'
	}
	if _ := parse_icon_image_path('icon:fa') {
		assert false, 'an icon path with no name was accepted'
	}
	if _ := parse_icon_image_path('icon::star') {
		assert false, 'an icon path with no alias was accepted'
	}
}

fn test_icon_button_names_its_image_the_way_a_symbol_is_named() {
	el := icon_button('add', 'fa', 'plus', 'Add', rect(0, 0, 100, 30), BoxStyle{},
		TextStyle{})
	assert el.kind == .button
	assert el.image_path == 'icon:fa:plus'
	assert el.text == 'Add'
	// No action of its own: an emitted tap is named after the id, which is what
	// every button without a separate action does.
	assert el.action_id == ''
}

fn test_icon_size_for_is_larger_than_the_body_text() {
	// An icon font is cut so its glyphs fill the em square where a text font
	// leaves the descender empty, so the same declared size reads smaller.
	assert icon_size_for(15.0) > 15.0
	assert icon_size_for(15.0) < 15.0 * 1.5
}
