package flag

import "core:fmt"
import "core:intrinsics"
import "core:os"
import "core:reflect"
import "core:strconv"
import "core:strings"
import "core:unicode"
import "core:runtime"
import "core:path/filepath"

Command :: struct($Command_Type: typeid) where intrinsics.type_is_enum(Command_Type) {
	type:        Command_Type,
	name:        string,
	description: string,
}

// just Bindings
Bindings :: union {
	Binding_Boolean,
	Binding_Integer,
	Binding_String,
	Binding_Dynamic_Array, // [dynamic]string
	Binding_Map, // map[string]string
	Binding_Enum,
}

// -name:argument
Flag :: struct($Command_Type: typeid) where intrinsics.type_is_enum(Command_Type) {
	name:        string,
	binding:     Bindings,
	description: string,
	commands:    bit_set[Command_Type], // supported_commands? has?
}

Error_Code :: enum {
	Ok,
	Help_Text,
	Invalid_Command, // command not found
	Invalid_Flag, // flag not found
	Invalid_Argument, // flag was found but it has an invalid argument
}

Error :: struct {
	code:    Error_Code,
	message: string,
}

Error_Handling :: enum {
	Exit_On_Error,
	Return_On_Error,
	Assert_On_Error,
}

parse_args :: proc {
	parse_args_commands,
	parse_args_flags,
}

parse_args_flags :: proc(
	flags: []Flag($E),
	args: []string = nil,
	mode: Error_Handling = .Exit_On_Error,
) -> (
	err: Error,
) where intrinsics.type_is_enum(E) {
	_, err = parse_args_commands(E, nil, flags, args, mode)
	return
}

parse_args_commands :: proc(
	$E: typeid,
	commands: []Command(E),
	flags: []Flag(E),
	args: []string = nil,
	error_handling: Error_Handling = .Exit_On_Error,
) -> (
	command: E,
	err: Error,
) where intrinsics.type_is_enum(E) {
	command, err = _parse_args_commands(E, commands, flags, args if args != nil else os.args)
	if err.code != .Ok {
		fmt.eprintln(err.message)
		switch error_handling {
		case .Exit_On_Error:
			os.exit(2 if err.code != .Help_Text else 0)
		case .Return_On_Error:
			return
		case .Assert_On_Error:
			assert(false, err.message)
		}
	}
	return
}

@(private)
_parse_args_commands :: proc(
	$E: typeid,
	commands: []Command(E),
	flags: []Flag(E),
	args: []string,
) -> (
	command_type: E,
	err: Error,
) where intrinsics.type_is_enum(E) {
	// requires:
	//   1 <= len(args)
	//   args[0]: executable file name

	i := 1

	command: Command(E)

	if 0 < len(commands) {
		// exe <command>
		// exe help
		// exe help <command>
		if !(i < len(args))  {
			err = {.Help_Text, commands_help_text(args[0], commands)}
			return
		}
		show_help := false
		if args[i] == "help" {
			i += 1
			show_help = true
			if !(i < len(args))  {
				err = {.Help_Text, commands_help_text(args[0], commands)}
				return
			}
		}
		for c in commands {
			if (c.name == args[i]) {
				command = c
				break
			}
		}
		if command.name == "" {
			err =  {
				.Invalid_Command,
				fmt.tprintf(
					"flag: command '%v' not found\n%v",
					args[i],
					commands_help_text(args[0], commands),
				),
			}
			return
		} else if (show_help) {
			err = {.Help_Text, flags_help_text(args[0], command, flags)}
			return
		}
		i += 1
	}

	if 0 < len(flags) {
		n: int
		for ; i < len(args); i += n {
			n = 1
			arg := args[i]
			when ODIN_OS == .Windows {
				// Windows /nuisance
				if strings.has_prefix(arg, "/") {
					fmt.eprintf(
						"warn: %v is never interpreted as a flag, use -%v instead\n",
						arg,
						arg[1:],
					)
					continue
				}
			}
			if strings.has_prefix(arg, "-") {
				arg = arg[1:]
				if strings.has_prefix(arg, "-") {
					arg = arg[1:]
					if strings.has_prefix(arg, "-") {
						err = {.Invalid_Flag, fmt.tprintf("flag: too many - in %v", args[i])}
						return
					}
				}

				// arg is now a flag name

				j := strings.index_rune(arg, ':')
				k := strings.index_rune(arg, '=')

				name: string
				val: string

				if j != -1 && k == -1 {
					// -flag:foo
					name = arg[:j]
					val = arg[j + 1:]
				} else if j == -1 && k != -1 {
					// -flag=foo (unconventional?)
					name = arg[:k]
					val = arg[k + 1:]
				} else if j < k {
					// -flag:foo=bar
					name = arg[:j]
					val = arg[j + 1:]
				} else if k < j {
					// -flag=foo:bar (unconventional)
					fmt.eprintf(
						"warn: %v is unconventional, use -%v:%v=%v instead\n",
						args[i],
						arg[:k],
						arg[k + 1:j],
						arg[j + 1:],
					)
					name = arg[:k]
					val = arg[k + 1:]
				} else {
					// -flag [val]
					name = arg
					n = 2
				}
				
				// -help
				if name == "help" {
					err = {.Help_Text, flags_help_text(args[0], command, flags)}
					return
				}

				flag: Flag(E)

				// note(john): it is possible for the flag name to not be unique
				for f in flags {
					if f.name == name {
						flag = f
						break
					}
				}
				if (flag.name == "") {
					err =  {
						.Invalid_Flag,
						fmt.tprintf("flag: %v not found, see -help for details\n", args[i]),
					}
					return
				}

				if val == "" {
					if _, ok := flag.binding.(Binding_Boolean); ok {
						val = "1"
						n = 1
					} else if (i + 1 < len(args)) {
						val = args[i + 1]
					} else {
						err =  {
							.Invalid_Argument,
							fmt.tprintf("flag: %v is missing required argument\n", args[i]),
						}
						return
					}
				}

				val = strings.trim_space(val)

				ok: bool
				message: string
				switch binding in flag.binding {
				case Binding_Boolean:
					binding.bool_^, ok = strconv.parse_bool(val)
				case Binding_Integer:
					i: int
					i, ok = strconv.parse_int(val)
					if binding.min <= i && i <= binding.max {
						binding.int_^ = i
					} else {
						message = fmt.tprintf(
							"integer must be between %v and %v.",
							binding.min,
							binding.max,
						)
						ok = false
					}
				case Binding_String:
					binding.string_^, ok = val, true
				case Binding_Dynamic_Array:
					if binding.validator != nil {
						message = binding.validator(len(binding.dynamic_array^), val)
					}
					if message == "" {
						append(binding.dynamic_array, val)
						ok = true
					}
				case Binding_Map:
					map_key, map_val := split_key_value_pair(val)
					if binding.validator != nil {
						message = binding.validator(map_key, map_val)
					}
					if message == "" {
						if (binding.map_ == nil) {
							binding.map_^ = make(map[string]string)
						}
						// maybe: redefition of existing key is not allowed?
						//        mistake or feature?
						binding.map_^[map_key] = map_val
						ok = true
					}
				case Binding_Enum:
					ok = binding.procedure(binding, val)
					names := binding->names()
					if !ok && 0 < len(names) {
						message = fmt.tprintf("Expected one of %#v", names)
					}
				}
				if !ok {
					err =  {
						.Invalid_Argument,
						fmt.tprintf(
							"flag: %v has invalid argument: %v\n%v",
							args[i],
							val,
							message,
						),
					}
					return
				}
			}
		}
	}

	command_type = command.type
	return
}

split_key_value_pair :: proc(s: string) -> (key: string, val: string) {
	// the goal here is to split foo=bar
	//  -flag:foo=bar (expected)
	// use could have
	//  -flag=foo:bar (unconventional)
	//  -flag foo:bar (unconventional)
	//  -flag=foo=bar (unconventional)
	//  -flag:foo:bar (unconventional)
	// if you want to put a colon in the value you can but you cannot use both = and : as map values
	i := strings.index_rune(s, '=')
	j := strings.index_rune(s, ':')
	if (i != -1 && j == -1) {
		key = s[:i]
		val = s[i + 1:]
	} else if (i == -1 && j != -1) {
		// unambigous though unconventional
		// -flag=foo=bar?
		// -flag:foo:bar?
		// fmt.eprintf(
		//     "warn: %v is unconventional, use -%v:%v=%v instead\n",
		//     args[i],
		//     arg[:k],
		//     arg[k + 1:j],
		//     arg[j + 1:],
		// )
		key = s[:j]
		val = s[j + 1:]
	} else if (i < j) {
		key = s[:i]
		val = s[i + 1:]
	} else {
		// unconventional?
		key = s[:j]
		val = s[j + 1:]
	}
	return
}

commands_help_text :: proc(
	arg0: string,
	commands: []Command($E),
) -> string where intrinsics.type_is_enum(E) {
	exec_stem := filepath.stem(arg0) // executable file name

	help: strings.Builder

	strings.write_string(&help, "Usage:\n")
	fmt.sbprintf(&help, "\t%v command [arguments]\n", exec_stem)

	// todo: two passes are needed here to figure out the max width
	strings.write_string(&help, "Commands:\n")
	max_len: int
	for cmd in commands {
		max_len = max(max_len, len(cmd.name))
	}
	for cmd in commands {
		strings.write_rune(&help, '\t')
		strings.write_string(&help, cmd.name)
		for i in 0..<(max_len-len(cmd.name))+4 {
			strings.write_rune(&help, ' ')
		}
		strings.write_string(&help, cmd.description) // need to reflow if it spans more than 1 line because \t\t might not be enough
		strings.write_rune(&help, '\n')
	}

	strings.write_rune(&help, '\n')
	strings.write_string(&help, "For further details on a command, invoke command help:\n")
	fmt.sbprintf(&help, "\t e.g. `%v %v -help` or `%v help %v`\n", exec_stem, commands[0].name, exec_stem, commands[0].name)

	return strings.to_string(help)
}

flags_help_text :: proc(
	arg0: string,
	command: Command($E),
	flags: []Flag(E),
) -> string where intrinsics.type_is_enum(E) {
	help: strings.Builder
	// This is why it is necessary that the default value is "not a command"
	if command.type == {} {
		// not a command
	}

	strings.write_string(&help, "Usage:\n")
	fmt.sbprintf(&help, "\t%v %v [arguments]\n", arg0, command.name)

	// command "full summary"

	strings.write_string(&help, "Flags:\n")
	for flag in flags {
		if !(command.type in flag.commands) || command.type == {} {
			continue
		}
		// find and replace?
		//  {exec_file}    C:\devel\odin.exe
		//  {exec_base}    odin
		//  {command}      build

		param: string

		#partial switch binding in flag.binding {
		case Binding_String:
			param = binding.param
		case Binding_Integer:
			param = binding.param
		case Binding_Enum:
			param = binding.param
		case Binding_Dynamic_Array:
			param = binding.param
		case Binding_Map:
			param = binding.param
		}

		fmt.sbprintf(&help, "\t-%v%v\n\t\t%v\n", flag.name, param, flag.description)

		#partial switch binding in flag.binding {
		case Binding_Integer:
			if INT_MIN < binding.min {
				fmt.sbprintf(&help, "\t\tMust be greater than %v.\n", binding.min - 1)
			}
			if binding.max < INT_MAX {
				fmt.sbprintf(&help, "\t\tCannot be greater than %v.\n", binding.max)
			}
			if binding.int_^ != 0 {
				fmt.sbprintf(&help, "\t\tThe default is %v.\n", binding.int_^)
			}
		case Binding_String:
			if binding.string_^ != "" {
				fmt.sbprintf(&help, "\t\tThe default is %v.\n", binding.string_^)
			}
		case Binding_Enum:
			// todo: Binding_Custom
			fmt.sbprintln(&help, "\t\tAvailable options:") // todo: if names?
			names := binding->names()
			for value in names {
				fmt.sbprintf(&help, "\t\t\t-%v:%v\n", flag.name, value)
			}
			default := binding->default()
			fmt.sbprintf(&help, "\t\tThe default is -%v:%v.\n", flag.name, default) // todo: if non empty?
			if (binding.bit_set_) {
				fmt.sbprintln(&help, "\t\tNOTE: This flag can be used multiple times.\n")
			}
		}
	}

	return strings.to_string(help)
}

// ---

Binding :: struct {
	param: string,
}

Binding_Boolean :: struct {
	using _: Binding,
	bool_:   ^bool,
}

bind_bool :: proc(bool_: ^bool) -> Bindings {
	binding: Binding_Boolean
	binding.bool_ = bool_
	return binding
}

Binding_Integer :: struct {
	using _: Binding,
	int_:    ^int,
	min:     int,
	max:     int,
}

INT_MAX :: 1 << (8 * size_of(int) - 1) - 1
INT_MIN :: -INT_MAX // we can go one less but then you cannot take the abs of that, so let's not

bind_int :: proc(
	int_: ^int,
	param := ":<integer>",
	min: int = INT_MIN,
	max: int = INT_MAX,
) -> Bindings {
	binding: Binding_Integer
	binding.param = param
	binding.int_ = int_
	binding.min = min
	binding.max = max
	return binding
}

Binding_String :: struct {
	using _: Binding,
	string_: ^string,
}

bind_string :: proc(string_: ^string, param := ":<string>") -> Bindings {
	binding: Binding_String
	binding.param = param
	binding.string_ = string_
	return binding
}

// ---

Binding_Enum_Parser_Proc :: #type proc(binding: Binding_Enum, value: string) -> (ok: bool)

// options?
Binding_Enum_Names_Proc :: #type proc(binding: Binding_Enum) -> (names: []string)

Binding_Enum_Default_Proc :: #type proc(binding: Binding_Enum) -> (default: string)

Binding_Enum :: struct {
	using _:   Binding,
	procedure: Binding_Enum_Parser_Proc, // parse
	enum_:     rawptr, // data: ^Enum_Type, ^bit_set[Enum_Type]
	rename:    runtime.Raw_Map, // map[string]Enum_Type
	names:     Binding_Enum_Names_Proc,
	default:   Binding_Enum_Default_Proc,
	bit_set_:  bool,
}

@(private)
_enum_parse :: proc($Enum_Type: typeid, binding: Binding_Enum, name: string) -> (value: Enum_Type, ok: bool) {
	rename := transmute(map[string]Enum_Type)binding.rename
	if rename != nil {
		for key, value in rename {
			if strings.equal_fold(name, key) {
				return Enum_Type(value), true
			}
		}
	} else {
		value_names := reflect.enum_field_names(Enum_Type)
		for value_name, i in value_names {
			if strings.equal_fold(name, value_name) {
				return Enum_Type(reflect.enum_field_values(Enum_Type)[i]), true
			}
		}
	}
	return {}, false
}

bind_enum :: proc(
	enum_: ^$Enum_Type,
	param := ":<string>",
) -> Binding_Enum where intrinsics.type_is_enum(Enum_Type) {
	return bind_enum_rename(enum_, param, nil)
}

bind_enum_rename :: proc(
	enum_: ^$Enum_Type,
	param := ":<string>",
	rename: map[string]Enum_Type, // todo: rename -> mapped?
) -> Binding_Enum where intrinsics.type_is_enum(Enum_Type) {
	binding: Binding_Enum
	binding.param = param
	binding.procedure = proc(binding: Binding_Enum, name: string) -> bool {
		if value, ok := _enum_parse(Enum_Type, binding, name); ok {
			(^Enum_Type)(binding.enum_)^ = value
			return true
		}
		return false
	}
	binding.enum_ = enum_
	binding.rename = transmute(runtime.Raw_Map)rename
	binding.names = proc (binding: Binding_Enum) -> []string {
		rename := transmute(map[string]Enum_Type)binding.rename
		if rename != nil {
			names := make([]string, len(rename), context.temp_allocator)
			i: int
			for k in rename {
				names[i] = k
				i += 1
			}
			return names[:]
		}
		return reflect.enum_field_names(Enum_Type)
	}
	binding.default = proc (binding: Binding_Enum) -> string {
		value := (^Enum_Type)(binding.enum_)^
		rename := transmute(map[string]Enum_Type)binding.rename
		if rename != nil {
			for name, bit in rename {
				if bit == value {
					return name
				}
			}
		} else {
			names := reflect.enum_field_names(Enum_Type)
			for bit, i in reflect.enum_field_values(Enum_Type) {
				if Enum_Type(bit) == value {
					return names[i]
				}
			}
		}
		return ""
	}
	return binding
}

bind_bit_set :: proc(
	bit_set_: ^$Bit_Set_Type/bit_set[$Enum_Type],
	param := ":<string>",
) -> Binding_Enum where intrinsics.type_is_bit_set(Bit_Set_Type) {
	return bind_bit_set_rename(bit_set_, param, nil)
}

bind_bit_set_rename :: proc(
	bit_set_: ^$Bit_Set_Type/bit_set[$Enum_Type],
	param := ":<string>",
	rename: map[string]Enum_Type
) -> Binding_Enum where intrinsics.type_is_bit_set(Bit_Set_Type) {
	binding: Binding_Enum
	binding.param = param
	binding.procedure = proc(binding: Binding_Enum, names: string) -> bool {
		// -flag:foo,bar,baz
		// -flag:0,bar everything off except bar
		// -flag:~0,-bar everything on except bar
		for name in strings.split(names, ",", allocator = context.temp_allocator) {
			name := name
			switch {
			case strings.has_prefix(name, "+"):
				name = name[1:]
				fallthrough
			case:
				value := _enum_parse(Enum_Type, binding, name) or_return
				(^Bit_Set_Type)(binding.enum_)^ += {value}
			case strings.has_prefix(name, "-"):
				name := name[1:]
				value := _enum_parse(Enum_Type, binding, name) or_return
				(^Bit_Set_Type)(binding.enum_)^ -= {value}
			case name == "0":
				(^Bit_Set_Type)(binding.enum_)^ = {}
			case name == "~0":
				(^Bit_Set_Type)(binding.enum_)^ = ~{} // note: this will set bits outside the enum
			}
		}
		return true
	}
	binding.enum_ = bit_set_
	binding.rename = transmute(runtime.Raw_Map)rename
	binding.names = proc (binding: Binding_Enum) -> []string {
		rename := transmute(map[string]Enum_Type)binding.rename
		if rename != nil {
			names := make([]string, len(rename), context.temp_allocator)
			i: int
			for k in rename {
				names[i] = k
				i += 1
			}
			return names[:]
		}
		return reflect.enum_field_names(Enum_Type)
	}
	binding.default = proc (binding: Binding_Enum) -> string {
		sb: strings.Builder
		strings.builder_init(&sb, context.temp_allocator)
		bits := (^Bit_Set_Type)(binding.enum_)^
		rename := transmute(map[string]Enum_Type)binding.rename
		if rename != nil {
			for name, bit in rename {
				if bit in bits {
					if 0 < strings.builder_len(sb) {
						strings.write_rune(&sb, ',')
					}
					strings.write_string(&sb, name)
				}
			}
		} else {
			names := reflect.enum_field_names(Enum_Type)
			for bit, i in reflect.enum_field_values(Enum_Type) {
				if Enum_Type(bit) in bits {
					if 0 < strings.builder_len(sb) {
						strings.write_rune(&sb, ',')
					}
					strings.write_string(&sb, names[i])
				}
			}
		}
		return strings.to_string(sb)
	}
	binding.bit_set_ = true
	return binding
}

Binding_Map_Validator_Proc :: #type proc(key: string, val: string) -> (err: string)

Binding_Map :: struct {
	using _:   Binding,
	map_:      ^map[string]string,
	validator: Binding_Map_Validator_Proc,
}

bind_map :: proc(
	map_: ^map[string]string,
	param := ":<key>=<value>",
	validator: Binding_Map_Validator_Proc = nil,
) -> Bindings {
	binding: Binding_Map
	binding.param = param
	binding.map_ = map_
	binding.validator = validator
	return binding
}

Binding_Dynamic_Array_Validator_Proc :: #type proc(index: int, val: string) -> (err: string)

Binding_Dynamic_Array :: struct {
	using _:       Binding,
	dynamic_array: ^[dynamic]string,
	validator:     Binding_Dynamic_Array_Validator_Proc,
}

bind_dynamic_array :: proc(
	dynamic_array: ^[dynamic]string,
	param := ":<string>",
	validator: Binding_Dynamic_Array_Validator_Proc = nil,
) -> Bindings {
	binding: Binding_Dynamic_Array
	binding.param = param
	binding.dynamic_array = dynamic_array
	binding.validator = validator
	return binding
}

bind :: proc {
	bind_bool,
	bind_int,
	bind_string,
	bind_enum,
	bind_enum_rename,
	bind_bit_set,
	bind_bit_set_rename,
	bind_dynamic_array,
	bind_map,
}
