const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // this cmd calls python script to generate json schema.  the result
    // becomes a zig module, 'json-schema'.
    const cmd = b.addSystemCommand(&.{ "python3", "src/json-to-zig-schema.py" });
    if (b.args) |args| cmd.addArg(args[0]);
    const schema_file = cmd.captureStdOut();
    const schema_mod = b.addModule("json-schema", .{
        .root_source_file = schema_file,
        .imports = &.{.{
            .name = "json-helper",
            .module = b.addModule("json-helper", .{
                .root_source_file = b.path("src/json-helper.zig"),
            }),
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
    run_json_cmd.step.dependOn(&cmd.step);
    if (b.args) |args| run_json_cmd.addArgs(args);
    const run_json_step = b.step("json", "Run 'parse-json-with-generated'");
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
}
