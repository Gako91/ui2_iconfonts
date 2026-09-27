// An icon font ships its names in a stylesheet, and no two ship them the same
// way. Reading the stylesheet is therefore the only way to get a name for a
// glyph without a table the font's author never wrote. `parse_icon_css` reads
// the three layouts an icon package actually uses:
//
//	.fa-comment:before { content: "\f0e5" }        Font Awesome 4
//	.fas.fa-comment:before { content: "\f0e5" }     Font Awesome 5
//	.icon-home:before { content: "\e900" }          IcoMoon
//
// The rules of the first three all name one icon each, and the pseudo-element
// carries the code point as a CSS string.
//
// A font that spells its icons as *ligature text* has no code point in its
// stylesheet at all — the glyph comes from the font's own substitution table —
// so its names cannot be read this way. Such a font is given a table written by
// hand, or one generated from the code point list its package ships, and
// registered with `register_icon_font_with_map`.
//
// The functions here are deliberately free of file and font access, so the
// whole of the reading can be tested against the stylesheet text itself. The
// command that uses them is `tools/icond.v`.
module ui2

// parse_icon_css reads every icon a stylesheet names, keyed by the name with
// the package's own class prefix left off, so the three layouts above all give
// `comment` for the same icon. Names that appear twice keep the first code
// point: a stylesheet listing a name in two rules means one icon, and the
// later rule is usually a hover variant repeating the same content.
pub fn parse_icon_css(source string) map[string]int {
	mut icons := map[string]int{}
	for rule in icon_css_rules(source) {
		code := icon_css_content_code(icon_css_declaration(rule.body, 'content'))
		if !icon_css_is_icon_code(code) {
			continue
		}
		for name in icon_css_names(rule.selector) {
			// A name that already has a code point keeps the one it has. A
			// stylesheet that names an icon twice means one icon, and the later
			// rule is a weight or a state repeating the first — Font Awesome
			// lists `star` under `fas` and again under `far`, at two code points
			// for two faces of one name.
			if name !in icons {
				icons[name] = code
			}
		}
	}
	return icons
}

// IconCssRule is one `:before` rule of a stylesheet: what it selects and what
// it sets.
pub struct IconCssRule {
pub:
	selector string
	body     string
}

// icon_css_rules breaks a stylesheet into the rules that could carry an icon.
fn icon_css_rules(source string) []IconCssRule {
	mut rest := icon_css_strip_comments(source)
	mut rules := []IconCssRule{}
	for {
		open := rest.index('{') or { break }
		mut shut := rest[open..].index('}') or { break }
		shut += open
		selector := rest[..open]
		body := rest[open + 1..shut]
		rest = rest[shut + 1..]
		if !icon_css_is_icon_rule(selector, body) {
			continue
		}
		rules << IconCssRule{
			selector: selector
			body:     body
		}
	}
	return rules
}

// icon_css_strip_comments drops the commented-out rules. A commented rule is
// not a rule, and reading one would answer a name the package deliberately
// turned off. The blank left in its place matters: it is what keeps
// `.a:before{}.b:before{}` from becoming a selector for `.a:before{}.b`.
fn icon_css_strip_comments(source string) string {
	mut out := []u8{cap: source.len}
	mut rest := source
	for {
		start := rest.index('/*') or { break }
		mut stop := rest[start..].index('*/') or { break }
		stop += start
		out << rest[..start].bytes()
		out << ` `
		rest = rest[stop + 2..]
	}
	out << rest.bytes()
	return out.bytestr()
}

// icon_css_is_icon_rule keeps the rules that name a glyph. A stylesheet also
// carries the face itself — `.fa { font-family: FontAwesome }` — and the sizes
// and weights it is used at, none of which is an icon.
fn icon_css_is_icon_rule(selector string, body string) bool {
	if !selector.contains(':before') && !selector.contains('::before') {
		return false
	}
	return icon_css_declaration(body, 'content').len > 0
}

// icon_css_content_code reads the code point out of a `content` declaration,
// and nothing when the declaration names glyphs in words instead. The code point
// is written as an escape above U+007F, which is every icon in every package,
// so the first rune of the unquoted value is the one that carries it.
fn icon_css_content_code(declaration string) int {
	quoted := icon_css_unquote(declaration)
	if quoted.len == 0 {
		// `content: \f0e5`, which CSS also allows without the quotes.
		return icon_css_escape_code(declaration)
	}
	if quoted[0] == `\\` {
		return icon_css_escape_code(quoted)
	}
	return int(quoted.runes()[0])
}

// icon_css_is_icon_code says whether a code point is one an icon font keeps its
// glyphs at. The private use areas are the Unicode's own answer to "a character
// that means nothing but what this font says it means", which is what an icon is,
// and every icon font that ships a code point list uses one of them. This is what
// separates a code point from a word: a `content` reading `star` is a ligature
// the font substitutes, not a glyph, and no amount of reading will turn it into a
// code point.
fn icon_css_is_icon_code(code int) bool {
	return (code >= 0xe000 && code <= 0xf8ff) || (code >= 0xf0000 && code <= 0xffffd)
		|| (code >= 0x100000 && code <= 0x10fffd)
}

// icon_css_declaration returns the value a stylesheet sets for `property` in a
// rule body, or an empty string when it does not set it.
fn icon_css_declaration(body string, property string) string {
	mut wanted := property + ':'
	mut from := 0
	for {
		mut at := body[from..].index(wanted) or { return '' }
		at += from
		// `content` also starts the name of `content-type`, and a property is
		// only one when nothing but whitespace precedes its colon.
		if at == 0 || body[at - 1] == ` ` || body[at - 1] == `\t` || body[at - 1] == `\n`
			|| body[at - 1] == `;` {
			mut value := body[at + wanted.len..].trim_left(' \t\n\r')
			stop := value.index(';') or { value.len }
			return value[..stop].trim(' \t\n\r')
		}
		from = at + wanted.len
	}
	// The loop above only leaves through a return. The line is here because a
	// compiler that does not see `for {}` as endless needs the function to end
	// in a return of its own, and an empty one is the same answer.
	return ''
}

// icon_css_unquote removes the quotes a CSS string is written in, and the
// whitespace inside them, which CSS allows but no package writes.
fn icon_css_unquote(value string) string {
	body := if value.len > 1 && value[0] == `'` && value[value.len - 1] == `'` {
		value[1..value.len - 1]
	} else if value.len > 1 && value[0] == `"` && value[value.len - 1] == `"` {
		value[1..value.len - 1]
	} else {
		return ''
	}
	return body.trim(' \t\n\r')
}

// icon_css_escape_code reads a CSS escape, which is a backslash followed by up
// to six hexadecimal digits. `\f0e5` is the whole of what an icon package
// writes this way, but the shorter form is legal too and a stylesheet that used
// it would otherwise be read as no icon at all.
fn icon_css_escape_code(value string) int {
	if value.len == 0 || value[0] != `\\` {
		return 0
	}
	return parse_icon_hex(value[1..])
}

// icon_css_names lists the icons a selector names, with the package's class
// prefix taken off. A selector carries more than one class — Font Awesome 5
// writes `.fas.fa-star`, where `fas` is the weight and `fa-star` the icon —
// and only the classes that name an icon are read, which is decided by the
// prefixes an icon package writes them with.
fn icon_css_names(selector string) []string {
	mut names := []string{}
	for raw in selector.split(',') {
		rule := icon_css_selector_classes(raw)
		if rule.len == 0 {
			continue
		}
		mut best := ''
		for part in rule.split('.') {
			for word in part.split(' ') {
				candidate := word.trim(' \t\n\r')
				if candidate.len == 0 {
					continue
				}
				name := icon_css_strip_prefix(candidate)
				if name.len == 0 {
					continue
				}
				// `.fas` names the weight and `fa-comment` the icon, and the
				// longer name is the icon, so the longest match wins.
				if name.len > best.len {
					best = name
				}
			}
		}
		key := icon_name_key(best)
		if key.len > 0 && key !in names {
			names << key
		}
	}
	return names
}

// icon_css_selector_classes reduces one selector to the part holding the icon's
// classes. The pseudo-elements and pseudo-classes are dropped: `.fa-star:before`
// and `.fa-star:hover:before` both name the same icon, and reading the `:hover`
// as part of the name would answer a second name that nothing draws.
fn icon_css_selector_classes(selector string) string {
	mut out := []u8{cap: selector.len}
	for c in selector {
		if c == `:` {
			break
		}
		out << c
	}
	return out.bytestr().trim(' \t\n\r')
}

// icon_css_strip_prefix takes the package's class prefix off an icon name.
fn icon_css_strip_prefix(class string) string {
	for prefix in icon_name_prefixes {
		if class.starts_with(prefix) {
			return class[prefix.len..]
		}
	}
	return class
}
