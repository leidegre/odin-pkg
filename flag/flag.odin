package flag

import "core:fmt"
import "core:intrinsics"
import "core:os"
import "core:reflect"
import "core:strconv"
import "core:strings"
import "core:unicode"

Command :: struct($Enum_Type: typeid) where intrinsics.type_is_enum(Enum_Type) {
	type:        Enum_Type,
	name:        string,
	description: string,
}

// just Bindings
Flag_Bindings :: union {
	Flag_Binding_Bool,
	Flag_Binding_Int,
	Flag_Binding_String,
	Flag_Binding_Map,
	Flag_Parser,
}

// -name:argument
Flag :: struct($Enum_Type: typeid) where intrinsics.type_is_enum(Enum_Type) {
	var:         Flag_Bindings, // binding
	name:        string,
	description: string,
	commands:    bit_set[Enum_Type], // supported_commands? has?
}

// while it is possible to put a unnamed enum inside the Flag it will break the type checker
Dummy :: enum {
	None,
}

Flag_Dummy :: Flag(Dummy)

make_flag :: proc(var: Flag_Bindings, name: string, description: string = "") -> Flag_Dummy {
	return {var, name, description, {}}
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

// mother of all parsers
parse_args_commands :: proc(
	$E: typeid,
	commands: []Command(E),
	flags: []Flag(E),
	args: []string = nil,
	mode: Error_Handling = .Exit_On_Error,
) -> (
	command: E,
	err: Error,
) where intrinsics.type_is_enum(E) {
	command, err = _parse_args_commands(E, commands, flags, args != nil ? args : os.args)
	if err.code != .Ok {
		fmt.eprintln(err.message)
		switch mode {
		case .Exit_On_Error:
			os.exit(err.code != .Help_Text ? 2 : 0)
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
		// first argument should be a command
		if len(args) <= 1 {
			err = {.Help_Text, commands_help_text(args[0], commands)}
			return
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
					"flag: command %#v not found\n%v",
					args[i],
					commands_help_text(args[0], commands),
				),
			}
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
					if _, ok := flag.var.(Flag_Binding_Bool); ok {
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
				switch binding in flag.var {
				case Flag_Binding_Bool:
					binding.bool_^, ok = strconv.parse_bool(val)
				case Flag_Binding_Int:
					binding.int_^, ok = strconv.parse_int(val)
				case Flag_Binding_String:
					binding.string_^, ok = val, true
				case Flag_Binding_Map:
					map_key, map_val := split_key_value_pair(val)
					if binding.validator != nil {
						message = binding.validator(map_key, map_val)
					}
					if message == "" {
						if (binding.map_ == nil) {
							binding.map_^ = make(map[string]string)
						}
						// todo: redefition of existing key is not allowed
						binding.map_^[map_key] = map_val
						ok = true
					}
				case Flag_Parser:
					ok = binding.procedure(binding.data, val)
					if !ok && 0 < len(binding.available_options) {
						message = fmt.tprintf("Expected one of %#v", binding.available_options)
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
	help: strings.Builder

	strings.write_string(&help, "Usage:\n")
	fmt.sbprintf(&help, "\t%v command [arguments]\n", arg0)

	// todo: two passes are needed here to figure out the max width
	strings.write_string(&help, "Commands:\n")
	for cmd in commands {
		fmt.sbprintf(&help, "\t%v\t%v\n", cmd.name, cmd.description)
	}

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
		fmt.sbprintf(&help, "\t-%v\n\t\t%v\n", flag.name, flag.description)

		#partial switch binding in flag.var {
		case Flag_Parser:
			fmt.sbprintln(&help, "\t\tAvailable options:")
			for value in binding.available_options {
				fmt.sbprintf(&help, "\t\t\t-%v:%v\n", flag.name, value)
			}
			fmt.sbprintf(&help, "\t\tThe default is -%v:%v.\n", flag.name, binding.default)
			if (binding.cardinality == .Many) {
				fmt.sbprintln(&help, "\t\tNOTE: This flag can be used multiple times.\n")
			}
		}
	}

	return strings.to_string(help)
}

// ---

Flag_Binding :: struct {
	param: string,
}

Flag_Binding_Bool :: struct {
	using _: Flag_Binding,
	bool_:   ^bool,
}

bind_bool :: proc(bool_: ^bool) -> Flag_Bindings {
	binding: Flag_Binding_Bool
	binding.bool_ = bool_
	return binding
}

Flag_Binding_Int :: struct {
	using _: Flag_Binding,
	int_:    ^int,
}

bind_int :: proc(int_: ^int, param := "<integer>") -> Flag_Bindings {
	binding: Flag_Binding_Int
	binding.param = param
	binding.int_ = int_
	return binding
}

Flag_Binding_String :: struct {
	using _: Flag_Binding,
	string_: ^string,
}

bind_string :: proc(string_: ^string, param := "<string>") -> Flag_Bindings {
	binding: Flag_Binding_String
	binding.param = param
	binding.string_ = string_
	return binding
}

// ---

Flag_Parser_Proc :: #type proc(data: rawptr, value: string) -> (ok: bool)

Flag_Cardinality :: enum {
	One,
	Many,
}

Flag_Parser :: struct {
	procedure:         Flag_Parser_Proc,
	data:              rawptr,
	available_options: []string, // if non-empty a string passed on the command line must be a member of this set
	default:           string,
	cardinality:       Flag_Cardinality, // maybe...
}

bind_enum :: proc(
	enum_: ^$Enum_Type,
	param := "<string>",
) -> Flag_Parser where intrinsics.type_is_enum(Enum_Type) {
	bind :: proc(enum_: ^Enum_Type, name: string) -> bool {
		value := reflect.enum_from_name(Enum_Type, name) or_return
		enum_^ = value
		return true
	}
	return(
		 {
			Flag_Parser_Proc(bind),
			enum_,
			reflect.enum_field_names(Enum_Type),
			fmt.aprint(enum_^),
			.One,
		} \
	)
}

bind_bit_set :: proc(
	bit_set_: ^$Bit_Set_Type/bit_set[$Enum_Type],
	param := "<string>",
) -> Flag_Parser where intrinsics.type_is_bit_set(Bit_Set_Type) {
	bind :: proc(bit_set_: ^Bit_Set_Type, name: string) -> bool {
		// todo: split comma?
		value := reflect.enum_from_name(Enum_Type, name) or_return
		bit_set_^ += {value}
		return true
	}
	// todo: render default value as -flag:foo,bar,baz?
	return(
		 {
			Flag_Parser_Proc(bind),
			bit_set_,
			reflect.enum_field_names(Enum_Type),
			fmt.aprint(bit_set_^),
			.Many,
		} \
	)
}

// Flag_Binding_Map?
// Map_Binding? <- this!!!
// Map_Binding_Validator_Proc?
Flag_Validator_Proc :: #type proc(key: string, val: string) -> (err: string)

Flag_Binding_Map :: struct {
	using _:   Flag_Binding,
	map_:      ^map[string]string,
	validator: Flag_Validator_Proc,
}

bind_map :: proc(
	map_: ^map[string]string,
	param := "<key>=<value>",
	validator: Flag_Validator_Proc = nil,
) -> Flag_Bindings {
	binding: Flag_Binding_Map
	binding.param = param
	binding.map_ = map_
	binding.validator = validator
	return binding
}

bind :: proc {
	bind_bool,
	bind_int,
	bind_string,
	bind_enum,
	bind_bit_set,
	bind_map,
}
