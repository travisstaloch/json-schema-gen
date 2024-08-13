pub const std_options: std.Options = .{
    .logFn = logFn,
};

var logbuf: [1024]u8 = undefined;
extern fn consoleLog(ptr: [*]const u8, len: usize) void;

fn logFn(
    comptime level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime fmt: []const u8,
    args: anytype,
) void {
    _ = scope;
    var fbs = std.io.fixedBufferStream(&logbuf);
    fbs.writer().print("[{s}]: ", .{@tagName(level)}) catch unreachable;
    fbs.writer().print(fmt, args) catch unreachable;
    consoleLog(&logbuf, fbs.pos);
}

pub fn panic(msg: []const u8, st: ?*std.builtin.StackTrace, addr: ?usize) noreturn {
    _ = st;
    _ = addr;
    log.err("panic: {s}", .{msg});
    @trap();
}

export fn getMem(len: usize) ?[*]u8 {
    log.info("getMem len {}", .{len});
    const m = std.heap.wasm_allocator.alloc(u8, len) catch return null;
    return m.ptr;
}

pub export fn parseBuildRender(
    input: [*:0]const u8,
    input_len: usize,
    debug_json: bool,
    dump_schema: bool,
    input_schema: bool, // TODO wire up in js
    include_test: bool,
) ?[*:0]u8 {
    log.info("pbr() input len {} debug_json {} dump_schema {} include_test {}", .{ input_len, debug_json, dump_schema, include_test });
    // const len = @min(20, input_len);
    // const start = input_len -| 20;
    // log.info("input\nstart {s}\nend {s}", .{ input[0..len], input[start..input_len] });
    const opts = Options{
        .debug_json = debug_json,
        .dump_schema = dump_schema,
        .input_schema = input_schema,
        .include_test = include_test,
    };
    var fbsin = std.io.fixedBufferStream(input[0..input_len]);
    var l = std.ArrayList(u8).init(std.heap.wasm_allocator);
    errdefer l.deinit();
    json_to_zig.parseBuildRender(
        std.heap.wasm_allocator,
        fbsin.reader(),
        l.writer(),
        opts,
    ) catch |e| {
        log.err("conversion error: {s}", .{@errorName(e)});
        return null;
    };
    const slice = l.toOwnedSliceSentinel(0) catch return null;
    return slice.ptr;
}

const std = @import("std");
const json_to_zig = @import("json-to-zig-schema.zig");
const Options = json_to_zig.Options;
const log = std.log;
