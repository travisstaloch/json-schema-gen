pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2) return error.MissingJsonFilePathArg;
    const f = try std.fs.cwd().openFile(args[1], .{});
    defer f.close();
    var jr = json.reader(alloc, f.reader());
    defer jr.deinit();
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    try stderr.print("\nparsing     {s}\n", .{options.json_path});
    try stderr.print("schema file {s}\n", .{options.schema_path});
    const parsed = try json.parseFromTokenSource(generated.Root, alloc, &jr, .{});
    defer parsed.deinit();
    try stderr.print("success!\nprinting schema to stdout\n\n", .{});
    const fschema = try std.fs.cwd().openFile(options.schema_path, .{});
    var fifo = std.fifo.LinearFifo(u8, .{ .Static = std.mem.page_size }).init();
    try fifo.pump(fschema.reader(), stdout);
}

const std = @import("std");
const json = std.json;
const generated = @import("json-schema");
const options = @import("build-options");
