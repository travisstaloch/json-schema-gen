fn usage(exe_path: []const u8) void {
    std.debug.print(
        \\
        \\USAGE: $ {s} <json-file-path> <?options>
        \\  options:
        \\    --debug-json  - add a jsonParse() method to each object which prints field names.
        \\    --dump-schema - print schema json instead of generating zig code.
        \\
        \\
    , .{std.fs.path.basename(exe_path)});
}

const metak = "__meta__";
const reqk = "required";
const typesk = "type";
const nullablek = "nullable";
const fieldsk = "__fields__";
const reserved_fields = [_][]const u8{ metak, fieldsk }; // TODO StaticStringMap

const Fields = std.StringArrayHashMapUnmanaged(Node);
const root = @This();
const Node = struct {
    meta: Meta,
    fields: Fields = .{},

    pub fn deinit(n: *Node, alloc: mem.Allocator) void {
        for (n.fields.values()) |*v| v.deinit(alloc);
        n.fields.deinit(alloc);
    }

    pub const build = root.build;
    pub const check = root.check;
    pub const renderImpl = root.renderImpl;
    pub const render = root.render;

    pub fn format(n: Node, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt; // autofix
        _ = options; // autofix
        try json.stringify(n, .{ .whitespace = .indent_2 }, writer);
    }

    pub fn jsonStringify(n: Node, jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField(metak);
        {
            try jw.beginObject();

            try jw.objectField(typesk);
            {
                try jw.beginArray();
                var it = n.meta.type.iterator();
                while (it.next()) |tag| {
                    try jw.write(tag);
                }
                try jw.endArray();
            }

            try jw.objectField(reqk);
            try jw.write(n.meta.required);
            try jw.objectField(nullablek);
            try jw.write(n.meta.nullable);

            try jw.endObject();
        }

        for (n.fields.keys(), n.fields.values()) |k, v| {
            try jw.objectField(k);
            try jw.write(v);
        }

        try jw.endObject();
    }
};

const Type = std.enums.EnumSet(std.meta.Tag(json.Value));
const Meta = struct {
    type: Type = .{},
    required: bool = true,
    nullable: bool = false,
};

/// build a schema tree by visiting each node and recording
/// the types each node contains.  array nodes are flattened by reusing the
/// same tree.
fn build(node: *Node, alloc: mem.Allocator, json_node: std.json.Value) !void {
    node.meta.type.insert(json_node);
    node.meta.nullable = json_node == .null;

    switch (json_node) {
        .array => |a| {
            for (a.items) |ele| {
                try node.build(alloc, ele);
            }
        },
        .object => |o| {
            for (o.keys(), o.values()) |k, v| {
                const found = for (reserved_fields) |rf| {
                    if (mem.eql(u8, k, rf)) break true;
                } else false;
                if (found) {
                    std.log.err("name conflict. field '{s}' conflicts with reserved_fields {s}", .{ k, reserved_fields });
                    return error.NameConflict;
                }
                const child = try node.fields.getOrPut(alloc, k);
                if (!child.found_existing) {
                    child.value_ptr.* = .{ .meta = .{} };
                }
                try child.value_ptr.build(alloc, v);
            }
        },
        else => {},
    }
}

/// validate type field and set 'required' to false for fields which don't
/// always appear
pub fn check(node: *Node, json_node: json.Value) !void {
    switch (node.meta.type.count()) {
        1 => {},
        2 => {
            if (node.meta.type.contains(.array)) {
                //
            } else if (node.meta.type.contains(.null)) {
                node.meta.type.remove(.null);
                node.meta.nullable = true;
            } else {
                typeError(node.meta.type);
                return error.TypeError;
            }
        },
        else => {
            typeError(node.meta.type);
            return error.TypeError;
        },
    }

    switch (json_node) {
        .array => |a| for (a.items) |ele| try node.check(ele),
        .object => |o| {
            for (node.fields.keys()) |k| {
                if (!o.contains(k)) {
                    node.fields.getPtr(k).?.meta.required = false;
                }
            }
            for (o.keys(), o.values()) |k, v| {
                try node.fields.getPtr(k).?.check(v);
            }
        },
        else => {},
    }
}

fn typeError(t: Type) void {
    std.log.err("Expected one or two types. found {}", .{t.count()});
    var iter = t.iterator();
    while (iter.next()) |tag| {
        std.log.err("{s}", .{@tagName(tag)});
    }
}

fn renderImpl(node: *Node, depth: u8, writer: anytype, opts: Options) !void {
    const qmark: []const u8 = if (node.meta.nullable or !node.meta.required) "?" else "";

    if (node.meta.type.contains(.array) and !node.meta.type.contains(.object)) {
        try writer.print("{s}[]const ", .{qmark});
        node.meta.type.remove(.array);
        node.meta.nullable = false;
        try node.renderImpl(depth, writer, opts);
    } else if (node.meta.type.contains(.object)) {
        if (node.meta.type.contains(.array)) {
            try writer.print("{s}[]const struct {{", .{qmark});
        } else {
            try writer.print("{s}struct {{", .{qmark});
        }
        for (node.fields.keys(), node.fields.values()) |k, *v| {
            try writer.print("\n{s: >[1]}{2s}: ", .{ " ", depth * 4, k });
            if (v.meta.type.count() == 0)
                _ = try writer.write("[]const struct{}")
            else
                try v.renderImpl(depth + 1, writer, opts);

            if (!v.meta.required) {
                _ = try writer.write(" = null");
            }
            _ = try writer.write(",");
        }
        _ = try writer.write("\n");
        if (opts.debug_json) {
            try writer.writeByteNTimes(' ', depth * 4);
            _ = try writer.write("pub const jsonParse = jsonhelper.JsonParse(@This()).jsonParse;\n");
        }
        try writer.writeByteNTimes(' ', (depth - 1) * 4);
        try writer.writeByte('}');
    } else if (node.meta.type.contains(.string)) {
        try writer.print("{s}[]const u8", .{qmark});
    } else if (node.meta.type.contains(.integer)) {
        try writer.print("{s}i64", .{qmark});
    } else if (node.meta.type.contains(.float)) {
        try writer.print("{s}f64", .{qmark});
    } else if (node.meta.type.contains(.bool)) {
        try writer.print("{s}bool", .{qmark});
    } else if (node.meta.type.count() == 0 or node.meta.type.contains(.null)) {
        _ = try writer.write("?u0");
    } else {
        typeError(node.meta.type);
        return error.TypeError;
    }
}

fn render(node: *Node, writer: anytype, opts: Options) !void {
    _ = try writer.write("pub const Root = ");
    try node.renderImpl(1, writer, opts);
    _ = try writer.write(";\n");
    if (opts.debug_json)
        _ = try writer.write(
            \\const jsonhelper = @import("json-helper");
            \\
        );
}

const Options = struct {
    debug_json: bool,
    dump_tree: bool,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    var mjson_path: ?[]const u8 = null;
    var opts: Options = .{
        .debug_json = false,
        .dump_tree = false,
    };
    const E = enum {
        @"--debug-json",
        @"--dump-tree",
        @"--help",
        @"-h",
    };

    for (args[1..]) |arg| {
        if (std.meta.stringToEnum(E, arg)) |e| {
            switch (e) {
                .@"--debug-json" => {
                    opts.debug_json = true;
                },
                .@"--dump-tree" => {
                    opts.dump_tree = true;
                },
                .@"--help", .@"-h" => {
                    usage(args[0]);
                    return;
                },
            }
        } else {
            if (mjson_path != null) {
                usage(args[0]);
                std.log.err("unexpected argument '{s}'\n", .{arg});
                return error.UnexpectedArgument;
            }
            mjson_path = arg;
        }
    }

    const json_path = mjson_path orelse {
        usage(args[0]);
        std.log.err("missing json path", .{});
        return error.MissingJsonPath;
    };

    const f = try std.fs.cwd().openFile(json_path, .{});
    defer f.close();
    var jr = json.reader(alloc, f.reader());
    defer jr.deinit();

    const parsed = try json.parseFromTokenSource(json.Value, alloc, &jr, .{});
    defer parsed.deinit();
    // try std.json.stringify(parsed.value, .{}, std.io.getStdErr().writer());
    var node: Node = .{ .meta = .{} };
    defer node.deinit(alloc);
    try node.build(alloc, parsed.value);
    try node.check(parsed.value);
    if (opts.dump_tree) {
        std.debug.print("{}\n", .{node});
    } else {
        try node.render(std.io.getStdOut().writer(), opts);
    }
}

const std = @import("std");
const json = std.json;
const mem = std.mem;
