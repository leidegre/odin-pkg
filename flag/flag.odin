package flag

import "core:fmt"
import "core:intrinsics"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:unicode"
import "core:reflect"

Command :: struct($Enum_Type: typeid) where intrinsics.type_is_enum(Enum_Type) {
	type:        Enum_Type,
	name:        string,
	description: string,
}

// Command_Flag_Var, Command_Flag_Ptr, Command_Flag_Binding? Flag_Binding?
Flag_Var :: union {
	^string,
	^bool,
	^int,
    Flag_Parser,
}

// -name:argument
Flag :: struct($Enum_Type: typeid) where intrinsics.type_is_enum(Enum_Type) {
	var:         Flag_Var, // ptr?
	name:        string,
	description: string, // usage
	commands:    bit_set[Enum_Type], // supported_commands? has?
}

// while it is possible to put a unnamed enum inside the Flag it will break the type checker
Dummy :: enum {
	None,
}

Flag_Dummy :: Flag(Dummy)

make_flag :: proc(var: Flag_Var, name: string, description: string = "") -> Flag_Dummy {
	return {var, name, description, {}}
}

Error_Code :: enum {
	Ok,
	Help_Text,
	Invalid_Command, // command not found
	Invalid_Option, // flag not found
	Invalid_Argument, // flag has invalid argument
}

Error :: struct {
	code:    Error_Code,
	message: string,
}

// Error_Handling
Error_Mode :: enum {
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
	mode: Error_Mode = .Exit_On_Error,
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
	mode: Error_Mode = .Exit_On_Error,
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
						err = {.Invalid_Option, fmt.tprintf("flag: too many - in %v", args[i])}
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
						.Invalid_Option,
						fmt.tprintf("flag: %v not found, see -help for details\n", args[i]),
					}
					return
				}

				if val == "" {
					if _, ok := flag.var.(^bool); ok {
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
				switch var in flag.var {
				case ^bool:
					var^, ok = strconv.parse_bool(val)
				case ^string:
					var^, ok = val, true
				case ^int:
					var^, ok = strconv.parse_int(val)
                case Flag_Parser:
                        ok = var.procedure(var.data, val)
                        if !ok && 0 < len(var.available_options) {
                            message = fmt.tprintf("Expected one of %#v", var.available_options)
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

// Bind: binds a variable

Flag_Parser_Proc :: #type proc (data: rawptr, value: string) -> (ok: bool)

Flag_Cardinality :: enum {
    One,
    Many
}

Flag_Parser :: struct {
    procedure:          Flag_Parser_Proc,
    data:               rawptr,
    available_options:  []string, // if non-empty a string passed on the command line must be a member of this set
    default:            string,
    cardinality:        Flag_Cardinality // maybe...
}

bind_enum :: proc(enum_: ^$Enum_Type) -> Flag_Parser where intrinsics.type_is_enum(Enum_Type) {
    bind :: proc (enum_: ^Enum_Type, name: string) -> bool {
        value := reflect.enum_from_name(Enum_Type, name) or_return
        enum_^ = value
        return true
    }
    return {Flag_Parser_Proc(bind), enum_, reflect.enum_field_names(Enum_Type), fmt.aprint(enum_^), .One}
}

bind_bit_set :: proc(bit_set_: ^$Bit_Set_Type/bit_set[$Enum_Type]) -> Flag_Parser where intrinsics.type_is_bit_set(Bit_Set_Type) {
    bind :: proc (bit_set_: ^Bit_Set_Type, name: string) -> bool {
        value := reflect.enum_from_name(Enum_Type, name) or_return
        bit_set_^ += {value}
        return true
    }
    // how should we render the default value in this case?
    return {Flag_Parser_Proc(bind), bit_set_, reflect.enum_field_names(Enum_Type), fmt.aprint(bit_set_^), .Many}
}

bind :: proc{
    bind_enum, 
    bind_bit_set,
}