pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2) return error.MissingJsonFilePathArg;
    const f = try std.fs.cwd().openFile(args[1], .{});
    var jr = json.reader(alloc, f.reader());
    defer jr.deinit();
    const parsed = try json.parseFromTokenSource(tmp.Root, alloc, &jr, .{});
    defer parsed.deinit();
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Successfully parsed {s}\n", .{options.json_path});
    try stdout.print("schema              {s}\n", .{options.schema_path});
}

const std = @import("std");
const json = std.json;
const tmp = @import("json-schema");
const options = @import("build-options");
