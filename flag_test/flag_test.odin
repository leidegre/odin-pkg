package flag_test

import "core:fmt"
import "core:intrinsics"
import "core:reflect"
import "core:testing"

import "../flag"

@(test)
test_parse_flags_string :: proc(t: ^testing.T) {
	// -foo:bar
	// -foo:bar=baz

	// -foo bar
	// -foo=bar

	// -foo=bar:baz (ew!)

	foo: string

	flags := []flag.Flag_Dummy{{flag.bind(&foo), "foo", "", {}}}

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
test_parse_flags_int :: proc(t: ^testing.T) {
	i: int

	flags := []flag.Flag_Dummy{{flag.bind(&i), "i", "", {}}}

	flag.parse_args_flags(flags, []string{"", "-i:123"}, .Assert_On_Error)
	testing.expect_value(t, i, 123)

	flag.parse_args_flags(flags, []string{"", "-i=123456"}, .Assert_On_Error)
	testing.expect_value(t, i, 123456)

	flag.parse_args_flags(flags, []string{"", "-i", "123456789"}, .Assert_On_Error)
	testing.expect_value(t, i, 123456789)
}

@(test)
test_parse_flags_bool :: proc(t: ^testing.T) {
	b: bool

	flags := []flag.Flag_Dummy{{flag.bind(&b), "b", "", {}}}

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

@(test)
test_parse_enum :: proc(t: ^testing.T) {
	Metasyntactic_Variable :: enum {
		Foo,
		Bar,
		Baz,
	}

	meta_var: Metasyntactic_Variable

	flags := []flag.Flag_Dummy{flag.Flag_Dummy{flag.bind(&meta_var), "meta-var", "", {}}}

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
test_parse_bit_set :: proc(t: ^testing.T) {
	Metasyntactic_Variable :: enum {
		Foo,
		Bar,
		Baz,
	}
	Metasyntactic_Variables :: bit_set[Metasyntactic_Variable]

	meta_vars: Metasyntactic_Variables

	flags := []flag.Flag_Dummy{flag.Flag_Dummy{flag.bind_bit_set(&meta_vars), "meta-var", "", {}}}

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
}
