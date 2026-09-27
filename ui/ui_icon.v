// An icon font carries its glyphs in the private use area of Unicode, where
// nothing else is written, so the only way to ask for a named one is to know
// which code point behind the name is. Every icon font package ships that list
// in a stylesheet, and every one of them names it differently: Font Awesome 4
// writes `.fa-comment:before { content: "\f0e5" }`, Font Awesome 5 writes
// `.fas.fa-comment:before`, and IcoMoon writes `.icon-comment:before`. `ui2`
// reads all three, so a name is the same thing here whatever the package it
// came from.
//
// A font that spells its icons as ligature text is the one shape with nothing to
// read: a stylesheet for it says no code point at all, because the glyph comes
// out of the font's own substitution table. That one needs a table written by
// hand or generated from a code point list the package ships.
//
// A registered font is a file plus that table. The two are kept together
// because neither is useful alone: the table says which code point to draw and
// the file says what it looks like, and an element needs both. Nothing here
// asks a platform to resolve a family by name, because a font shipped beside a
// binary is not installed on the machine running it: AppKit and Win32 name a
// face by the string inside the file, and neither of them looks in a
// directory the application owns.
@[has_globals]
module ui2

import json2
import os
import sync

// IconFont is one registered icon font.
pub struct IconFont {
pub:
	// alias is the short name it is registered and referred to by, and is what
	// an `icon:<alias>:<name>` image path names.
	alias string
	// family is the name the file gives itself, which is how the native
	// backends ask for it once it is installed for the process.
	family string
	// path is the font file, and is what the custom renderer hands to fontstash.
	path string
	// icons maps a name to the code point that draws it.
	icons map[string]int
}

// lookup reports the code point for `name`, accepting the prefixes an icon
// package writes in front of it so `fa-comment`, `icon-comment` and `comment`
// are the same icon.
pub fn (font IconFont) lookup(name string) ?int {
	key := icon_name_key(name)
	if code := font.icons[key] {
		return code
	}
	for prefix in icon_name_prefixes {
		if key.starts_with(prefix) {
			if code := font.icons[key[prefix.len..]] {
				return code
			}
		}
	}
	return none
}

// IconFontRegistry holds the fonts an application registered. Registration
// happens while a program sets itself up, on the thread that starts it, and
// reading happens on whichever thread draws; a mutex is what keeps the two
// from meeting halfway through a map write.
@[heap]
struct IconFontRegistry {
	mutex &sync.Mutex = sync.new_mutex()
mut:
	// fonts is keyed by alias. More than one font may carry the same names —
	// the two Font Awesome weights do, for instance — so the alias is what
	// tells them apart.
	fonts map[string]IconFont
	// names holds the tables an application added itself, keyed by family and
	// name together as `family\x1fname`. It comes before the tables `ui2`
	// ships, so an application that knows a font better than the shipped table
	// can say so.
	//
	// One flat map rather than a family key holding a name map. A map of maps
	// cannot be read by the compilers V falls back to when a C name collides on
	// the way to a backend, and a table that only some machines can read is a
	// table that is wrong on the others.
	names map[string]int
}

__global g_icon_fonts = &IconFontRegistry{
	fonts:  map[string]IconFont{}
	names:   map[string]int{}
}

// icon_name_prefixes are the class prefixes the icon packages write. They are
// stripped from a name before it is looked up, so the same name reads the same
// whether it was written as `fa-star`, `icon-star`, `glyphicon-star` or `star`.
const icon_name_prefixes = ['fa-', 'fas-', 'far-', 'fal-', 'fad-', 'icon-',
	'glyphicon-', 'ico-', 'mdi-']

// icon_name_key normalizes a name down to letters, digits and dashes, so
// `Home`, `home` and ` home ` are the same icon. A dash the name already carries
// is kept, because the packages write their multi-word names with one:
// `comment-alt` is one name and not two words run together.
//
// It is public because a generated table has to be keyed the way a lookup is
// keyed. A table holding `help_outline` and a lookup for `help-outline` are the
// same name written twice, and one of the two spellings has to be chosen or a
// name the font ships is a name nothing finds.
pub fn icon_name_key(name string) string {
	mut out := []u8{cap: name.len}
	mut last_dash := false
	for c in name.to_lower() {
		if c == `-` {
			if out.len > 0 && !last_dash {
				out << `-`
				last_dash = true
			}
			continue
		}
		if c == ` ` || c == `_` || c == `.` {
			if out.len > 0 && !last_dash {
				out << `-`
				last_dash = true
			}
			continue
		}
		if (c >= `a` && c <= `z`) || (c >= `0` && c <= `9`) {
			out << c
			last_dash = false
		}
	}
	if out.len > 0 && out[out.len - 1] == `-` {
		out = out[..out.len - 1]
	}
	return out.bytestr()
}

// ── Registration ───────────────────────────────────────────────────

// register_icon_font makes an icon font available under `alias`, resolving the
// family the file gives itself. The names it answers to are the ones `ui2`
// ships for that family, or, for a font it ships nothing for, the ones the file
// can already be drawn with on this machine — see `icon_font_for_family`.
//
// The file is only read, never installed, so nothing outside the process
// changes. The native backends install it for themselves when they first need
// to draw it.
pub fn register_icon_font(alias string, ttf string) !IconFont {
	return register_icon_font_with_map(alias, ttf, '')
}

// register_icon_font_with_map registers a font whose names are read from a
// table written by `tools/icond.v`. An empty `map_file` falls back to the table
// `ui2` ships for that family.
pub fn register_icon_font_with_map(alias string, ttf string, map_file string) !IconFont {
	if alias.len == 0 {
		return error('an icon font needs an alias to be registered under')
	}
	if !os.is_file(ttf) {
		return error('icon font file not found: ${ttf}')
	}
	family := font_file_family(ttf)!
	mut icons := map[string]int{}
	if map_file.len > 0 {
		icons = read_icon_map(map_file)!
	} else {
		icons = builtin_icon_map(family)
	}
	font := IconFont{
		alias:  alias
		family: family
		path:   ttf
		icons:  icons
	}
	g_icon_fonts.mutex.lock()
	g_icon_fonts.fonts[alias] = font
	g_icon_fonts.mutex.unlock()
	return font
}

// register_builtin_icon_font records a table for a family `ui2` ships nothing
// for, so a face the machine already has installed answers to names without the
// application having to carry the file. It is how a font the project does not
// vendor — Bootstrap Icons, an icon set of the application's own — gets its
// names in.
pub fn register_builtin_icon_font(alias string, family string, icons map[string]int) {
	key := icon_name_key(family)
	g_icon_fonts.mutex.lock()
	for name, code in icons {
		g_icon_fonts.names['${key}\x1f${name}'] = code
	}
	g_icon_fonts.mutex.unlock()
}

// builtin_icon_map returns the names a family answers to, or an empty map when
// nothing is known about it. A font the application brought itself still draws
// without a table here; it simply has no names to answer to yet.
pub fn builtin_icon_map(family string) map[string]int {
	key := icon_name_key(family)
	if key.len == 0 {
		return map[string]int{}
	}
	mut table := map[string]int{}
	g_icon_fonts.mutex.lock()
	for name, code in g_icon_fonts.names {
		if name.len > key.len + 1 && name[..key.len] == key && name[key.len] == `\x1f` {
			table[name[key.len + 1..]] = code
		}
	}
	g_icon_fonts.mutex.unlock()
	if table.len > 0 {
		return table
	}
	return shipped_icon_map(key)
}

// shipped_icon_map is the table `ui2` ships for a family it ships a face for.
// The key is the family as `icon_name_key` writes it, so `Material Icons` and
// `material-icons` reach the same arm. A family with no arm has no shipped
// names, which is not an error: the font may be one the application brought.
fn shipped_icon_map(key string) map[string]int {
	match key {
		'material-icons' {
			return material_icon_table()
		}
		else {
			return map[string]int{}
		}
	}
}

// icon_font_file_for_family returns the file behind a family name, for a face
// `ui2` knows about and the system index would not find: a font shipped beside
// a binary is not installed on the machine running it. An empty result means
// nothing is known about the family, and the caller should ask the system.
pub fn icon_font_file_for_family(family string) string {
	if font := icon_font_for_family(family) {
		if font.path.len > 0 {
			return font.path
		}
	}
	// A face `ui2` ships is answerable by family without ever having been
	// registered, and a program asking only about a family is asking about a
	// style, not about an alias.
	if builtin_icon_map(family).len > 0 {
		return material_icon_path_if_family(icon_name_key(family))
	}
	return ''
}

// material_icon_path_if_family returns the bundled face's file, and nothing for
// any other family: a family with a shipped table but no shipped file is a font
// the machine is expected to have.
fn material_icon_path_if_family(key string) string {
	if key == icon_name_key(material_icon_family) {
		return material_icon_path
	}
	return ''
}

// shipped_icon_fonts is the icon font `ui2` ships, with the names the package
// lists for it. It is bundled so that a name resolves and draws on a machine
// where no icon font is installed, which is what an example in this repository
// has to be able to do.
//
// Shipping a second face means adding it to this list: nothing else in the
// library names a particular font.
pub fn shipped_icon_fonts() []IconFont {
	return [material_icon_font()]
}

// material_icon_font is the Material Icons face this repository ships, with the
// 2234 names the Material Icons package lists for it. It is registered under
// `material`, which is the alias a name is written with when nothing else says
// otherwise.
//
// The table is built once and held. Building it costs 2234 insertions, and every
// label carrying an icon asks for it.
__global g_material_icons = map[string]int{}

fn material_icon_table() map[string]int {
	if g_material_icons.len == 0 {
		g_material_icons = material_icons()
	}
	return g_material_icons
}

pub fn material_icon_font() IconFont {
	return IconFont{
		alias:  'material'
		family: material_icon_family
		path:   material_icon_path
		icons:  material_icon_table()
	}
}

// material_icon_family and material_icon_path are the name the bundled face
// gives itself and where the file is, which the native backends need: AppKit
// and Win32 both identify a face by the name inside the file once it has been
// loaded, and the immediate renderer wants the file itself.
pub const material_icon_family = 'Material Icons'

pub const material_icon_path = @VMODROOT + '/assets/fonts/MaterialIcons-Regular.ttf'

// read_icon_map reads a generated icon table. The format is a JSON object
// mapping a name to its code point, either as a number or as the string the
// stylesheet wrote it as, so both of these are the same table:
//
//	{"home": 59530}
//	{"home": "\\ue88a"}
//
// The numbers are decimal, because JSON has no hexadecimal literal: a `0xe88a`
// written into a JSON file is not JSON at all, and a table that claims to be
// JSON has to be readable by a JSON reader.
pub fn read_icon_map(path string) !map[string]int {
	raw := os.read_file(path)!
	mut icons := map[string]int{}
	// The number form is what `tools/icond.v` writes; the string form is what a
	// hand-written table tends to hold, because the code point can be pasted out
	// of the stylesheet without being read as a number.
	if table := json2.decode[map[string]int](raw) {
		for name, code in table {
			key := icon_name_key(name)
			if key.len > 0 {
				icons[key] = code
			}
		}
		return icons
	}
	for name, value in json2.decode[map[string]string](raw)! {
		key := icon_name_key(name)
		if key.len > 0 {
			icons[key] = icon_text_codepoint(value)
		}
	}
	return icons
}

// icon_text_codepoint reads the code point out of the way a stylesheet writes
// one: `content: "\f0e5"`. The escape is what a stylesheet uses for a code point
// above U+007F, so a table read back from CSS carries it rather than the
// character itself. The digits are hexadecimal: a leading `f` is how a package
// keeps the glyphs clear of the letters, and it is not a decimal digit.
fn icon_text_codepoint(text string) int {
	mut body := text.trim(' \t\n\r')
	if body.len > 1 && body[0] == `"` && body[body.len - 1] == `"` {
		body = body[1..body.len - 1]
	}
	if body.len == 0 {
		return 0
	}
	if body[0] == `\\` {
		return parse_icon_hex(body[1..])
	}
	return int(body.runes()[0])
}

// parse_icon_hex reads a code point out of the hexadecimal digits a package
// writes it as. A stylesheet writes `\f0e5` with no `u` in front of it, a code
// point list writes `e951` with nothing in front of it at all, and some write
// `\ue900`; the digits run to the first character that is not one of them, six
// at most, which is what CSS allows and what a code point can need.
//
// The digits are accumulated by hand because a leading `f` is how a package
// keeps its glyphs clear of the letters, and a leading `f` is not a decimal
// digit: `int('e951')` would answer a number that has nothing to do with the
// glyph.
//
// This is public because the command that writes a table has to read the same
// numbers the library does, and two readers of one format is one too many.
pub fn parse_icon_hex(digits string) int {
	mut hex := digits
	if hex.len > 0 && (hex[0] == `u` || hex[0] == `U`) {
		hex = hex[1..]
	}
	mut value := 0
	mut read := 0
	for read < hex.len && read < 6 {
		digit := icon_hex_digit(hex[read])
		if digit < 0 {
			break
		}
		value = value * 16 + digit
		read++
	}
	return value
}

// icon_hex_digit is one hexadecimal digit's value, or -1 for anything else.
fn icon_hex_digit(c u8) int {
	if c >= `0` && c <= `9` {
		return int(c - `0`)
	}
	if c >= `a` && c <= `f` {
		return int(c - `a`) + 10
	}
	if c >= `A` && c <= `F` {
		return int(c - `A`) + 10
	}
	return -1
}

// ── Lookup ─────────────────────────────────────────────────────────

// icon_font returns the font registered under `alias`.
//
// An alias the application never registered can still be one of the faces
// `ui2` ships, and the bundled Material Icons face is registered under
// `material` from the first call. That is what lets `icon: home` — a name with
// no setup behind it — draw on a machine that has never had an icon font
// installed, and it is why a program that ships its own face under the same
// alias overrides the bundled one by registering it.
pub fn icon_font(alias string) ?IconFont {
	g_icon_fonts.mutex.lock()
	mut font := g_icon_fonts.fonts[alias]
	g_icon_fonts.mutex.unlock()
	if font.path.len > 0 {
		return font
	}
	for shipped in shipped_icon_fonts() {
		if shipped.alias == alias {
			return shipped
		}
	}
	return none
}

// icon_families lists the aliases that answer, which is the ones registered plus
// the ones shipped, so a settings screen can offer them without keeping its own
// list in step with the registration calls.
pub fn icon_families() []string {
	g_icon_fonts.mutex.lock()
	mut aliases := g_icon_fonts.fonts.keys()
	g_icon_fonts.mutex.unlock()
	for shipped in shipped_icon_fonts() {
		if shipped.alias !in aliases {
			aliases << shipped.alias
		}
	}
	aliases.sort()
	return aliases
}

// icon_font_for_family finds a registered font by the family its file gives
// itself, which is what an element that only knows a `font_family` string has
// to work from: a style carries a family and no alias, and the alias is what
// the registry is keyed by.
pub fn icon_font_for_family(family string) ?IconFont {
	key := icon_name_key(family)
	if key.len == 0 {
		return none
	}
	g_icon_fonts.mutex.lock()
	mut found := ?IconFont{}
	for _, font in g_icon_fonts.fonts {
		if icon_name_key(font.family) == key {
			found = font
			break
		}
	}
	g_icon_fonts.mutex.unlock()
	return found
}

// icon_codepoint returns the code point `name` draws in the font registered
// under `alias`, and nothing when the font does not carry that name. Returning
// nothing rather than a wrong code point is deliberate: a code point from the
// wrong font draws a different glyph rather than nothing at all, so a caller
// that ignored the result would get a plausible icon that is not the one it
// asked for.
pub fn icon_codepoint(alias string, name string) ?int {
	font := icon_font(alias) or { return none }
	return font.lookup(name)
}

// icon_name returns the single character that draws `name` in the font
// registered under `alias`. It is the bare glyph, with no family attached, so
// a caller that only wants to append it to a string uses this; a caller
// drawing it needs `icon_style` or `icon_label` as well, since a code point
// says nothing about which file draws it.
pub fn icon_name(alias string, name string) string {
	code := icon_codepoint(alias, name) or { return '' }
	return rune(code).str()
}

// icon_style is the style that draws `name` from the font registered under
// `alias`, for a run of text among other text. An unknown name yields `style`
// unchanged, so a missing icon draws as text rather than as a stray private use
// character.
pub fn icon_style(alias string, name string, style TextStyle) TextStyle {
	font := icon_font(alias) or { return style }
	_ := font.lookup(name) or { return style }
	return TextStyle{
		...style
		font_family: icon_font_path(font)
	}
}

// icon_run is `name` as a rich text run, for putting an icon inside a sentence
// without the rest of it being drawn in the icon font.
pub fn icon_run(alias string, name string, style TextStyle) TextRun {
	font := icon_font(alias) or { return TextRun{ text: '', style: style } }
	code := font.lookup(name) or { return TextRun{ text: '', style: style } }
	return TextRun{
		text:  rune(code).str()
		style: TextStyle{
			...style
			font_family: icon_font_path(font)
		}
	}
}

// icon_font_path is what a renderer hands its text stack for `font`. The
// custom renderer reads `TextStyle.font_family` as a path and loads the file
// itself; the native backends want the family name, and resolve the file
// through the g_icon_fonts. Handing both the path is what lets one element cross
// every backend unchanged.
pub fn icon_font_path(font IconFont) string {
	return if font.path.len > 0 { font.path } else { font.family }
}

// ── Elements ───────────────────────────────────────────────────────

// icon_label is a label drawing one icon, which is all an icon is: a label
// whose text is a single private use code point drawn in an icon font. The
// element is a `.label` like any other, so it is measured, aligned, clipped
// and reconciled by the code already written for those, and adding a new
// `Kind` to the enum would have bought nothing.
pub fn icon_label(id string, alias string, name string, frame Rect, style TextStyle) Element {
	font := icon_font(alias) or { return label(id, '', frame, style) }
	code := font.lookup(name) or { return label(id, '', frame, style) }
	return label(id, rune(code).str(), frame, TextStyle{
		...style
		font_family: icon_font_path(font)
	})
}

// icon_image_path names an icon for the `image_path` of a control, in the same
// way `symbol:<name>` names a platform symbol: `icon:<alias>:<name>`. A button
// draws one where it would draw an image, so an icon-only button and a
// button-with-a-label are the same control.
pub fn icon_image_path(alias string, name string) string {
	return 'icon:${alias}:${name}'
}

// IconRef is an icon named on an `image_path`: which registered font, and which
// name inside it.
pub struct IconRef {
pub:
	alias string
	name  string
}

// parse_icon_image_path reads what `icon_image_path` wrote, and nothing for a
// path that is not an icon, so a caller can tell one from a file to load.
fn parse_icon_image_path(path string) ?IconRef {
	prefix := 'icon:'
	if !path.starts_with(prefix) {
		return none
	}
	parts := path[prefix.len..].split(':')
	if parts.len != 2 || parts[0].len == 0 || parts[1].len == 0 {
		return none
	}
	return IconRef{
		alias: parts[0]
		name:  parts[1]
	}
}

// icon_button is a button whose image is an icon rather than a file, drawn
// beside its title the way a button with an image is. On a custom-rendered
// desktop the icon is drawn as text in the icon font; the native backends use
// the platform's own way of putting a glyph beside a title.
pub fn icon_button(id string, alias string, name string, title string, frame Rect, box_ BoxStyle, style TextStyle) Element {
	return button_with_image(id, title, icon_image_path(alias, name), frame, box_, style)
}

// icon_size_for returns the point size an icon of `height` tall should be
// declared at, which is what makes an icon line up with the text beside it. An
// icon font is cut so its glyphs fill the em square, where a text font leaves
// the descender empty, so an icon drawn at the body size reads smaller than
// the text around it and has to be declared larger.
pub fn icon_size_for(body_size f64) f64 {
	return body_size * 1.2
}
