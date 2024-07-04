const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // call python script to generate zig json schema.  the result becomes a
    // zig module, 'json-schema'.
    const gencmd = b.addSystemCommand(&.{ "python3", "src/json-to-zig-schema.py" });
    if (b.args) |args| gencmd.addArgs(args);
    const json_helper = b.createModule(.{
        .root_source_file = b.path("src/json-helper.zig"),
    });
    const schema_file = gencmd.captureStdOut();
    const schema_mod = b.createModule(.{
        .root_source_file = schema_file,
        .imports = &.{.{
            .name = "json-helper",
            .module = json_helper,
        }},
    });

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
    b.installArtifact(parse_json_exe);
    parse_json_exe.root_module.addImport("json-schema", schema_mod);
    const opts = b.addOptions();
    opts.addOptionPath("json_path", std.Build.LazyPath{ .cwd_relative = if (b.args) |args| args[0] else "" });
    opts.addOptionPath("schema_path", schema_file);
    parse_json_exe.root_module.addOptions("build-options", opts);
    const run_json_cmd = b.addRunArtifact(parse_json_exe);
    run_json_cmd.step.dependOn(&gencmd.step);
    if (b.args) |args| run_json_cmd.addArgs(args);
    const run_json_step = b.step("json", "Run 'parse-json-with-gen-schema'");
    run_json_step.dependOn(&run_json_cmd.step);

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
    const examples = [_][]const u8{ "1", "2", "3", "4" };
    for (0..examples.len) |i| {
        const test_gencmd = b.addSystemCommand(&.{ "python3", "src/json-to-zig-schema.py" });
        const ex_path = b.pathJoin(&.{ "examples", b.fmt("{s}.json", .{examples[i]}) });
        test_gencmd.addArg(ex_path);
        run_tests.step.dependOn(&test_gencmd.step);
        const name = b.fmt("gen_{s}", .{examples[i]});
        tests.root_module.addImport(name, b.createModule(.{
            .root_source_file = test_gencmd.captureStdOut(),
            .imports = &.{.{ .name = "json-helper", .module = json_helper }},
        }));
        testopts.addOptionPath(b.fmt("path_{s}", .{examples[i]}), b.path(ex_path));
        testopts.addOptionPath(b.fmt("schema_path_{s}", .{examples[i]}), b.path(ex_path));
    }

    if (b.args) |args| run_tests.addArgs(args);
    const run_tests_step = b.step("test", "Run 'parse-json-with-generated'");
    run_tests_step.dependOn(&run_tests.step);
}
