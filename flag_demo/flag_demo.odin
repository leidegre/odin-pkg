package flag_demo

import "core:fmt"
import "core:odin/tokenizer"
import "core:os"

import "../flag"

// This demo is based on the Odin compiler command line interface
// https://github.com/odin-lang/Odin/blob/master/src/main.cpp

Odin_Command :: enum {
	None, // the default value should represent the abscence of a command in the event of an error
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

Odin_Sanitizer_Flag :: enum {
	Address,
	Memory,
	Thread,
}
Odin_Sanitizer_Flags :: bit_set[Odin_Sanitizer_Flag]

Odin_Build_Context :: struct {
	file:               string,
	out_filepath:       string,
	optimization_level: Odin_Optimization_Level,
	show_timings:       bool,
	sanitizer_flags:    Odin_Sanitizer_Flags,
	collection:         map[string]string,
	max_error_count:    int,
}

parse_args :: proc(
	build_context: ^Odin_Build_Context,
) -> (
	command: Odin_Command,
	err: flag.Error,
) {
	commands := []flag.Command(Odin_Command) {
		 {
			.Build,
			"build",
			"Compiles directory of .odin files, as an executable.\n" +
			"\t\tOne must contain the program's entry point, all must be in the same package.",
		},
		{.Run, "run", "Same as 'build', but also then runs the newly compiled executable."},
		{.Check, "check", "Parses, and type checks a directory of .odin files."},
	}

	Build_Or_Run :: bit_set[Odin_Command]{.Build, .Run}
	Command_Does_Check :: bit_set[Odin_Command]{.Run, .Build, .Check}

	flags := []flag.Flag(Odin_Command) {
		{
			"file",
			flag.bind(&build_context.file, ":<filepath>"),
			"Tells `%v` to treat the given file as a self-contained package.\n" +
			"\t\tThis means that `<dir>/a.odin` won't have access to `<dir>/b.odin`'s contents.",
			Build_Or_Run + {.Check},
		},
		{
			"out",
			flag.bind(&build_context.out_filepath, ":<filepath>"),
			"Sets the file name of the outputted executable.\n" + "\t\tExample: -out:foo.exe",
			Build_Or_Run,
		},
		{
			"o",
			flag.bind(&build_context.optimization_level),
			"Sets the optimization mode for compilation.",
			Build_Or_Run,
		},
		{
			"sanitize",
			flag.bind(&build_context.sanitizer_flags),
			"Enables sanitization analysis.",
			Build_Or_Run,
		},
		{
			"show-timings",
			flag.bind(&build_context.show_timings),
			"Shows basic overview of the timings of different stages within the compiler in milliseconds.",
			Build_Or_Run,
		},
		{
			"collection",
			flag.bind(&build_context.collection, ":<name>=<filepath>", collection_validator),
			"Defines a library collection used for imports.\n" +
			"\t\tExample: -collection:shared=dir/to/shared\n" +
			"\t\tUsage in Code:\n" +
			"\t\t\timport \"shared:foo\"",
			Build_Or_Run,
		},
		{
			"max-error-count",
			flag.bind(&build_context.max_error_count, min=1),
			"Sets the maximum number of errors that can be displayed before the compiler terminates.",
			Build_Or_Run,
		},
	}

	collection_validator :: proc(key: string, val: string) -> (err: string) {
		t: tokenizer.Tokenizer
		tokenizer.init(&t, key, "")
		tok := tokenizer.scan(&t)
		if (tok.kind != .Ident) {
			err = fmt.tprintf("Library collection name '%v' must be a valid identifier.\n", key)
		} else if (tok.text == "_") {
			err = "Library collection name cannot be an underscore\n"
		} else if (tok.text == "system") {
			err = "Library collection name 'system' is reserved\n"
		} else if (!os.is_dir(val)) {
			err = fmt.tprintf(
				"Library collection name '%v' path must be a directory, got '%v'.\n",
				key,
				val,
			)
		}
		return
	}

	return flag.parse_args_commands(Odin_Command, commands, flags)
}

main :: proc() {
	build_context: Odin_Build_Context
	
	// defaults
	build_context.optimization_level = Odin_Optimization_Level.Minimal 
    build_context.sanitizer_flags += {.Address}
	build_context.max_error_count = 36
	
	fmt.println(parse_args(&build_context))

	fmt.printf("%#v\n", build_context)
}
