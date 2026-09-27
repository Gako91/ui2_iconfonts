// icond turns an icon font's names into a table the `ui2` registry can answer
// from, so a program can ask for `home` and be given the character the font
// draws it with.
//
// An icon font ships its names in a stylesheet or in a list of code points, and
// the two packages that matter spell them differently:
//
//	v run tools/icond.v -alias material -ttf assets/fonts/MaterialIcons-Regular.ttf \
//		-codepoints MaterialIcons-Regular.codepoints -out ui/icons_material.v
//	v run tools/icond.v -alias fa -ttf /path/to/fontawesome.css -out fa.json
//
// The two inputs are read differently on purpose. A stylesheet is parsed by
// `ui2.parse_icon_css`, which knows the layouts the icon packages write. A code
// point list is one name and one hexadecimal code per line, which is the shape
// the Material Icons package ships and the shape `tools/icond.v` writes back out.
//
// Output is a V module by default, because that is what a program in this
// repository wants: no file to read at startup, and no table to keep in step with
// the font. `-out` ending in `.json` writes the table `ui2.read_icon_map` reads
// instead, for a font that is not in this repository and so is not compiled in.
module main

import os

import ui2

// IcondOpts is what the command line asks for.
struct IcondOpts {
	mut:
	// alias is the name a program registers the font under.
	alias string = 'material'
	// ttf is the font file, recorded in the table so the font can be drawn.
	ttf string
	// codepoints and css are the two ways a package names its glyphs. At most
	// one is needed; both may be given when a package ships both.
	codepoints string
	css string
	// out is where the table is written. A `.json` suffix writes the table
	// `ui2.read_icon_map` reads; anything else writes a V module.
	out string = 'ui/icons_material.v'
	// pkg is the module a generated V file declares itself as.
	pkg string = 'ui2'
}

fn main() {
	mut opts := IcondOpts{}
	mut positional := []string{}
	args := os.args[1..]
	mut i := 0
	for i < args.len {
		flag := args[i]
		match flag {
			'-alias' {
				i++
				opts.alias = icond_value(args, i, flag)
			}
			'-ttf' {
				i++
				opts.ttf = icond_value(args, i, flag)
			}
			'-codepoints' {
				i++
				opts.codepoints = icond_value(args, i, flag)
			}
			'-css' {
				i++
				opts.css = icond_value(args, i, flag)
			}
			'-out' {
				i++
				opts.out = icond_value(args, i, flag)
			}
			'-pkg' {
				i++
				opts.pkg = icond_value(args, i, flag)
			}
			'-h', '--help' {
				icond_usage()
				return
			}
			else {
				if flag.starts_with('-') {
					eprintln('icond: unknown flag ${flag}')
					icond_usage()
					exit(1)
				}
				positional << flag
			}
		}
		i++
	}
	// `icond.v font.css` is the short form of naming the stylesheet.
	if opts.css.len == 0 && opts.codepoints.len == 0 && positional.len > 0 {
		opts.css = positional[0]
	}
	if opts.ttf.len == 0 {
		eprintln('icond: the font file is needed, pass -ttf')
		exit(1)
	}
	mut icons := map[string]int{}
	if opts.codepoints.len > 0 {
		mut names := parse_code_point_list(os.read_file(opts.codepoints)!)
		for name, code in names {
			icons[name] = code
		}
	}
	if opts.css.len > 0 {
		// A stylesheet is read by the same code the library uses, so a name read
		// here is a name `ui2` can look up afterwards.
		mut names := ui2.parse_icon_css(os.read_file(opts.css)!)
		for name, code in names {
			icons[name] = code
		}
	}
	if icons.len == 0 {
		eprintln('icond: no icon names were read, is the stylesheet the right file?')
		exit(1)
	}
	table := write_table(opts, icons)
	if opts.out.ends_with('.json') {
		os.write_file(opts.out, table)!
	} else {
		os.write_file(opts.out, table)!
	}
	println('icond: ${icons.len} names -> ${opts.out}')
}

// icond_value reads the argument that follows a flag, saying which one is
// missing rather than reading past the end of the command line.
fn icond_value(args []string, i int, flag string) string {
	if i >= args.len {
		eprintln('icond: ${flag} needs a value')
		exit(1)
	}
	return args[i]
}

// parse_code_point_list reads the one-name-one-code-per-line form the Material
// Icons package ships:
//
//	10k e951
//	ac-unit efb3
//
// The codes are hexadecimal, and the leading `e` or `f` that keeps a glyph clear
// of the letters is part of the code rather than a marker. Anything after the
// code is not a name and is not read: the list is a mapping, not a sentence.
fn parse_code_point_list(source string) map[string]int {
	mut icons := map[string]int{}
	for line in source.split_into_lines() {
		text := line.trim(' \t\n\r')
		if text.len == 0 || text.starts_with('#') {
			continue
		}
		parts := text.split_any(' \t')
		mut name := ''
		mut code_text := ''
		for part in parts {
			if part.len == 0 {
				continue
			}
			if name.len == 0 {
				name = part
			} else if code_text.len == 0 {
				code_text = part
			}
		}
		if name.len == 0 || code_text.len == 0 {
			continue
		}
		code := ui2.parse_icon_hex(code_text)
		if code == 0 {
			continue
		}
		// The key is normalized the way a lookup is normalized, so a package
		// that writes `help_outline` and an application that writes
		// `help-outline` reach the same glyph. The Material Icons list alone
		// spells two hundred of its names with an underscore.
		key := ui2.icon_name_key(name)
		if key.len == 0 {
			continue
		}
		icons[key] = code
	}
	return icons
}

// write_table writes the table in the shape `opts.out` asks for: a V module
// holding the names in a constant, or the JSON `ui2.read_icon_map` reads. The
// two hold the same numbers, so a table written as one can be checked against
// the other.
fn write_table(opts IcondOpts, icons map[string]int) string {
	mut names := icons.keys()
	names.sort()
	table := name_hint(opts.alias)
	if opts.out.ends_with('.json') {
		mut out := '{'
		for i, name in names {
			if i > 0 {
				out += ','
			}
			out += '\n\t"${name}": ${icons[name]}'
		}
		return out + '\n}\n'
	}
	// The table is written as assignments rather than as a map literal. A map
	// literal is newer than the compilers V falls back to when a C name collides
	// on the way to a backend, and a table only some machines can read is a table
	// that is wrong on the others.
	mut out := '// ${table} names, as a table.\n'
	out += '//\n'
	out += '// Generated by tools/icond.v. Do not edit: the next run overwrites this file, and\n'
	out += '// a hand edit would be lost without anyone being told it was wrong.\n'
	out += '// To write it again:\n'
	out += '//   v run tools/icond.v -alias ${opts.alias} -ttf ${opts.ttf} -codepoints <the package list> -out ${opts.out}\n'
	out += 'module ${opts.pkg}\n'
	out += '\n'
	out += '// ${table}_icons returns a name to the code point its glyph sits at. The code\n'
	out += '// points are hexadecimal, which is the way the package that shipped them\n'
	out += '// writes them. There are ${names.len} of them.\n'
	out += 'pub fn ${table}_icons() map[string]int {\n'
	out += '\tmut icons := map[string]int{}\n'
	for name in names {
		out += "\ticons['${name}'] = 0x${hex4(icons[name])}\n"
	}
	out += '\treturn icons\n'
	out += '}\n'
	return out
}

// hex4 writes a code point as at least four hexadecimal digits, which is the
// width a private use code point is written at everywhere else.
fn hex4(code int) string {
	mut text := code.hex()
	for text.len < 4 {
		text = '0' + text
	}
	return text
}

// name_hint turns an alias into something usable as a V identifier.
fn name_hint(alias string) string {
	mut out := []u8{cap: alias.len}
	for c in alias.to_lower() {
		if (c >= `a` && c <= `z`) || (c >= `0` && c <= `9`) {
			out << c
		} else {
			out << `_`
		}
	}
	return out.bytestr()
}

// icond_usage prints the command line, one line at a time. A tool whose own help
// is hard to read is a tool nobody runs twice.
fn icond_usage() {
	println('icond - write an icon name table for the ui2 registry')
	println('')
	println('  v run tools/icond.v -ttf FONT.ttf (-css STYLE.css | -codepoints LIST) -out FILE')
	println('')
	println('  -alias NAME       the name a program registers the font under (material)')
	println('  -ttf PATH         the icon font itself, recorded in the table')
	println('  -css PATH         a stylesheet to read the names from')
	println('  -codepoints PATH  a one-name-one-hex-code-per-line list to read from')
	println('  -out PATH         the table to write; a .json name writes what')
	println('                    ui2.read_icon_map reads instead of a V module')
	println('  -pkg NAME         the module name of a generated V file (ui2)')
	println('')
	println('  A font that spells its icons as ligature text holds no code point to')
	println('  read, and needs a table written by hand.')
}
