package flag_demo

import "core:fmt"

import "../flag"

// This demo is based on the Odin compiler command line interface
// https://github.com/odin-lang/Odin/blob/master/src/main.cpp

Odin_Command_Kind :: enum {
	None, // the default value should represent the abscence of a command
	Build,
	Run,
	Check,
}

Odin_Optimization_Level :: enum {
	None,
	Minimal,
	Size,
	Speed,
	Aggressive,
}

Odin_SanitizerFlag :: enum {
    Address,
    Memory,
    Thread,
}
Odin_SanitizerFlags :: bit_set[Odin_SanitizerFlag]

Odin_Build_Context :: struct {
	file:                string, 
	out_filepath:        string,
    optimization_level:  Odin_Optimization_Level,
	show_timings:        bool,
    sanitizer_flags:     Odin_SanitizerFlags,
}

parse_args :: proc(build_context: ^Odin_Build_Context) -> (command: Odin_Command_Kind, err: flag.Error) {
	commands := []flag.Command(Odin_Command_Kind) {
		 {
			.Build,
			"build",
			"Compiles directory of .odin files, as an executable.\n" +
			"\t\tOne must contain the program's entry point, all must be in the same package.",
		},
		{.Run, "run", "Same as 'build', but also then runs the newly compiled executable."},
		{.Check, "check", "Parses, and type checks a directory of .odin files."},
	}

	Build_Or_Run :: bit_set[Odin_Command_Kind]{.Build, .Run}
	Command_Does_Check :: bit_set[Odin_Command_Kind]{.Run, .Build, .Check}

	flags := []flag.Flag(Odin_Command_Kind) {
		{
			&build_context.file,
			"file",
			"Tells `%v` to treat the given file as a self-contained package.\n" +
			"\t\tThis means that `<dir>/a.odin` won't have access to `<dir>/b.odin`'s contents.",
			Build_Or_Run + {.Check},
		},
		{
			&build_context.out_filepath,
			"out",
			"Sets the file name of the outputted executable.\n" + "\t\tExample: -out:foo.exe",
			Build_Or_Run,
		},
        {
            flag.bind_enum(&build_context.optimization_level),
			"o", // o:<string>? {"o", "string"}?
			"Sets the optimization mode for compilation.",
			Build_Or_Run,
		},
        {
            flag.bind_bit_set(&build_context.sanitizer_flags),
			"sanitize", // o:<string>? {"o", "string"}?
			"Enables sanitization analysis.",
			Build_Or_Run,
		},
        {
			&build_context.show_timings,
			"show-timings",
			"Shows basic overview of the timings of different stages within the compiler in milliseconds.",
			Build_Or_Run,
		},
	}

	// todo: -collection:<name>=<filepath>
    
	return flag.parse_args_commands(Odin_Command_Kind, commands, flags)
}

main :: proc() {
	build_context: Odin_Build_Context
	build_context.optimization_level = Odin_Optimization_Level.Minimal // default
	fmt.println(parse_args(&build_context))
	fmt.printf("%#v\n", build_context)
}
