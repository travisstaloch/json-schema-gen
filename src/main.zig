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
    const stdout = std.io.getStdOut().writer();
    try stdout.print("\nparsing {s}\n", .{options.json_path});
    try stdout.print("schema  {s}\n", .{options.schema_path});
    const parsed = try json.parseFromTokenSource(generated.Root, alloc, &jr, .{});
    defer parsed.deinit();
    try stdout.print("success!\n", .{});
}

const std = @import("std");
const json = std.json;
const generated = @import("json-schema");
const options = @import("build-options");
