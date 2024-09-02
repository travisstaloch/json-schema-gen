const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // call python script to generate zig json schema.  the result becomes a
    // zig module, 'json-schema'.
    // const gencmd = b.addSystemCommand(&.{ "python3", "src/json-to-zig-schema.py" });
    // if (b.args) |args| gencmd.addArgs(args);
    // const schema_path = gencmd.captureStdOut();
    // const schema_mod = b.createModule(.{ .root_source_file = schema_path });

    // call zig script to generate a zig json schema.  the result becomes a
    // zig module, 'json-schema'.
    const gen_exe = b.addExecutable(.{
        .name = "json-to-zig-schema",
        .root_source_file = b.path("src/json-to-zig-schema.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(gen_exe);
    const gen_exe_run = b.addRunArtifact(gen_exe);
    gen_exe_run.step.dependOn(&gen_exe.step);
    if (b.args) |args| gen_exe_run.addArgs(args);
    const gen_step = b.step("gen", "Run 'json-to-zig-schema'");
    gen_step.dependOn(&gen_exe_run.step);
    const schema_path = gen_exe_run.captureStdOut();
    const schema_mod = b.createModule(.{ .root_source_file = schema_path });

    // this exe verifies the generated schema by parsing the json file used to
    // generate it.  on success it prints out the input json file path and
    // generated schema path.
    //
    // $ zig build json -- /path/to/file.json
    //
    // if the json won't parse, passing --debug-json will echo out field
    // names as they're parsed.  this might help to manually fix the schema.
    // or perhaps submit a patch to improve schema gen.
    //
    // $ zig build json -- /path/to/file.json --debug-json
    const parse_json_exe = b.addExecutable(.{
        .name = "parse-json-with-gen-schema",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (b.args != null) b.installArtifact(parse_json_exe);
    parse_json_exe.root_module.addImport("json-schema", schema_mod);
    const opts = b.addOptions();
    opts.addOptionPath("json_path", std.Build.LazyPath{ .cwd_relative = if (b.args) |args| args[0] else "" });
    opts.addOptionPath("schema_path", schema_path);
    parse_json_exe.root_module.addOptions("build-options", opts);
    const json_cmd_run = b.addRunArtifact(parse_json_exe);
    json_cmd_run.step.dependOn(&gen_exe_run.step);
    if (b.args) |args| json_cmd_run.addArgs(args);
    const run_json_step = b.step("json", "Run 'parse-json-with-gen-schema'");
    run_json_step.dependOn(&json_cmd_run.step);

    // for zls - check if main compiles
    const exe_check = b.addExecutable(.{
        .name = "check",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const check = b.step("check", "Check if main compiles");
    check.dependOn(&exe_check.step);

    const tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    const testopts = b.addOptions();
    tests.root_module.addOptions("build-options", testopts);
    const run_tests = b.addRunArtifact(tests);
    if (b.args) |args| run_tests.addArgs(args);
    const run_tests_step = b.step("test", "Run 'parse-json-with-generated'");
    run_tests_step.dependOn(&run_tests.step);

    // add module and path options to tests for each .json file in examples/
    var ex_dir = try std.fs.cwd().openDir("examples", .{ .iterate = true });
    defer ex_dir.close();
    var iter = ex_dir.iterate();
    while (try iter.next()) |e| {
        if (e.kind != .file) continue;
        if (!std.mem.eql(u8, std.fs.path.extension(e.name), ".json")) continue;
        const stem = std.fs.path.stem(e.name);
        const test_gen_exe_run = b.addRunArtifact(gen_exe);
        test_gen_exe_run.step.dependOn(&gen_exe.step);
        const ex_path = b.pathJoin(&.{ "examples", e.name });
        test_gen_exe_run.addArg(ex_path);
        run_tests.step.dependOn(&test_gen_exe_run.step);
        const gen_name = b.fmt("gen_{s}", .{stem});
        const test_schema_path = test_gen_exe_run.captureStdOut();
        tests.root_module.addImport(gen_name, b.createModule(.{
            .root_source_file = test_schema_path,
        }));
        testopts.addOptionPath(b.fmt("path_{s}", .{stem}), b.path(ex_path));
        testopts.addOptionPath(b.fmt("schema_path_{s}", .{stem}), test_schema_path);
    }

    const wasm = b.addExecutable(.{
        .name = "lib",
        .root_source_file = b.path("src/wasm.zig"),
        .target = b.resolveTargetQuery(std.Target.Query.parse(
            .{ .arch_os_abi = "wasm32-freestanding" },
        ) catch unreachable),
        .optimize = optimize,
    });
    wasm.entry = .disabled;
    wasm.rdynamic = true;
    wasm.import_symbols = true;
    const i = b.addInstallBinFile(wasm.getEmittedBin(), "../../web/lib.wasm");
    b.getInstallStep().dependOn(&i.step);
}
