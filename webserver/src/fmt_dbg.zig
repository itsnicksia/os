//! String formatting and parsing.

const std = @import("std");
const builtin = @import("builtin");

const io = std.io;
const math = std.math;
const assert = std.debug.assert;
const mem = std.mem;
const unicode = std.unicode;
const meta = std.meta;
const lossyCast = math.lossyCast;
const expectFmt = std.testing.expectFmt;

pub const default_max_depth = 3;

pub const Alignment = enum {
    left,
    center,
    right,
};

pub const FormatOptions = struct {
    precision: ?usize = null,
    width: ?usize = null,
    alignment: Alignment = .right,
    fill: u21 = ' ',
};

/// Renders fmt string with args, calling `writer` with slices of bytes.
/// If `writer` returns an error, the error is returned from `format` and
/// `writer` is not called again.
///
/// The format string must be comptime-known and may contain placeholders following
/// this format:
/// `{[argument][specifier]:[fill][alignment][width].[precision]}`
///
/// Above, each word including its surrounding [ and ] is a parameter which you have to replace with something:
///
/// - *argument* is either the numeric index or the field name of the argument that should be inserted
///   - when using a field name, you are required to enclose the field name (an identifier) in square
///     brackets, e.g. {[score]...} as opposed to the numeric index form which can be written e.g. {2...}
/// - *specifier* is a type-dependent formatting option that determines how a type should formatted (see below)
/// - *fill* is a single unicode codepoint which is used to pad the formatted text
/// - *alignment* is one of the three bytes '<', '^', or '>' to make the text left-, center-, or right-aligned, respectively
/// - *width* is the total width of the field in unicode codepoints
/// - *precision* specifies how many decimals a formatted number should have
///
/// Note that most of the parameters are optional and may be omitted. Also you can leave out separators like `:` and `.` when
/// all parameters after the separator are omitted.
/// Only exception is the *fill* parameter. If *fill* is required, one has to specify *alignment* as well, as otherwise
/// the digits after `:` is interpreted as *width*, not *fill*.
///
/// The *specifier* has several options for types:
/// - `x` and `X`: output numeric value in hexadecimal notation
/// - `s`:
///   - for pointer-to-many and C pointers of u8, print as a C-string using zero-termination
///   - for slices of u8, print the entire slice as a string without zero-termination
/// - `e`: output floating point value in scientific notation
/// - `d`: output numeric value in decimal notation
/// - `b`: output integer value in binary notation
/// - `o`: output integer value in octal notation
/// - `c`: output integer as an ASCII character. Integer type must have 8 bits at max.
/// - `u`: output integer as an UTF-8 sequence. Integer type must have 21 bits at max.
/// - `?`: output optional value as either the unwrapped value, or `null`; may be followed by a format specifier for the underlying value.
/// - `!`: output error union value as either the unwrapped value, or the formatted error value; may be followed by a format specifier for the underlying value.
/// - `*`: output the address of the value instead of the value itself.
/// - `any`: output a value of any type using its default format.
///
/// If a formatted user type contains a function of the type
/// ```
/// pub fn format(value: ?, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void
/// ```
/// with `?` being the type formatted, this function will be called instead of the default implementation.
/// This allows user types to be formatted in a logical manner instead of dumping all fields of the type.
///
/// A user type may be a `struct`, `vector`, `union` or `enum` type.
///
/// To print literal curly braces, escape them by writing them twice, e.g. `{{` or `}}`.
pub fn format(
    writer: anytype,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    if (args_type_info != .Struct) {
        @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
    }

    const fields_info = args_type_info.Struct.fields;
    if (fields_info.len > max_format_args) {
        @compileError("32 arguments max are supported per format call");
    }

    @setEvalBranchQuota(2000000);
    comptime var arg_state: ArgState = .{ .args_len = fields_info.len };
    comptime var i = 0;
    inline while (i < fmt.len) {
        const start_index = i;

        inline while (i < fmt.len) : (i += 1) {
            switch (fmt[i]) {
                '{', '}' => break,
                else => {},
            }
        }

        comptime var end_index = i;
        comptime var unescape_brace = false;

        // Handle {{ and }}, those are un-escaped as single braces
        if (i + 1 < fmt.len and fmt[i + 1] == fmt[i]) {
            unescape_brace = true;
            // Make the first brace part of the literal...
            end_index += 1;
            // ...and skip both
            i += 2;
        }

        // Write out the literal
        if (start_index != end_index) {
            try writer.writeAll(fmt[start_index..end_index]);
        }

        // We've already skipped the other brace, restart the loop
        if (unescape_brace) continue;

        if (i >= fmt.len) break;

        if (fmt[i] == '}') {
            @compileError("missing opening {");
        }

        // Get past the {
        comptime assert(fmt[i] == '{');
        i += 1;

        const fmt_begin = i;
        // Find the closing brace
        inline while (i < fmt.len and fmt[i] != '}') : (i += 1) {}
        const fmt_end = i;

        if (i >= fmt.len) {
            @compileError("missing closing }");
        }

        // Get past the }
        comptime assert(fmt[i] == '}');
        i += 1;

        const placeholder = comptime Placeholder.parse(fmt[fmt_begin..fmt_end].*);
        const arg_pos = comptime switch (placeholder.arg) {
            .none => null,
            .number => |pos| pos,
            .named => |arg_name| meta.fieldIndex(ArgsType, arg_name) orelse
                @compileError("no argument with name '" ++ arg_name ++ "'"),
        };

        const width = switch (placeholder.width) {
            .none => null,
            .number => |v| v,
            .named => |arg_name| blk: {
                const arg_i = comptime meta.fieldIndex(ArgsType, arg_name) orelse
                    @compileError("no argument with name '" ++ arg_name ++ "'");
                _ = comptime arg_state.nextArg(arg_i) orelse @compileError("too few arguments");
                break :blk @field(args, arg_name);
            },
        };

        const precision = switch (placeholder.precision) {
            .none => null,
            .number => |v| v,
            .named => |arg_name| blk: {
                const arg_i = comptime meta.fieldIndex(ArgsType, arg_name) orelse
                    @compileError("no argument with name '" ++ arg_name ++ "'");
                _ = comptime arg_state.nextArg(arg_i) orelse @compileError("too few arguments");
                break :blk @field(args, arg_name);
            },
        };

        const arg_to_print = comptime arg_state.nextArg(arg_pos) orelse
            @compileError("too few arguments");

        try formatType(
            @field(args, fields_info[arg_to_print].name),
            placeholder.specifier_arg,
            FormatOptions{
                .fill = placeholder.fill,
                .alignment = placeholder.alignment,
                .width = width,
                .precision = precision,
            },
            writer,
            std.options.fmt_max_depth,
        );
    }

    if (comptime arg_state.hasUnusedArgs()) {
        const missing_count = arg_state.args_len - @popCount(arg_state.used_args);
        switch (missing_count) {
            0 => unreachable,
            1 => @compileError("unused argument in '" ++ fmt ++ "'"),
            else => @compileError(comptimePrint("{d}", .{missing_count}) ++ " unused arguments in '" ++ fmt ++ "'"),
        }
    }
}

fn cacheString(str: anytype) []const u8 {
    return &str;
}

pub const Placeholder = struct {
    specifier_arg: []const u8,
    fill: u21,
    alignment: Alignment,
    arg: Specifier,
    width: Specifier,
    precision: Specifier,

    pub fn parse(comptime str: anytype) Placeholder {
        const view = std.unicode.Utf8View.initComptime(&str);
        comptime var parser = Parser{
            .buf = &str,
            .iter = view.iterator(),
        };

        // Parse the positional argument number
        const arg = comptime parser.specifier() catch |err|
            @compileError(@errorName(err));

        // Parse the format specifier
        const specifier_arg = comptime parser.until(':');

        // Skip the colon, if present
        if (comptime parser.char()) |ch| {
            if (ch != ':') {
                @compileError("expected : or }, found '" ++ unicode.utf8EncodeComptime(ch) ++ "'");
            }
        }

        // Parse the fill character
        // The fill parameter requires the alignment parameter to be specified
        // too
        const fill = comptime if (parser.peek(1)) |ch|
            switch (ch) {
                '<', '^', '>' => parser.char().?,
                else => ' ',
            }
        else
            ' ';

        // Parse the alignment parameter
        const alignment: Alignment = comptime if (parser.peek(0)) |ch| init: {
            switch (ch) {
                '<', '^', '>' => _ = parser.char(),
                else => {},
            }
            break :init switch (ch) {
                '<' => .left,
                '^' => .center,
                else => .right,
            };
        } else .right;

        // Parse the width parameter
        const width = comptime parser.specifier() catch |err|
            @compileError(@errorName(err));

        // Skip the dot, if present
        if (comptime parser.char()) |ch| {
            if (ch != '.') {
                @compileError("expected . or }, found '" ++ unicode.utf8EncodeComptime(ch) ++ "'");
            }
        }

        // Parse the precision parameter
        const precision = comptime parser.specifier() catch |err|
            @compileError(@errorName(err));

        if (comptime parser.char()) |ch| {
            @compileError("extraneous trailing character '" ++ unicode.utf8EncodeComptime(ch) ++ "'");
        }

        return Placeholder{
            .specifier_arg = cacheString(specifier_arg[0..specifier_arg.len].*),
            .fill = fill,
            .alignment = alignment,
            .arg = arg,
            .width = width,
            .precision = precision,
        };
    }
};

pub const Specifier = union(enum) {
    none,
    number: usize,
    named: []const u8,
};

pub const Parser = struct {
    buf: []const u8,
    pos: usize = 0,
    iter: std.unicode.Utf8Iterator = undefined,

    // Returns a decimal number or null if the current character is not a
    // digit
    pub fn number(self: *@This()) ?usize {
        var r: ?usize = null;

        while (self.peek(0)) |code_point| {
            switch (code_point) {
                '0'...'9' => {
                    if (r == null) r = 0;
                    r.? *= 10;
                    r.? += code_point - '0';
                },
                else => break,
            }
            _ = self.iter.nextCodepoint();
        }

        return r;
    }

    // Returns a substring of the input starting from the current position
    // and ending where `ch` is found or until the end if not found
    pub fn until(self: *@This(), ch: u21) []const u8 {
        var result: []const u8 = &[_]u8{};
        while (self.peek(0)) |code_point| {
            if (code_point == ch)
                break;
            result = result ++ (self.iter.nextCodepointSlice() orelse &[_]u8{});
        }
        return result;
    }

    // Returns one character, if available
    pub fn char(self: *@This()) ?u21 {
        if (self.iter.nextCodepoint()) |code_point| {
            return code_point;
        }
        return null;
    }

    pub fn maybe(self: *@This(), val: u21) bool {
        if (self.peek(0) == val) {
            _ = self.iter.nextCodepoint();
            return true;
        }
        return false;
    }

    // Returns a decimal number or null if the current character is not a
    // digit
    pub fn specifier(self: *@This()) !Specifier {
        if (self.maybe('[')) {
            const arg_name = self.until(']');

            if (!self.maybe(']'))
                return @field(anyerror, "Expected closing ]");

            return Specifier{ .named = arg_name };
        }
        if (self.number()) |i|
            return Specifier{ .number = i };

        return Specifier{ .none = {} };
    }

    // Returns the n-th next character or null if that's past the end
    pub fn peek(self: *@This(), n: usize) ?u21 {
        const original_i = self.iter.i;
        defer self.iter.i = original_i;

        var i = 0;
        var code_point: ?u21 = null;
        while (i <= n) : (i += 1) {
            code_point = self.iter.nextCodepoint();
            if (code_point == null) return null;
        }
        return code_point;
    }
};

pub const ArgSetType = u32;
const max_format_args = @typeInfo(ArgSetType).Int.bits;

pub const ArgState = struct {
    next_arg: usize = 0,
    used_args: ArgSetType = 0,
    args_len: usize,

    pub fn hasUnusedArgs(self: *@This()) bool {
        return @popCount(self.used_args) != self.args_len;
    }

    pub fn nextArg(self: *@This(), arg_index: ?usize) ?usize {
        const next_index = arg_index orelse init: {
            const arg = self.next_arg;
            self.next_arg += 1;
            break :init arg;
        };

        if (next_index >= self.args_len) {
            return null;
        }

        // Mark this argument as used
        self.used_args |= @as(ArgSetType, 1) << @as(u5, @intCast(next_index));
        return next_index;
    }
};

pub fn formatAddress(value: anytype, options: FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
    _ = options;
    const T = @TypeOf(value);

    switch (@typeInfo(T)) {
        .Pointer => |info| {
            try writer.writeAll(@typeName(info.child) ++ "@");
            if (info.size == .Slice)
                try formatInt(@intFromPtr(value.ptr), 16, .lower, FormatOptions{}, writer)
            else
                try formatInt(@intFromPtr(value), 16, .lower, FormatOptions{}, writer);
            return;
        },
        .Optional => |info| {
            if (@typeInfo(info.child) == .Pointer) {
                try writer.writeAll(@typeName(info.child) ++ "@");
                try formatInt(@intFromPtr(value), 16, .lower, FormatOptions{}, writer);
                return;
            }
        },
        else => {},
    }

    @compileError("cannot format non-pointer type " ++ @typeName(T) ++ " with * specifier");
}

// This ANY const is a workaround for: https://github.com/ziglang/zig/issues/7948
const ANY = "any";

pub fn defaultSpec(comptime T: type) [:0]const u8 {
    switch (@typeInfo(T)) {
        .Array => |_| return ANY,
        .Pointer => |ptr_info| switch (ptr_info.size) {
            .One => switch (@typeInfo(ptr_info.child)) {
                .Array => |_| return ANY,
                else => {},
            },
            .Many, .C => return "*",
            .Slice => return ANY,
        },
        .Optional => |info| return "?" ++ defaultSpec(info.child),
        .ErrorUnion => |info| return "!" ++ defaultSpec(info.payload),
        else => {},
    }
    return "";
}

fn stripOptionalOrErrorUnionSpec(comptime fmt: []const u8) []const u8 {
    return if (std.mem.eql(u8, fmt[1..], ANY))
        ANY
    else
        fmt[1..];
}

pub fn invalidFmtError(comptime fmt: []const u8, value: anytype) void {
    @compileError("invalid format string '" ++ fmt ++ "' for type '" ++ @typeName(@TypeOf(value)) ++ "'");
}

pub fn formatType(
    value: anytype,
    comptime fmt: []const u8,
    options: FormatOptions,
    writer: anytype,
    max_depth: usize,
) @TypeOf(writer).Error!void {
    const T = @TypeOf(value);
    const actual_fmt = comptime if (std.mem.eql(u8, fmt, ANY))
        defaultSpec(T)
    else if (fmt.len != 0 and (fmt[0] == '?' or fmt[0] == '!')) switch (@typeInfo(T)) {
            .Optional, .ErrorUnion => fmt,
            else => stripOptionalOrErrorUnionSpec(fmt),
        } else fmt;

    if (comptime std.mem.eql(u8, actual_fmt, "*")) {
        return formatAddress(value, options, writer);
    }

    if (std.meta.hasMethod(T, "format")) {
        return try value.format(actual_fmt, options, writer);
    }

    switch (@typeInfo(T)) {
        .ComptimeInt, .Int, .ComptimeFloat, .Float => {
            return formatValue(value, actual_fmt, options, writer);
        },
        .Void => {
            if (actual_fmt.len != 0) invalidFmtError(fmt, value);
            return formatBuf("void", options, writer);
        },
        .Bool => {
            if (actual_fmt.len != 0) invalidFmtError(fmt, value);
            return formatBuf(if (value) "true" else "false", options, writer);
        },
        .Optional => {
            if (actual_fmt.len == 0 or actual_fmt[0] != '?')
                @compileError("cannot format optional without a specifier (i.e. {?} or {any})");
            const remaining_fmt = comptime stripOptionalOrErrorUnionSpec(actual_fmt);
            if (value) |payload| {
                return formatType(payload, remaining_fmt, options, writer, max_depth);
            } else {
                return formatBuf("null", options, writer);
            }
        },
        .ErrorUnion => {
            if (actual_fmt.len == 0 or actual_fmt[0] != '!')
                @compileError("cannot format error union without a specifier (i.e. {!} or {any})");
            const remaining_fmt = comptime stripOptionalOrErrorUnionSpec(actual_fmt);
            if (value) |payload| {
                return formatType(payload, remaining_fmt, options, writer, max_depth);
            } else |err| {
                return formatType(err, "", options, writer, max_depth);
            }
        },
        .ErrorSet => {
            if (actual_fmt.len != 0) invalidFmtError(fmt, value);
            try writer.writeAll("error.");
            return writer.writeAll(@errorName(value));
        },
        .Enum => |enumInfo| {
            try writer.writeAll(@typeName(T));
            if (enumInfo.is_exhaustive) {
                if (actual_fmt.len != 0) invalidFmtError(fmt, value);
                try writer.writeAll(".");
                try writer.writeAll(@tagName(value));
                return;
            }

            // Use @tagName only if value is one of known fields
            @setEvalBranchQuota(3 * enumInfo.fields.len);
            inline for (enumInfo.fields) |enumField| {
                if (@intFromEnum(value) == enumField.value) {
                    try writer.writeAll(".");
                    try writer.writeAll(@tagName(value));
                    return;
                }
            }

            try writer.writeAll("(");
            try formatType(@intFromEnum(value), actual_fmt, options, writer, max_depth);
            try writer.writeAll(")");
        },
        .Union => |info| {
            if (actual_fmt.len != 0) invalidFmtError(fmt, value);
            try writer.writeAll(@typeName(T));
            if (max_depth == 0) {
                return writer.writeAll("{ ... }");
            }
            if (info.tag_type) |UnionTagType| {
                try writer.writeAll("{ .");
                try writer.writeAll(@tagName(@as(UnionTagType, value)));
                try writer.writeAll(" = ");
                inline for (info.fields) |u_field| {
                    if (value == @field(UnionTagType, u_field.name)) {
                        try formatType(@field(value, u_field.name), ANY, options, writer, max_depth - 1);
                    }
                }
                try writer.writeAll(" }");
            } else {
                try format(writer, "@{x}", .{@intFromPtr(&value)});
            }
        },
        .Struct => |info| {
            if (actual_fmt.len != 0) invalidFmtError(fmt, value);
            if (info.is_tuple) {
                // Skip the type and field names when formatting tuples.
                if (max_depth == 0) {
                    return writer.writeAll("{ ... }");
                }
                try writer.writeAll("{");
                inline for (info.fields, 0..) |f, i| {
                    if (i == 0) {
                        try writer.writeAll(" ");
                    } else {
                        try writer.writeAll(", ");
                    }
                    try formatType(@field(value, f.name), ANY, options, writer, max_depth - 1);
                }
                return writer.writeAll(" }");
            }
            try writer.writeAll(@typeName(T));
            if (max_depth == 0) {
                return writer.writeAll("{ ... }");
            }
            try writer.writeAll("{");
            inline for (info.fields, 0..) |f, i| {
                if (i == 0) {
                    try writer.writeAll(" .");
                } else {
                    try writer.writeAll(", .");
                }
                try writer.writeAll(f.name);
                try writer.writeAll(" = ");
                try formatType(@field(value, f.name), ANY, options, writer, max_depth - 1);
            }
            try writer.writeAll(" }");
        },
        .Pointer => |ptr_info| switch (ptr_info.size) {
            .One => switch (@typeInfo(ptr_info.child)) {
                .Array, .Enum, .Union, .Struct => {
                    return formatType(value.*, actual_fmt, options, writer, max_depth);
                },
                else => return format(writer, "{s}@{x}", .{ @typeName(ptr_info.child), @intFromPtr(value) }),
            },
            .Many, .C => {
                if (actual_fmt.len == 0)
                    @compileError("cannot format pointer without a specifier (i.e. {s} or {*})");
                if (ptr_info.sentinel) |_| {
                    return formatType(mem.span(value), actual_fmt, options, writer, max_depth);
                }
                if (actual_fmt[0] == 's' and ptr_info.child == u8) {
                    return formatBuf(mem.span(value), options, writer);
                }
                invalidFmtError(fmt, value);
            },
            .Slice => {
                if (actual_fmt.len == 0)
                    @compileError("cannot format slice without a specifier (i.e. {s} or {any})");
                if (max_depth == 0) {
                    return writer.writeAll("{ ... }");
                }
                if (actual_fmt[0] == 's' and ptr_info.child == u8) {
                    return formatBuf(value, options, writer);
                }
                try writer.writeAll("{ ");
                for (value, 0..) |elem, i| {
                    try formatType(elem, actual_fmt, options, writer, max_depth - 1);
                    if (i != value.len - 1) {
                        try writer.writeAll(", ");
                    }
                }
                try writer.writeAll(" }");
            },
        },
        .Array => |info| {
            if (actual_fmt.len == 0)
                @compileError("cannot format array without a specifier (i.e. {s} or {any})");
            if (max_depth == 0) {
                return writer.writeAll("{ ... }");
            }
            if (actual_fmt[0] == 's' and info.child == u8) {
                return formatBuf(&value, options, writer);
            }
            try writer.writeAll("{ ");
            for (value, 0..) |elem, i| {
                try formatType(elem, actual_fmt, options, writer, max_depth - 1);
                if (i < value.len - 1) {
                    try writer.writeAll(", ");
                }
            }
            try writer.writeAll(" }");
        },
        .Vector => |info| {
            try writer.writeAll("{ ");
            var i: usize = 0;
            while (i < info.len) : (i += 1) {
                try formatValue(value[i], actual_fmt, options, writer);
                if (i < info.len - 1) {
                    try writer.writeAll(", ");
                }
            }
            try writer.writeAll(" }");
        },
        .Fn => @compileError("unable to format function body type, use '*const " ++ @typeName(T) ++ "' for a function pointer type"),
        .Type => {
            if (actual_fmt.len != 0) invalidFmtError(fmt, value);
            return formatBuf(@typeName(value), options, writer);
        },
        .EnumLiteral => {
            if (actual_fmt.len != 0) invalidFmtError(fmt, value);
            const buffer = [_]u8{'.'} ++ @tagName(value);
            return formatBuf(buffer, options, writer);
        },
        .Null => {
            if (actual_fmt.len != 0) invalidFmtError(fmt, value);
            return formatBuf("null", options, writer);
        },
        else => @compileError("unable to format type '" ++ @typeName(T) ++ "'"),
    }
}

fn formatValue(
    value: anytype,
    comptime fmt: []const u8,
    options: FormatOptions,
    writer: anytype,
) !void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .Float, .ComptimeFloat => return formatFloatValue(value, fmt, options, writer),
        .Int, .ComptimeInt => return formatIntValue(value, fmt, options, writer),
        .Bool => return formatBuf(if (value) "true" else "false", options, writer),
        else => comptime unreachable,
    }
}

pub fn formatIntValue(
    value: anytype,
    comptime fmt: []const u8,
    options: FormatOptions,
    writer: anytype,
) !void {
    comptime var base = 10;
    comptime var case: Case = .lower;

    const int_value = if (@TypeOf(value) == comptime_int) blk: {
        const Int = math.IntFittingRange(value, value);
        break :blk @as(Int, value);
    } else value;

    if (fmt.len == 0 or comptime std.mem.eql(u8, fmt, "d")) {
        base = 10;
        case = .lower;
    } else if (comptime std.mem.eql(u8, fmt, "c")) {
        if (@typeInfo(@TypeOf(int_value)).Int.bits <= 8) {
            return formatAsciiChar(@as(u8, int_value), options, writer);
        } else {
            @compileError("cannot print integer that is larger than 8 bits as an ASCII character");
        }
    } else if (comptime std.mem.eql(u8, fmt, "u")) {
        if (@typeInfo(@TypeOf(int_value)).Int.bits <= 21) {
            return formatUnicodeCodepoint(@as(u21, int_value), options, writer);
        } else {
            @compileError("cannot print integer that is larger than 21 bits as an UTF-8 sequence");
        }
    } else if (comptime std.mem.eql(u8, fmt, "b")) {
        base = 2;
        case = .lower;
    } else if (comptime std.mem.eql(u8, fmt, "x")) {
        base = 16;
        case = .lower;
    } else if (comptime std.mem.eql(u8, fmt, "X")) {
        base = 16;
        case = .upper;
    } else if (comptime std.mem.eql(u8, fmt, "o")) {
        base = 8;
        case = .lower;
    } else {
        invalidFmtError(fmt, value);
    }

    return formatInt(int_value, base, case, options, writer);
}

pub const format_float = @import("format_float.zig");
pub const formatFloat = format_float.formatFloat;
pub const FormatFloatError = format_float.FormatError;

fn formatFloatValue(
    value: anytype,
    comptime fmt: []const u8,
    options: FormatOptions,
    writer: anytype,
) !void {
    var buf: [format_float.bufferSize(.decimal, f64)]u8 = undefined;

    if (fmt.len == 0 or comptime std.mem.eql(u8, fmt, "e")) {
        const s = formatFloat(&buf, value, .{ .mode = .scientific, .precision = options.precision }) catch |err| switch (err) {
            error.BufferTooSmall => "(float)",
        };
        return formatBuf(s, options, writer);
    } else if (comptime std.mem.eql(u8, fmt, "d")) {
        const s = formatFloat(&buf, value, .{ .mode = .decimal, .precision = options.precision }) catch |err| switch (err) {
            error.BufferTooSmall => "(float)",
        };
        return formatBuf(s, options, writer);
    } else if (comptime std.mem.eql(u8, fmt, "x")) {
        var buf_stream = std.io.fixedBufferStream(&buf);
        formatFloatHexadecimal(value, options, buf_stream.writer()) catch |err| switch (err) {
            error.NoSpaceLeft => unreachable,
        };
        return formatBuf(buf_stream.getWritten(), options, writer);
    } else {
        invalidFmtError(fmt, value);
    }
}

test {
    _ = &format_float;
}

pub const Case = enum { lower, upper };

fn formatSliceHexImpl(comptime case: Case) type {
    const charset = "0123456789" ++ if (case == .upper) "ABCDEF" else "abcdef";

    return struct {
        pub fn formatSliceHexImpl(
            bytes: []const u8,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;
            var buf: [2]u8 = undefined;

            for (bytes) |c| {
                buf[0] = charset[c >> 4];
                buf[1] = charset[c & 15];
                try writer.writeAll(&buf);
            }
        }
    };
}

const formatSliceHexLower = formatSliceHexImpl(.lower).formatSliceHexImpl;
const formatSliceHexUpper = formatSliceHexImpl(.upper).formatSliceHexImpl;

/// Return a Formatter for a []const u8 where every byte is formatted as a pair
/// of lowercase hexadecimal digits.
pub fn fmtSliceHexLower(bytes: []const u8) std.fmt.Formatter(formatSliceHexLower) {
    return .{ .data = bytes };
}

/// Return a Formatter for a []const u8 where every byte is formatted as pair
/// of uppercase hexadecimal digits.
pub fn fmtSliceHexUpper(bytes: []const u8) std.fmt.Formatter(formatSliceHexUpper) {
    return .{ .data = bytes };
}

fn formatSliceEscapeImpl(comptime case: Case) type {
    const charset = "0123456789" ++ if (case == .upper) "ABCDEF" else "abcdef";

    return struct {
        pub fn formatSliceEscapeImpl(
            bytes: []const u8,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;
            var buf: [4]u8 = undefined;

            buf[0] = '\\';
            buf[1] = 'x';

            for (bytes) |c| {
                if (std.ascii.isPrint(c)) {
                    try writer.writeByte(c);
                } else {
                    buf[2] = charset[c >> 4];
                    buf[3] = charset[c & 15];
                    try writer.writeAll(&buf);
                }
            }
        }
    };
}

const formatSliceEscapeLower = formatSliceEscapeImpl(.lower).formatSliceEscapeImpl;
const formatSliceEscapeUpper = formatSliceEscapeImpl(.upper).formatSliceEscapeImpl;

/// Return a Formatter for a []const u8 where every non-printable ASCII
/// character is escaped as \xNN, where NN is the character in lowercase
/// hexadecimal notation.
pub fn fmtSliceEscapeLower(bytes: []const u8) std.fmt.Formatter(formatSliceEscapeLower) {
    return .{ .data = bytes };
}

/// Return a Formatter for a []const u8 where every non-printable ASCII
/// character is escaped as \xNN, where NN is the character in uppercase
/// hexadecimal notation.
pub fn fmtSliceEscapeUpper(bytes: []const u8) std.fmt.Formatter(formatSliceEscapeUpper) {
    return .{ .data = bytes };
}

fn formatSizeImpl(comptime base: comptime_int) type {
    return struct {
        fn formatSizeImpl(
            value: u64,
            comptime fmt: []const u8,
            options: FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            if (value == 0) {
                return formatBuf("0B", options, writer);
            }
            // The worst case in terms of space needed is 32 bytes + 3 for the suffix.
            var buf: [format_float.min_buffer_size + 3]u8 = undefined;

            const mags_si = " kMGTPEZY";
            const mags_iec = " KMGTPEZY";

            const log2 = math.log2(value);
            const magnitude = switch (base) {
                1000 => @min(log2 / comptime math.log2(1000), mags_si.len - 1),
                1024 => @min(log2 / 10, mags_iec.len - 1),
                else => unreachable,
            };
            const new_value = lossyCast(f64, value) / math.pow(f64, lossyCast(f64, base), lossyCast(f64, magnitude));
            const suffix = switch (base) {
                1000 => mags_si[magnitude],
                1024 => mags_iec[magnitude],
                else => unreachable,
            };

            const s = switch (magnitude) {
                0 => buf[0..formatIntBuf(&buf, value, 10, .lower, .{})],
                else => formatFloat(&buf, new_value, .{ .mode = .decimal, .precision = options.precision }) catch |err| switch (err) {
                    error.BufferTooSmall => unreachable,
                },
            };

            var i: usize = s.len;
            if (suffix == ' ') {
                buf[i] = 'B';
                i += 1;
            } else switch (base) {
                1000 => {
                    buf[i..][0..2].* = [_]u8{ suffix, 'B' };
                    i += 2;
                },
                1024 => {
                    buf[i..][0..3].* = [_]u8{ suffix, 'i', 'B' };
                    i += 3;
                },
                else => unreachable,
            }

            return formatBuf(buf[0..i], options, writer);
        }
    };
}

const formatSizeDec = formatSizeImpl(1000).formatSizeImpl;
const formatSizeBin = formatSizeImpl(1024).formatSizeImpl;

/// Return a Formatter for a u64 value representing a file size.
/// This formatter represents the number as multiple of 1000 and uses the SI
/// measurement units (kB, MB, GB, ...).
pub fn fmtIntSizeDec(value: u64) std.fmt.Formatter(formatSizeDec) {
    return .{ .data = value };
}

/// Return a Formatter for a u64 value representing a file size.
/// This formatter represents the number as multiple of 1024 and uses the IEC
/// measurement units (KiB, MiB, GiB, ...).
pub fn fmtIntSizeBin(value: u64) std.fmt.Formatter(formatSizeBin) {
    return .{ .data = value };
}

fn checkTextFmt(comptime fmt: []const u8) void {
    if (fmt.len != 1)
        @compileError("unsupported format string '" ++ fmt ++ "' when formatting text");
    switch (fmt[0]) {
    // Example of deprecation:
    // '[deprecated_specifier]' => @compileError("specifier '[deprecated_specifier]' has been deprecated, wrap your argument in `std.some_function` instead"),
        'x' => @compileError("specifier 'x' has been deprecated, wrap your argument in std.fmt.fmtSliceHexLower instead"),
        'X' => @compileError("specifier 'X' has been deprecated, wrap your argument in std.fmt.fmtSliceHexUpper instead"),
        else => {},
    }
}

pub fn formatText(
    bytes: []const u8,
    comptime fmt: []const u8,
    options: FormatOptions,
    writer: anytype,
) !void {
    comptime checkTextFmt(fmt);
    return formatBuf(bytes, options, writer);
}

pub fn formatAsciiChar(
    c: u8,
    options: FormatOptions,
    writer: anytype,
) !void {
    return formatBuf(@as(*const [1]u8, &c), options, writer);
}

pub fn formatUnicodeCodepoint(
    c: u21,
    options: FormatOptions,
    writer: anytype,
) !void {
    var buf: [4]u8 = undefined;
    const len = unicode.utf8Encode(c, &buf) catch |err| switch (err) {
        error.Utf8CannotEncodeSurrogateHalf, error.CodepointTooLarge => {
            return formatBuf(&unicode.utf8EncodeComptime(unicode.replacement_character), options, writer);
        },
    };
    return formatBuf(buf[0..len], options, writer);
}

pub fn formatBuf(
    buf: []const u8,
    options: FormatOptions,
    writer: anytype,
) !void {
    if (options.width) |min_width| {
        // In case of error assume the buffer content is ASCII-encoded
        const width = unicode.utf8CountCodepoints(buf) catch buf.len;
        const padding = if (width < min_width) min_width - width else 0;

        if (padding == 0)
            return writer.writeAll(buf);

        var fill_buffer: [4]u8 = undefined;
        const fill_utf8 = if (unicode.utf8Encode(options.fill, &fill_buffer)) |len|
            fill_buffer[0..len]
        else |err| switch (err) {
                error.Utf8CannotEncodeSurrogateHalf,
                error.CodepointTooLarge,
                => &unicode.utf8EncodeComptime(unicode.replacement_character),
            };
        switch (options.alignment) {
            .left => {
                try writer.writeAll(buf);
                try writer.writeBytesNTimes(fill_utf8, padding);
            },
            .center => {
                const left_padding = padding / 2;
                const right_padding = (padding + 1) / 2;
                try writer.writeBytesNTimes(fill_utf8, left_padding);
                try writer.writeAll(buf);
                try writer.writeBytesNTimes(fill_utf8, right_padding);
            },
            .right => {
                try writer.writeBytesNTimes(fill_utf8, padding);
                try writer.writeAll(buf);
            },
        }
    } else {
        // Fast path, avoid counting the number of codepoints
        try writer.writeAll(buf);
    }
}

pub fn formatFloatHexadecimal(
    value: anytype,
    options: FormatOptions,
    writer: anytype,
) !void {
    if (math.signbit(value)) {
        try writer.writeByte('-');
    }
    if (math.isNan(value)) {
        return writer.writeAll("nan");
    }
    if (math.isInf(value)) {
        return writer.writeAll("inf");
    }

    const T = @TypeOf(value);
    const TU = std.meta.Int(.unsigned, @bitSizeOf(T));

    const mantissa_bits = math.floatMantissaBits(T);
    const fractional_bits = math.floatFractionalBits(T);
    const exponent_bits = math.floatExponentBits(T);
    const mantissa_mask = (1 << mantissa_bits) - 1;
    const exponent_mask = (1 << exponent_bits) - 1;
    const exponent_bias = (1 << (exponent_bits - 1)) - 1;

    const as_bits = @as(TU, @bitCast(value));
    var mantissa = as_bits & mantissa_mask;
    var exponent: i32 = @as(u16, @truncate((as_bits >> mantissa_bits) & exponent_mask));

    const is_denormal = exponent == 0 and mantissa != 0;
    const is_zero = exponent == 0 and mantissa == 0;

    if (is_zero) {
        // Handle this case here to simplify the logic below.
        try writer.writeAll("0x0");
        if (options.precision) |precision| {
            if (precision > 0) {
                try writer.writeAll(".");
                try writer.writeByteNTimes('0', precision);
            }
        } else {
            try writer.writeAll(".0");
        }
        try writer.writeAll("p0");
        return;
    }

    if (is_denormal) {
        // Adjust the exponent for printing.
        exponent += 1;
    } else {
        if (fractional_bits == mantissa_bits)
            mantissa |= 1 << fractional_bits; // Add the implicit integer bit.
    }

    const mantissa_digits = (fractional_bits + 3) / 4;
    // Fill in zeroes to round the fraction width to a multiple of 4.
    mantissa <<= mantissa_digits * 4 - fractional_bits;

    if (options.precision) |precision| {
        // Round if needed.
        if (precision < mantissa_digits) {
            // We always have at least 4 extra bits.
            var extra_bits = (mantissa_digits - precision) * 4;
            // The result LSB is the Guard bit, we need two more (Round and
            // Sticky) to round the value.
            while (extra_bits > 2) {
                mantissa = (mantissa >> 1) | (mantissa & 1);
                extra_bits -= 1;
            }
            // Round to nearest, tie to even.
            mantissa |= @intFromBool(mantissa & 0b100 != 0);
            mantissa += 1;
            // Drop the excess bits.
            mantissa >>= 2;
            // Restore the alignment.
            mantissa <<= @as(math.Log2Int(TU), @intCast((mantissa_digits - precision) * 4));

            const overflow = mantissa & (1 << 1 + mantissa_digits * 4) != 0;
            // Prefer a normalized result in case of overflow.
            if (overflow) {
                mantissa >>= 1;
                exponent += 1;
            }
        }
    }

    // +1 for the decimal part.
    var buf: [1 + mantissa_digits]u8 = undefined;
    _ = formatIntBuf(&buf, mantissa, 16, .lower, .{ .fill = '0', .width = 1 + mantissa_digits });

    try writer.writeAll("0x");
    try writer.writeByte(buf[0]);
    const trimmed = mem.trimRight(u8, buf[1..], "0");
    if (options.precision) |precision| {
        if (precision > 0) try writer.writeAll(".");
    } else if (trimmed.len > 0) {
        try writer.writeAll(".");
    }
    try writer.writeAll(trimmed);
    // Add trailing zeros if explicitly requested.
    if (options.precision) |precision| if (precision > 0) {
        if (precision > trimmed.len)
            try writer.writeByteNTimes('0', precision - trimmed.len);
    };
    try writer.writeAll("p");
    try formatInt(exponent - exponent_bias, 10, .lower, .{}, writer);
}

pub fn formatInt(
    value: anytype,
    base: u8,
    case: Case,
    options: FormatOptions,
    writer: anytype,
) !void {
    assert(base >= 2);

    const int_value = if (@TypeOf(value) == comptime_int) blk: {
        const Int = math.IntFittingRange(value, value);
        break :blk @as(Int, value);
    } else value;

    const value_info = @typeInfo(@TypeOf(int_value)).Int;

    // The type must have the same size as `base` or be wider in order for the
    // division to work
    const min_int_bits = comptime @max(value_info.bits, 8);
    const MinInt = std.meta.Int(.unsigned, min_int_bits);

    const abs_value = @abs(int_value);
    // The worst case in terms of space needed is base 2, plus 1 for the sign
    var buf: [1 + @max(@as(comptime_int, value_info.bits), 1)]u8 = undefined;

    var a: MinInt = abs_value;
    var index: usize = buf.len;

    if (base == 10) {
        while (a >= 100) : (a = @divTrunc(a, 100)) {
            index -= 2;
            buf[index..][0..2].* = digits2(@as(usize, @intCast(a % 100)));
        }

        if (a < 10) {
            index -= 1;
            buf[index] = '0' + @as(u8, @intCast(a));
        } else {
            index -= 2;
            buf[index..][0..2].* = digits2(@as(usize, @intCast(a)));
        }
    } else {
        while (true) {
            const digit = a % base;
            index -= 1;
            buf[index] = digitToChar(@as(u8, @intCast(digit)), case);
            a /= base;
            if (a == 0) break;
        }
    }

    if (value_info.signedness == .signed) {
        if (value < 0) {
            // Negative integer
            index -= 1;
            buf[index] = '-';
        } else if (options.width == null or options.width.? == 0) {
            // Positive integer, omit the plus sign
        } else {
            // Positive integer
            index -= 1;
            buf[index] = '+';
        }
    }

    return formatBuf(buf[index..], options, writer);
}

pub fn formatIntBuf(out_buf: []u8, value: anytype, base: u8, case: Case, options: FormatOptions) usize {
    var fbs = std.io.fixedBufferStream(out_buf);
    formatInt(value, base, case, options, fbs.writer()) catch unreachable;
    return fbs.pos;
}

// Converts values in the range [0, 100) to a string.
pub fn digits2(value: usize) [2]u8 {
    return ("0001020304050607080910111213141516171819" ++
        "2021222324252627282930313233343536373839" ++
        "4041424344454647484950515253545556575859" ++
        "6061626364656667686970717273747576777879" ++
        "8081828384858687888990919293949596979899")[value * 2 ..][0..2].*;
}

const FormatDurationData = struct {
    ns: u64,
    negative: bool = false,
};

fn formatDuration(data: FormatDurationData, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;

    // worst case: "-XXXyXXwXXdXXhXXmXX.XXXs".len = 24
    var buf: [24]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    var buf_writer = fbs.writer();
    if (data.negative) {
        buf_writer.writeByte('-') catch unreachable;
    }

    var ns_remaining = data.ns;
    inline for (.{
        .{ .ns = 365 * std.time.ns_per_day, .sep = 'y' },
        .{ .ns = std.time.ns_per_week, .sep = 'w' },
        .{ .ns = std.time.ns_per_day, .sep = 'd' },
        .{ .ns = std.time.ns_per_hour, .sep = 'h' },
        .{ .ns = std.time.ns_per_min, .sep = 'm' },
    }) |unit| {
        if (ns_remaining >= unit.ns) {
            const units = ns_remaining / unit.ns;
            formatInt(units, 10, .lower, .{}, buf_writer) catch unreachable;
            buf_writer.writeByte(unit.sep) catch unreachable;
            ns_remaining -= units * unit.ns;
            if (ns_remaining == 0)
                return formatBuf(fbs.getWritten(), options, writer);
        }
    }

    inline for (.{
        .{ .ns = std.time.ns_per_s, .sep = "s" },
        .{ .ns = std.time.ns_per_ms, .sep = "ms" },
        .{ .ns = std.time.ns_per_us, .sep = "us" },
    }) |unit| {
        const kunits = ns_remaining * 1000 / unit.ns;
        if (kunits >= 1000) {
            formatInt(kunits / 1000, 10, .lower, .{}, buf_writer) catch unreachable;
            const frac = kunits % 1000;
            if (frac > 0) {
                // Write up to 3 decimal places
                var decimal_buf = [_]u8{ '.', 0, 0, 0 };
                _ = formatIntBuf(decimal_buf[1..], frac, 10, .lower, .{ .fill = '0', .width = 3 });
                var end: usize = 4;
                while (end > 1) : (end -= 1) {
                    if (decimal_buf[end - 1] != '0') break;
                }
                buf_writer.writeAll(decimal_buf[0..end]) catch unreachable;
            }
            buf_writer.writeAll(unit.sep) catch unreachable;
            return formatBuf(fbs.getWritten(), options, writer);
        }
    }

    formatInt(ns_remaining, 10, .lower, .{}, buf_writer) catch unreachable;
    buf_writer.writeAll("ns") catch unreachable;
    return formatBuf(fbs.getWritten(), options, writer);
}

/// Return a Formatter for number of nanoseconds according to its magnitude:
/// [#y][#w][#d][#h][#m]#[.###][n|u|m]s
pub fn fmtDuration(ns: u64) Formatter(formatDuration) {
    const data = FormatDurationData{ .ns = ns };
    return .{ .data = data };
}

test fmtDuration {
    var buf: [24]u8 = undefined;
    inline for (.{
        .{ .s = "0ns", .d = 0 },
        .{ .s = "1ns", .d = 1 },
        .{ .s = "999ns", .d = std.time.ns_per_us - 1 },
        .{ .s = "1us", .d = std.time.ns_per_us },
        .{ .s = "1.45us", .d = 1450 },
        .{ .s = "1.5us", .d = 3 * std.time.ns_per_us / 2 },
        .{ .s = "14.5us", .d = 14500 },
        .{ .s = "145us", .d = 145000 },
        .{ .s = "999.999us", .d = std.time.ns_per_ms - 1 },
        .{ .s = "1ms", .d = std.time.ns_per_ms + 1 },
        .{ .s = "1.5ms", .d = 3 * std.time.ns_per_ms / 2 },
        .{ .s = "1.11ms", .d = 1110000 },
        .{ .s = "1.111ms", .d = 1111000 },
        .{ .s = "1.111ms", .d = 1111100 },
        .{ .s = "999.999ms", .d = std.time.ns_per_s - 1 },
        .{ .s = "1s", .d = std.time.ns_per_s },
        .{ .s = "59.999s", .d = std.time.ns_per_min - 1 },
        .{ .s = "1m", .d = std.time.ns_per_min },
        .{ .s = "1h", .d = std.time.ns_per_hour },
        .{ .s = "1d", .d = std.time.ns_per_day },
        .{ .s = "1w", .d = std.time.ns_per_week },
        .{ .s = "1y", .d = 365 * std.time.ns_per_day },
        .{ .s = "1y52w23h59m59.999s", .d = 730 * std.time.ns_per_day - 1 }, // 365d = 52w1d
        .{ .s = "1y1h1.001s", .d = 365 * std.time.ns_per_day + std.time.ns_per_hour + std.time.ns_per_s + std.time.ns_per_ms },
        .{ .s = "1y1h1s", .d = 365 * std.time.ns_per_day + std.time.ns_per_hour + std.time.ns_per_s + 999 * std.time.ns_per_us },
        .{ .s = "1y1h999.999us", .d = 365 * std.time.ns_per_day + std.time.ns_per_hour + std.time.ns_per_ms - 1 },
        .{ .s = "1y1h1ms", .d = 365 * std.time.ns_per_day + std.time.ns_per_hour + std.time.ns_per_ms },
        .{ .s = "1y1h1ms", .d = 365 * std.time.ns_per_day + std.time.ns_per_hour + std.time.ns_per_ms + 1 },
        .{ .s = "1y1m999ns", .d = 365 * std.time.ns_per_day + std.time.ns_per_min + 999 },
        .{ .s = "584y49w23h34m33.709s", .d = math.maxInt(u64) },
    }) |tc| {
        const slice = try bufPrint(&buf, "{}", .{fmtDuration(tc.d)});
        try std.testing.expectEqualStrings(tc.s, slice);
    }

    inline for (.{
        .{ .s = "=======0ns", .f = "{s:=>10}", .d = 0 },
        .{ .s = "1ns=======", .f = "{s:=<10}", .d = 1 },
        .{ .s = "  999ns   ", .f = "{s:^10}", .d = std.time.ns_per_us - 1 },
    }) |tc| {
        const slice = try bufPrint(&buf, tc.f, .{fmtDuration(tc.d)});
        try std.testing.expectEqualStrings(tc.s, slice);
    }
}

fn formatDurationSigned(ns: i64, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    if (ns < 0) {
        const data = FormatDurationData{ .ns = @as(u64, @intCast(-ns)), .negative = true };
        try formatDuration(data, fmt, options, writer);
    } else {
        const data = FormatDurationData{ .ns = @as(u64, @intCast(ns)) };
        try formatDuration(data, fmt, options, writer);
    }
}

/// Return a Formatter for number of nanoseconds according to its signed magnitude:
/// [#y][#w][#d][#h][#m]#[.###][n|u|m]s
pub fn fmtDurationSigned(ns: i64) Formatter(formatDurationSigned) {
    return .{ .data = ns };
}

test fmtDurationSigned {
    var buf: [24]u8 = undefined;
    inline for (.{
        .{ .s = "0ns", .d = 0 },
        .{ .s = "1ns", .d = 1 },
        .{ .s = "-1ns", .d = -(1) },
        .{ .s = "999ns", .d = std.time.ns_per_us - 1 },
        .{ .s = "-999ns", .d = -(std.time.ns_per_us - 1) },
        .{ .s = "1us", .d = std.time.ns_per_us },
        .{ .s = "-1us", .d = -(std.time.ns_per_us) },
        .{ .s = "1.45us", .d = 1450 },
        .{ .s = "-1.45us", .d = -(1450) },
        .{ .s = "1.5us", .d = 3 * std.time.ns_per_us / 2 },
        .{ .s = "-1.5us", .d = -(3 * std.time.ns_per_us / 2) },
        .{ .s = "14.5us", .d = 14500 },
        .{ .s = "-14.5us", .d = -(14500) },
        .{ .s = "145us", .d = 145000 },
        .{ .s = "-145us", .d = -(145000) },
        .{ .s = "999.999us", .d = std.time.ns_per_ms - 1 },
        .{ .s = "-999.999us", .d = -(std.time.ns_per_ms - 1) },
        .{ .s = "1ms", .d = std.time.ns_per_ms + 1 },
        .{ .s = "-1ms", .d = -(std.time.ns_per_ms + 1) },
        .{ .s = "1.5ms", .d = 3 * std.time.ns_per_ms / 2 },
        .{ .s = "-1.5ms", .d = -(3 * std.time.ns_per_ms / 2) },
        .{ .s = "1.11ms", .d = 1110000 },
        .{ .s = "-1.11ms", .d = -(1110000) },
        .{ .s = "1.111ms", .d = 1111000 },
        .{ .s = "-1.111ms", .d = -(1111000) },
        .{ .s = "1.111ms", .d = 1111100 },
        .{ .s = "-1.111ms", .d = -(1111100) },
        .{ .s = "999.999ms", .d = std.time.ns_per_s - 1 },
        .{ .s = "-999.999ms", .d = -(std.time.ns_per_s - 1) },
        .{ .s = "1s", .d = std.time.ns_per_s },
        .{ .s = "-1s", .d = -(std.time.ns_per_s) },
        .{ .s = "59.999s", .d = std.time.ns_per_min - 1 },
        .{ .s = "-59.999s", .d = -(std.time.ns_per_min - 1) },
        .{ .s = "1m", .d = std.time.ns_per_min },
        .{ .s = "-1m", .d = -(std.time.ns_per_min) },
        .{ .s = "1h", .d = std.time.ns_per_hour },
        .{ .s = "-1h", .d = -(std.time.ns_per_hour) },
        .{ .s = "1d", .d = std.time.ns_per_day },
        .{ .s = "-1d", .d = -(std.time.ns_per_day) },
        .{ .s = "1w", .d = std.time.ns_per_week },
        .{ .s = "-1w", .d = -(std.time.ns_per_week) },
        .{ .s = "1y", .d = 365 * std.time.ns_per_day },
        .{ .s = "-1y", .d = -(365 * std.time.ns_per_day) },
        .{ .s = "1y52w23h59m59.999s", .d = 730 * std.time.ns_per_day - 1 }, // 365d = 52w1d
        .{ .s = "-1y52w23h59m59.999s", .d = -(730 * std.time.ns_per_day - 1) }, // 365d = 52w1d
        .{ .s = "1y1h1.001s", .d = 365 * std.time.ns_per_day + std.time.ns_per_hour + std.time.ns_per_s + std.time.ns_per_ms },
        .{ .s = "-1y1h1.001s", .d = -(365 * std.time.ns_per_day + std.time.ns_per_hour + std.time.ns_per_s + std.time.ns_per_ms) },
        .{ .s = "1y1h1s", .d = 365 * std.time.ns_per_day + std.time.ns_per_hour + std.time.ns_per_s + 999 * std.time.ns_per_us },
        .{ .s = "-1y1h1s", .d = -(365 * std.time.ns_per_day + std.time.ns_per_hour + std.time.ns_per_s + 999 * std.time.ns_per_us) },
        .{ .s = "1y1h999.999us", .d = 365 * std.time.ns_per_day + std.time.ns_per_hour + std.time.ns_per_ms - 1 },
        .{ .s = "-1y1h999.999us", .d = -(365 * std.time.ns_per_day + std.time.ns_per_hour + std.time.ns_per_ms - 1) },
        .{ .s = "1y1h1ms", .d = 365 * std.time.ns_per_day + std.time.ns_per_hour + std.time.ns_per_ms },
        .{ .s = "-1y1h1ms", .d = -(365 * std.time.ns_per_day + std.time.ns_per_hour + std.time.ns_per_ms) },
        .{ .s = "1y1h1ms", .d = 365 * std.time.ns_per_day + std.time.ns_per_hour + std.time.ns_per_ms + 1 },
        .{ .s = "-1y1h1ms", .d = -(365 * std.time.ns_per_day + std.time.ns_per_hour + std.time.ns_per_ms + 1) },
        .{ .s = "1y1m999ns", .d = 365 * std.time.ns_per_day + std.time.ns_per_min + 999 },
        .{ .s = "-1y1m999ns", .d = -(365 * std.time.ns_per_day + std.time.ns_per_min + 999) },
        .{ .s = "292y24w3d23h47m16.854s", .d = math.maxInt(i64) },
        .{ .s = "-292y24w3d23h47m16.854s", .d = math.minInt(i64) + 1 },
    }) |tc| {
        const slice = try bufPrint(&buf, "{}", .{fmtDurationSigned(tc.d)});
        try std.testing.expectEqualStrings(tc.s, slice);
    }

    inline for (.{
        .{ .s = "=======0ns", .f = "{s:=>10}", .d = 0 },
        .{ .s = "1ns=======", .f = "{s:=<10}", .d = 1 },
        .{ .s = "-1ns======", .f = "{s:=<10}", .d = -(1) },
        .{ .s = "  -999ns  ", .f = "{s:^10}", .d = -(std.time.ns_per_us - 1) },
    }) |tc| {
        const slice = try bufPrint(&buf, tc.f, .{fmtDurationSigned(tc.d)});
        try std.testing.expectEqualStrings(tc.s, slice);
    }
}

pub const ParseIntError = error{
/// The result cannot fit in the type specified
Overflow,

/// The input was empty or contained an invalid character
InvalidCharacter,
};

/// Creates a Formatter type from a format function. Wrapping data in Formatter(func) causes
/// the data to be formatted using the given function `func`.  `func` must be of the following
/// form:
///
///     fn formatExample(
///         data: T,
///         comptime fmt: []const u8,
///         options: std.fmt.FormatOptions,
///         writer: anytype,
///     ) !void;
///
pub fn Formatter(comptime format_fn: anytype) type {
    const Data = @typeInfo(@TypeOf(format_fn)).Fn.params[0].type.?;
    return struct {
        data: Data,
        pub fn format(
            self: @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) @TypeOf(writer).Error!void {
            try format_fn(self.data, fmt, options, writer);
        }
    };
}

/// Parses the string `buf` as signed or unsigned representation in the
/// specified base of an integral value of type `T`.
///
/// When `base` is zero the string prefix is examined to detect the true base:
///  * A prefix of "0b" implies base=2,
///  * A prefix of "0o" implies base=8,
///  * A prefix of "0x" implies base=16,
///  * Otherwise base=10 is assumed.
///
/// Ignores '_' character in `buf`.
/// See also `parseUnsigned`.
pub fn parseInt(comptime T: type, buf: []const u8, base: u8) ParseIntError!T {
    return parseIntWithGenericCharacter(T, u8, buf, base);
}

/// Like `parseInt`, but with a generic `Character` type.
pub fn parseIntWithGenericCharacter(
    comptime Result: type,
    comptime Character: type,
    buf: []const Character,
    base: u8,
) ParseIntError!Result {
    if (buf.len == 0) return error.InvalidCharacter;
    if (buf[0] == '+') return parseIntWithSign(Result, Character, buf[1..], base, .pos);
    if (buf[0] == '-') return parseIntWithSign(Result, Character, buf[1..], base, .neg);
    return parseIntWithSign(Result, Character, buf, base, .pos);
}

test parseInt {
    try std.testing.expectEqual(-10, try parseInt(i32, "-10", 10));
    try std.testing.expectEqual(10, try parseInt(i32, "+10", 10));
    try std.testing.expectEqual(10, try parseInt(u32, "+10", 10));
    try std.testing.expectError(error.Overflow, parseInt(u32, "-10", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, " 10", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "10 ", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "_10_", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "0x_10_", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "0x10_", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "0x_10", 10));
    try std.testing.expectEqual(255, try parseInt(u8, "255", 10));
    try std.testing.expectError(error.Overflow, parseInt(u8, "256", 10));

    // +0 and -0 should work for unsigned
    try std.testing.expectEqual(0, try parseInt(u8, "-0", 10));
    try std.testing.expectEqual(0, try parseInt(u8, "+0", 10));

    // ensure minInt is parsed correctly
    try std.testing.expectEqual(math.minInt(i1), try parseInt(i1, "-1", 10));
    try std.testing.expectEqual(math.minInt(i8), try parseInt(i8, "-128", 10));
    try std.testing.expectEqual(math.minInt(i43), try parseInt(i43, "-4398046511104", 10));

    // empty string or bare +- is invalid
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(i32, "", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "+", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(i32, "+", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "-", 10));
    try std.testing.expectError(error.InvalidCharacter, parseInt(i32, "-", 10));

    // autodectect the base
    try std.testing.expectEqual(111, try parseInt(i32, "111", 0));
    try std.testing.expectEqual(111, try parseInt(i32, "1_1_1", 0));
    try std.testing.expectEqual(111, try parseInt(i32, "1_1_1", 0));
    try std.testing.expectEqual(7, try parseInt(i32, "+0b111", 0));
    try std.testing.expectEqual(7, try parseInt(i32, "+0B111", 0));
    try std.testing.expectEqual(7, try parseInt(i32, "+0b1_11", 0));
    try std.testing.expectEqual(73, try parseInt(i32, "+0o111", 0));
    try std.testing.expectEqual(73, try parseInt(i32, "+0O111", 0));
    try std.testing.expectEqual(73, try parseInt(i32, "+0o11_1", 0));
    try std.testing.expectEqual(273, try parseInt(i32, "+0x111", 0));
    try std.testing.expectEqual(-7, try parseInt(i32, "-0b111", 0));
    try std.testing.expectEqual(-7, try parseInt(i32, "-0b11_1", 0));
    try std.testing.expectEqual(-73, try parseInt(i32, "-0o111", 0));
    try std.testing.expectEqual(-273, try parseInt(i32, "-0x111", 0));
    try std.testing.expectEqual(-273, try parseInt(i32, "-0X111", 0));
    try std.testing.expectEqual(-273, try parseInt(i32, "-0x1_11", 0));

    // bare binary/octal/decimal prefix is invalid
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "0b", 0));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "0o", 0));
    try std.testing.expectError(error.InvalidCharacter, parseInt(u32, "0x", 0));

    // edge cases which previously errored due to base overflowing T
    try std.testing.expectEqual(@as(i2, -2), try std.fmt.parseInt(i2, "-10", 2));
    try std.testing.expectEqual(@as(i4, -8), try std.fmt.parseInt(i4, "-10", 8));
    try std.testing.expectEqual(@as(i5, -16), try std.fmt.parseInt(i5, "-10", 16));
}

fn parseIntWithSign(
    comptime Result: type,
    comptime Character: type,
    buf: []const Character,
    base: u8,
    comptime sign: enum { pos, neg },
) ParseIntError!Result {
    if (buf.len == 0) return error.InvalidCharacter;

    var buf_base = base;
    var buf_start = buf;
    if (base == 0) {
        // Treat is as a decimal number by default.
        buf_base = 10;
        // Detect the base by looking at buf prefix.
        if (buf.len > 2 and buf[0] == '0') {
            if (math.cast(u8, buf[1])) |c| switch (std.ascii.toLower(c)) {
                'b' => {
                    buf_base = 2;
                    buf_start = buf[2..];
                },
                'o' => {
                    buf_base = 8;
                    buf_start = buf[2..];
                },
                'x' => {
                    buf_base = 16;
                    buf_start = buf[2..];
                },
                else => {},
            };
        }
    }

    const add = switch (sign) {
        .pos => math.add,
        .neg => math.sub,
    };

    // accumulate into Accumulate which is always 8 bits or larger.  this prevents
    // `buf_base` from overflowing Result.
    const info = @typeInfo(Result);
    const Accumulate = std.meta.Int(info.Int.signedness, @max(8, info.Int.bits));
    var accumulate: Accumulate = 0;

    if (buf_start[0] == '_' or buf_start[buf_start.len - 1] == '_') return error.InvalidCharacter;

    for (buf_start) |c| {
        if (c == '_') continue;
        const digit = try charToDigit(math.cast(u8, c) orelse return error.InvalidCharacter, buf_base);
        if (accumulate != 0) {
            accumulate = try math.mul(Accumulate, accumulate, math.cast(Accumulate, buf_base) orelse return error.Overflow);
        } else if (sign == .neg) {
            // The first digit of a negative number.
            // Consider parsing "-4" as an i3.
            // This should work, but positive 4 overflows i3, so we can't cast the digit to T and subtract.
            accumulate = math.cast(Accumulate, -@as(i8, @intCast(digit))) orelse return error.Overflow;
            continue;
        }
        accumulate = try add(Accumulate, accumulate, math.cast(Accumulate, digit) orelse return error.Overflow);
    }

    return if (Result == Accumulate)
        accumulate
    else
        math.cast(Result, accumulate) orelse return error.Overflow;
}

/// Parses the string `buf` as unsigned representation in the specified base
/// of an integral value of type `T`.
///
/// When `base` is zero the string prefix is examined to detect the true base:
///  * A prefix of "0b" implies base=2,
///  * A prefix of "0o" implies base=8,
///  * A prefix of "0x" implies base=16,
///  * Otherwise base=10 is assumed.
///
/// Ignores '_' character in `buf`.
/// See also `parseInt`.
pub fn parseUnsigned(comptime T: type, buf: []const u8, base: u8) ParseIntError!T {
    return parseIntWithSign(T, u8, buf, base, .pos);
}

test parseUnsigned {
    try std.testing.expectEqual(50124, try parseUnsigned(u16, "050124", 10));
    try std.testing.expectEqual(65535, try parseUnsigned(u16, "65535", 10));
    try std.testing.expectEqual(65535, try parseUnsigned(u16, "65_535", 10));
    try std.testing.expectError(error.Overflow, parseUnsigned(u16, "65536", 10));

    try std.testing.expectEqual(0xffffffffffffffff, try parseUnsigned(u64, "0ffffffffffffffff", 16));
    try std.testing.expectEqual(0xffffffffffffffff, try parseUnsigned(u64, "0f_fff_fff_fff_fff_fff", 16));
    try std.testing.expectError(error.Overflow, parseUnsigned(u64, "10000000000000000", 16));

    try std.testing.expectEqual(0xDEADBEEF, try parseUnsigned(u32, "DeadBeef", 16));

    try std.testing.expectEqual(1, try parseUnsigned(u7, "1", 10));
    try std.testing.expectEqual(8, try parseUnsigned(u7, "1000", 2));

    try std.testing.expectError(error.InvalidCharacter, parseUnsigned(u32, "f", 10));
    try std.testing.expectError(error.InvalidCharacter, parseUnsigned(u8, "109", 8));

    try std.testing.expectEqual(1442151747, try parseUnsigned(u32, "NUMBER", 36));

    // these numbers should fit even though the base itself doesn't fit in the destination type
    try std.testing.expectEqual(0, try parseUnsigned(u1, "0", 10));
    try std.testing.expectEqual(1, try parseUnsigned(u1, "1", 10));
    try std.testing.expectError(error.Overflow, parseUnsigned(u1, "2", 10));
    try std.testing.expectEqual(1, try parseUnsigned(u1, "001", 16));
    try std.testing.expectEqual(3, try parseUnsigned(u2, "3", 16));
    try std.testing.expectError(error.Overflow, parseUnsigned(u2, "4", 16));

    // parseUnsigned does not expect a sign
    try std.testing.expectError(error.InvalidCharacter, parseUnsigned(u8, "+0", 10));
    try std.testing.expectError(error.InvalidCharacter, parseUnsigned(u8, "-0", 10));

    // test empty string error
    try std.testing.expectError(error.InvalidCharacter, parseUnsigned(u8, "", 10));
}

/// Parses a number like '2G', '2Gi', or '2GiB'.
pub fn parseIntSizeSuffix(buf: []const u8, digit_base: u8) ParseIntError!usize {
    var without_B = buf;
    if (mem.endsWith(u8, buf, "B")) without_B.len -= 1;
    var without_i = without_B;
    var magnitude_base: usize = 1000;
    if (mem.endsWith(u8, without_B, "i")) {
        without_i.len -= 1;
        magnitude_base = 1024;
    }
    if (without_i.len == 0) return error.InvalidCharacter;
    const orders_of_magnitude: usize = switch (without_i[without_i.len - 1]) {
        'k', 'K' => 1,
        'M' => 2,
        'G' => 3,
        'T' => 4,
        'P' => 5,
        'E' => 6,
        'Z' => 7,
        'Y' => 8,
        'R' => 9,
        'Q' => 10,
        else => 0,
    };
    var without_suffix = without_i;
    if (orders_of_magnitude > 0) {
        without_suffix.len -= 1;
    } else if (without_i.len != without_B.len) {
        return error.InvalidCharacter;
    }
    const multiplier = math.powi(usize, magnitude_base, orders_of_magnitude) catch |err| switch (err) {
        error.Underflow => unreachable,
        error.Overflow => return error.Overflow,
    };
    const number = try std.fmt.parseInt(usize, without_suffix, digit_base);
    return math.mul(usize, number, multiplier);
}

pub fn charToDigit(c: u8, base: u8) (error{InvalidCharacter}!u8) {
    const value = switch (c) {
        '0'...'9' => c - '0',
        'A'...'Z' => c - 'A' + 10,
        'a'...'z' => c - 'a' + 10,
        else => return error.InvalidCharacter,
    };

    if (value >= base) return error.InvalidCharacter;

    return value;
}

pub fn digitToChar(digit: u8, case: Case) u8 {
    return switch (digit) {
        0...9 => digit + '0',
        10...35 => digit + ((if (case == .upper) @as(u8, 'A') else @as(u8, 'a')) - 10),
        else => unreachable,
    };
}

pub const BufPrintError = error{
/// As much as possible was written to the buffer, but it was too small to fit all the printed bytes.
NoSpaceLeft,
};

/// Print a Formatter string into `buf`. Actually just a thin wrapper around `format` and `fixedBufferStream`.
/// Returns a slice of the bytes printed to.
pub fn bufPrint(buf: []u8, comptime fmt: []const u8, args: anytype) BufPrintError![]u8 {
    var fbs = std.io.fixedBufferStream(buf);
    format(fbs.writer().any(), fmt, args) catch |err| switch (err) {
        error.NoSpaceLeft => return error.NoSpaceLeft,
        else => unreachable,
    };
    return fbs.getWritten();
}

pub fn bufPrintZ(buf: []u8, comptime fmt: []const u8, args: anytype) BufPrintError![:0]u8 {
    const result = try bufPrint(buf, fmt ++ "\x00", args);
    return result[0 .. result.len - 1 :0];
}

/// Count the characters needed for format. Useful for preallocating memory
pub fn count(comptime fmt: []const u8, args: anytype) u64 {
    var counting_writer = std.io.countingWriter(std.io.null_writer);
    format(counting_writer.writer().any(), fmt, args) catch unreachable;
    return counting_writer.bytes_written;
}

pub const AllocPrintError = error{OutOfMemory};

pub fn allocPrint(allocator: mem.Allocator, comptime fmt: []const u8, args: anytype) AllocPrintError![]u8 {
    const size = math.cast(usize, count(fmt, args)) orelse return error.OutOfMemory;
    const buf = try allocator.alloc(u8, size);
    return bufPrint(buf, fmt, args) catch |err| switch (err) {
        error.NoSpaceLeft => unreachable, // we just counted the size above
    };
}

pub fn allocPrintZ(allocator: mem.Allocator, comptime fmt: []const u8, args: anytype) AllocPrintError![:0]u8 {
    const result = try allocPrint(allocator, fmt ++ "\x00", args);
    return result[0 .. result.len - 1 :0];
}

test bufPrintIntToSlice {
    var buffer: [100]u8 = undefined;
    const buf = buffer[0..];

    try std.testing.expectEqualSlices(u8, "-1", bufPrintIntToSlice(buf, @as(i1, -1), 10, .lower, FormatOptions{}));

    try std.testing.expectEqualSlices(u8, "-101111000110000101001110", bufPrintIntToSlice(buf, @as(i32, -12345678), 2, .lower, FormatOptions{}));
    try std.testing.expectEqualSlices(u8, "-12345678", bufPrintIntToSlice(buf, @as(i32, -12345678), 10, .lower, FormatOptions{}));
    try std.testing.expectEqualSlices(u8, "-bc614e", bufPrintIntToSlice(buf, @as(i32, -12345678), 16, .lower, FormatOptions{}));
    try std.testing.expectEqualSlices(u8, "-BC614E", bufPrintIntToSlice(buf, @as(i32, -12345678), 16, .upper, FormatOptions{}));

    try std.testing.expectEqualSlices(u8, "12345678", bufPrintIntToSlice(buf, @as(u32, 12345678), 10, .upper, FormatOptions{}));

    try std.testing.expectEqualSlices(u8, "   666", bufPrintIntToSlice(buf, @as(u32, 666), 10, .lower, FormatOptions{ .width = 6 }));
    try std.testing.expectEqualSlices(u8, "  1234", bufPrintIntToSlice(buf, @as(u32, 0x1234), 16, .lower, FormatOptions{ .width = 6 }));
    try std.testing.expectEqualSlices(u8, "1234", bufPrintIntToSlice(buf, @as(u32, 0x1234), 16, .lower, FormatOptions{ .width = 1 }));

    try std.testing.expectEqualSlices(u8, "+42", bufPrintIntToSlice(buf, @as(i32, 42), 10, .lower, FormatOptions{ .width = 3 }));
    try std.testing.expectEqualSlices(u8, "-42", bufPrintIntToSlice(buf, @as(i32, -42), 10, .lower, FormatOptions{ .width = 3 }));
}

pub fn bufPrintIntToSlice(buf: []u8, value: anytype, base: u8, case: Case, options: FormatOptions) []u8 {
    return buf[0..formatIntBuf(buf, value, base, case, options)];
}

pub inline fn comptimePrint(comptime fmt: []const u8, args: anytype) *const [count(fmt, args):0]u8 {
    comptime {
        var buf: [count(fmt, args):0]u8 = undefined;
        _ = bufPrint(&buf, fmt, args) catch unreachable;
        buf[buf.len] = 0;
        const final = buf;
        return &final;
    }
}