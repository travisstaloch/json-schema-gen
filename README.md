# json-schema-gen

Generate zig code from arbitrary json data which can parse it.

## Web

https://travisstaloch.github.io/

## Motivation

When you need to parse arbitrary json in zig, you usually pass `std.json.Value` to one of the parse() methods.  This is convenient but is generally slower and allocates more memory than passing a concrete type.

Also, `std.json.Value` can be a little akward at times.  Here is how it looks to access data from the [github api](https://api.github.com/search/repositories?q=topic:zig-package&page=1&per_page=100)

with std.json.Value:

```zig
const url = parsed.value.object.get("items").?
    .array.items[0].object.get("commits_url").?.string;
```
with generated schema:
```zig
const url = parsed.value.items[0].commits_url;
```

## Generate a zig schema

clone or download this project and run the following, replacing `examples/1.json` with the path to your json file.

```console
$ zig build json -- examples/1.json > /my/project/src/json-schema.zig

parsing     .../json-schema-gen/examples/1.json
schema file .../json-schema-gen/.zig-cache/o/1bcb06dde0b5dc7c91c6fe363f6d75fd/stdout
success!
printing schema to stdout

$ cat /my/project/src/json-schema.zig
pub const Root = []const struct {
    a: struct {
        b: []const struct {
            key: ?[]const u8 = null,
        },
    },
};
```

Running with --verbose shows how the build system uses `json-to-zig-schema.zig` to generate a zig schema file in the cache.  The schema file is then used by [src/main.zig](src/main.zig) to parse the input `examples/1.json` file.  The json path and generated schema paths are shown along with a 'success!' message or an error trace if parsing fails.

```console
$ zig build json --verbose -- examples/1.json
json-schema-gen/.zig-cache/o/ebdbc614762cd389f778330b79addccd/json-to-zig-schema examples/1.json
# ... omitted
.../json-schema-gen/.zig-cache/o/0ef81ace90ad368f1e00b92e39512af1/parse-json-with-gen-schema examples/1.json

parsing     .../json-schema-gen/examples/1.json
schema file .../json-schema-gen/.zig-cache/o/1bcb06dde0b5dc7c91c6fe363f6d75fd/stdout
success!
printing schema to stdout
# ... omitted
```

The [zig script](src/json-to-zig-schema.zig) has a couple options

```console
$ zig build gen -- -h

USAGE: $ json-to-zig-schema <json-file-path> <?options>
  options:
    --debug-json   - add a jsonParse() method to each object which prints field names.
    --dump-schema  - print schema json instead of generating zig code.
    --input-schema - treat input as schema json file and skip build phase.
    --include-test - add a test skeleton to ouptut.
```

## Generate a zig schema from a json schema

1. generate json schema (optional)
```console
$ zig build
$ zig-out/bin/json-to-zig-schema examples/1.json --dump-schema > /tmp/example-1-schema.json
```
2. specify it as input with the `--input-schema` flag
```console
$ zig-out/bin/json-to-zig-schema /tmp/example-1-schema.json --input-schema
pub const Root = []const struct {
    a: struct {
        b: []const struct {
            key: ?[]const u8 = null,
        },
    },
};
```

## Using generated schema

[src/main.zig](src/main.zig) and [src/tests.zig](src/tests.zig) both show how to pass the generated schema file to a std.json.parse() method.  If you want to do the same, you can

1. run `zig build json /path/to/my.json` and either redirect stdout to a file or pipe to your editor and save it next to your zig project.  lets call it `json-schema.zig`
  * redirect to file: `zig build json -- examples/1.json > /my/project/src/json-schema.zig`
  * pipe to editor: `zig build json -- examples/1.json | nvim -`
3. add this line a zig file where you want to use it: `const generated = @import("json-schema.zig");`
5. parse your json.

## Troubleshooting parse errors

If your json file won't parse, you can use the --debug-json option to generate zig code which prints field names as they are parsed.

```console
$ zig build json -- examples/1.json --debug-json
# ... omitted
a
b
key
success!
# ... omitted
```

Hopefully that narrows your search for the problem json field and helps decide what edits to make to `json-schema.zig`.  

Or if you find a way to improve the [schema gen script](src/json-to-zig-schema.zig) to fix your parse error, patches are welcome.  Please add a reproduction of your parse error to examples/ and a test case to [src/tests.zig](src/tests.zig).  You'll need to add entries for your file to `example_mods` and `example_fmts`.
