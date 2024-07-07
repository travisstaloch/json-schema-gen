const talloc = testing.allocator;

const example_mods = [_]type{
    @import("gen_1"),
    @import("gen_2"),
    @import("gen_3"),
    @import("gen_4"),
    @import("gen_5"),
    @import("gen_6"),
};

const example_fmts = [_]struct { []const u8, Whitespace }{
    .{
        \\[{"a":{"b":[{"key":"value"},{}]}}]
        ,
        .minified,
    },
    .{
        \\[
        \\  {
        \\    "a": {
        \\      "c": {
        \\        "d": 1
        \\      }
        \\    }
        \\  },
        \\  {
        \\    "a": {},
        \\    "b": "d"
        \\  },
        \\  {
        \\    "a": {},
        \\    "c": 1,
        \\    "d": 1.1e0,
        \\    "e": true,
        \\    "f": false,
        \\    "g": "foo",
        \\    "h": [
        \\      {},
        \\      {
        \\        "a": 1
        \\      }
        \\    ]
        \\  }
        \\]
        ,
        .indent_2,
    },
    .{
        \\{"a":{"b":{"key":"value"}}}
        ,
        .minified,
    },
    .{
        \\{"a":[]}
        ,
        .minified,
    },
    .{ // these turn into std.json.Value
        \\[1,"a"]
        ,
        .minified,
    },
    .{
        \\[{"a":1},{"b":"c"}]
        ,
        .minified,
    },
};

fn parseExample(comptime i: usize) !void {
    const path_key = std.fmt.comptimePrint("path_{}", .{i});
    const f = try std.fs.cwd().openFile(@field(build_options, path_key), .{});
    defer f.close();
    var jr = json.reader(talloc, f.reader());
    defer jr.deinit();
    // const schema_path_key = std.fmt.comptimePrint("schema_path_{}", .{i});
    // std.debug.print("{s}\n", .{@field(build_options, schema_path_key)});
    const parsed = try json.parseFromTokenSource(example_mods[i - 1].Root, talloc, &jr, .{});
    defer parsed.deinit();
    try f.seekTo(0);
    const src = try f.readToEndAlloc(talloc, 1024);
    defer talloc.free(src);
    // std.debug.print("{s}: {s}\n", .{ path_key, src });
    // std.debug.print("{}\n", .{JsonFmt(example_mods[i - 1].Root){ .t = parsed.value }});
    try testing.expectFmt(
        example_fmts[i - 1][0],
        "{}",
        .{JsonFmt(example_mods[i - 1].Root){ .t = parsed.value, .ws = example_fmts[i - 1][1] }},
    );
}

const Whitespace = std.meta.FieldType(std.json.StringifyOptions, .whitespace);

fn JsonFmt(comptime T: type) type {
    return struct {
        t: T,
        ws: Whitespace = .minified,

        pub fn format(f: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try json.stringify(f.t, .{ .whitespace = f.ws, .emit_null_optional_fields = false }, writer);
        }
    };
}

test "parse examples" {
    try parseExample(1);
    try parseExample(2);
    try parseExample(3);
    try parseExample(4);
    try parseExample(5);
    try parseExample(6);
}

test "unions" {
    const f = try std.fs.cwd().openFile(build_options.schema_path_6, .{});
    defer f.close();
    const s = try f.readToEndAlloc(talloc, 1024);
    defer talloc.free(s);
    try testing.expectEqualStrings(
        \\const std = @import("std");
        \\pub const Root = []const union(enum) {
        \\    a: i64,
        \\    b: []const u8,
        \\};
        \\
    , s);
}

const std = @import("std");
const testing = std.testing;
const json = std.json;
const build_options = @import("build-options");
