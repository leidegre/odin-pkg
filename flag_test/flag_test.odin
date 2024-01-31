package flag_test

import "core:fmt"
import "core:intrinsics"
import "core:reflect"
import "core:slice"
import "core:testing"

import "../flag"

Command_Type :: enum{}

Flag :: flag.Flag(Command_Type)

@(test)
test_parse_args_string :: proc(t: ^testing.T) {
	// -foo:bar
	// -foo:bar=baz

	// -foo bar
	// -foo=bar

	// -foo=bar:baz (ew!)

	foo: string

	flags := []Flag{{"foo", flag.bind(&foo), "", {}}}

	flag.parse_args_flags(flags, []string{"", "-foo:bar"}, .Assert_On_Error)
	testing.expect_value(t, foo, "bar")

	flag.parse_args_flags(flags, []string{"", "-foo:bar=baz"}, .Assert_On_Error)
	testing.expect_value(t, foo, "bar=baz")

	flag.parse_args_flags(flags, []string{"", "-foo", "bar"}, .Assert_On_Error)
	testing.expect_value(t, foo, "bar")

	flag.parse_args_flags(flags, []string{"", "-foo=baz"}, .Assert_On_Error)
	testing.expect_value(t, foo, "baz")

	// ok but unconventional
	flag.parse_args_flags(flags, []string{"", "-foo=baz:bar"}, .Assert_On_Error)
	testing.expect_value(t, foo, "baz:bar")
}

@(test)
test_parse_args_int :: proc(t: ^testing.T) {
	i: int

	flags := []Flag{{"i", flag.bind(&i), "", {}}}

	flag.parse_args_flags(flags, []string{"", "-i:123"}, .Assert_On_Error)
	testing.expect_value(t, i, 123)

	flag.parse_args_flags(flags, []string{"", "-i=123456"}, .Assert_On_Error)
	testing.expect_value(t, i, 123456)

	flag.parse_args_flags(flags, []string{"", "-i", "123456789"}, .Assert_On_Error)
	testing.expect_value(t, i, 123456789)
}

@(test)
test_parse_args_bool :: proc(t: ^testing.T) {
	b: bool

	flags := []Flag{{"b", flag.bind(&b), "", {}}}

	Test :: struct {
		args:     []string,
		initial:  bool,
		expected: bool,
	}

	tests := []Test {
		{[]string{"", "-b"}, false, true},
		{[]string{"", "-b:1"}, false, true},
		{[]string{"", "-b:true"}, false, true},
		{[]string{"", "-b:0"}, true, false},
		{[]string{"", "-b:false"}, true, false},
	}

	for test in tests {
		b = test.initial
		flag.parse_args_flags(flags, test.args, .Assert_On_Error)
		testing.expect_value(t, b, test.expected)
	}
}

Metasyntactic_Variable :: enum {
	Foo,
	Bar,
	Baz,
}
Metasyntactic_Variables :: bit_set[Metasyntactic_Variable]

@(test)
test_parse_enum :: proc(t: ^testing.T) {
	meta_var: Metasyntactic_Variable

	flags := []Flag{
		{"meta-var", flag.bind(&meta_var), "", {}},
	}

	Test :: struct {
		args:     []string,
		expected: Metasyntactic_Variable,
	}

	tests := []Test {
		{[]string{"", "-meta-var:Foo"}, .Foo},
		{[]string{"", "-meta-var:Bar"}, .Bar},
		{[]string{"", "-meta-var:Baz"}, .Baz},
	}

	for test in tests {
		flag.parse_args_flags(flags, test.args, .Assert_On_Error)
		testing.expect_value(t, meta_var, test.expected)
	}
}

@(test)
test_parse_enum_rename :: proc(t: ^testing.T) {
	meta_var: Metasyntactic_Variable
	meta_var_map := map[string]Metasyntactic_Variable{
		"f" = .Foo, 
		"b" = .Bar, 
		"z" = .Baz,
	}

	flags := []Flag{
		{"meta-var", flag.bind(&meta_var, ":<string>", meta_var_map), "", {}},
	}

	Test :: struct {
		args:     []string,
		expected: Metasyntactic_Variable,
	}

	tests := []Test {
		{[]string{"", "-meta-var:f"}, .Foo},
		{[]string{"", "-meta-var:b"}, .Bar},
		{[]string{"", "-meta-var:z"}, .Baz},
	}

	for test in tests {
		flag.parse_args_flags(flags, test.args, .Assert_On_Error)
		testing.expect_value(t, meta_var, test.expected)
	}
}

@(test)
test_parse_bit_set :: proc(t: ^testing.T) {
	meta_vars: Metasyntactic_Variables

	flags := []Flag{
		{"meta-var", flag.bind(&meta_vars), "", {}},
	}

	Test :: struct {
		args:     []string,
		expected: Metasyntactic_Variables,
	}

	tests := []Test {
		{[]string{"", "-meta-var:Foo"}, {.Foo}},
		{[]string{"", "-meta-var:Bar"}, {.Foo, .Bar}},
		{[]string{"", "-meta-var:Baz"}, {.Foo, .Bar, .Baz}},
	}

	for test in tests {
		flag.parse_args_flags(flags, test.args, .Assert_On_Error)
		testing.expect_value(t, meta_vars, test.expected)
	}

	meta_vars = {}
	flag.parse_args_flags(flags, []string{"", "-meta-var:Baz,Bar,Foo"}, .Assert_On_Error)
	testing.expect_value(t, meta_vars, Metasyntactic_Variables({.Foo, .Bar, .Baz}))
}

@(test)
test_parse_bit_set_rename :: proc(t: ^testing.T) {
	meta_vars: Metasyntactic_Variables
	meta_var_map := map[string]Metasyntactic_Variable{
		"f" = .Foo, 
		"b" = .Bar, 
		"z" = .Baz,
	}

	flags := []Flag{
		{"meta-var", flag.bind(&meta_vars, ":<string>", meta_var_map), "", {}},
	}

	Test :: struct {
		args:     []string,
		expected: Metasyntactic_Variables,
	}

	tests := []Test {
		{[]string{"", "-meta-var:f"}, {.Foo}},
		{[]string{"", "-meta-var:b"}, {.Foo, .Bar}},
		{[]string{"", "-meta-var:0"}, {}},
		{[]string{"", "-meta-var:z"}, {.Baz}},
		{[]string{"", "-meta-var:~0"}, {.Foo, .Bar, .Baz}},
		{[]string{"", "-meta-var:-f"}, {.Bar, .Baz}},
		{[]string{"", "-meta-var:-b"}, {.Baz}},
	}

	for test in tests {
		flag.parse_args_flags(flags, test.args, .Assert_On_Error)
		testing.expect_value(t, meta_vars & {.Foo, .Bar, .Baz}, test.expected)
	}

	meta_vars = {}
	flag.parse_args_flags(flags, []string{"", "-meta-var:z,b,f"}, .Assert_On_Error)
	testing.expect_value(t, meta_vars, Metasyntactic_Variables({.Foo, .Bar, .Baz}))
}

@(test)
test_parse_dynamic_array :: proc(t: ^testing.T) {
	dynamic_array: [dynamic]string

	flags := []Flag {
		{"a", flag.bind_dynamic_array(&dynamic_array), "", {}},
	}

	testing.expect(t, dynamic_array == nil)

	flag.parse_args_flags(flags, []string{"", "-a:foo"}, .Assert_On_Error)
	testing.expect(t, slice.equal(dynamic_array[:], []string{"foo"}))

	flag.parse_args_flags(flags, []string{"", "-a:bar"}, .Assert_On_Error)
	testing.expect(t, slice.equal(dynamic_array[:], []string{"foo", "bar"}))

	flag.parse_args_flags(flags, []string{"", "-a:baz"}, .Assert_On_Error)
	testing.expect(t, slice.equal(dynamic_array[:], []string{"foo", "bar", "baz"}))
}

@(test)
test_parse_map :: proc(t: ^testing.T) {
	map_: map[string]string

	flags := []Flag {
		{"m", flag.bind_map(&map_), "", {}},
	}
	
	testing.expect(t, map_ == nil)

	flag.parse_args_flags(flags, []string{"", "-m:foo=bar"}, .Assert_On_Error)
	testing.expect_value(t, map_["foo"], "bar")

	flag.parse_args_flags(flags, []string{"", "-m:bar=baz"}, .Assert_On_Error)
	testing.expect_value(t, map_["foo"], "bar")
	testing.expect_value(t, map_["bar"], "baz")
}