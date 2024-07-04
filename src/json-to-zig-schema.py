import sys
import json

json_path = None
debug_json = False
dump_tree = False
show_help = False

for arg in sys.argv[1:]:
  if arg.startswith('--debug-json'):
    debug_json = True
  elif arg.startswith('--dump-schema'):
    dump_tree = True
  elif arg.startswith('--help') or arg == '-h':
    show_help = True
  else:
    json_path = arg

if json_path == None or show_help:
  print()
  print(f'USAGE: $ {sys.argv[0]} <json-file-path> <?options>')
  print('  options:')
  print('    --debug-json  - add a jsonParse() method to each object which prints field names.')
  print('    --dump-schema - print schema json instead of generating zig code.')
  print()
  exit(1)

meta = '__meta__'
req = 'required'
types = 'type'
nullable = 'nullable'
fields = '__fields__'
reserved_fields = [meta, fields]

# build a schema tree by visiting each node and recording
# the types each node contains
def build_tree(tree, node):
  # set types.
  # keep a set of type names incase there are multiple.
  # convert to a string later in finish_tree().
  if not meta in tree: tree[meta] = {}
  if types in tree[meta]:
    assert type(tree[meta][types]) == set
    tree[meta][types].add(type(node).__name__)
  else:
    tree[meta][types] = set([type(node).__name__])
  # set
  tree[meta][req] = True
  tree[meta][nullable] = node == None
  if type(node) == list:
    if not fields in tree: tree[fields] = {}
    for ele in node:
      build_tree(tree[fields], ele)
  elif type(node) == dict:
    if not fields in tree: tree[fields] = {}
    for k in node.keys():
      if k in reserved_fields:
        raise(Exception(f'name conflict. field \'{k}\' conflicts with reserved_fields {reserved_fields}'))
      if not k in tree[fields]: tree[fields][k] = {}
      build_tree(tree[fields][k], node[k])

# set 'required' to false for fields which don't always appear
def check_tree(tree, node):
  if type(node) == list:
    for ele in node:
      check_tree(tree[fields], ele)
  elif type(node) == dict:
    for k in tree[fields].keys():
      if not k in node:
        tree[fields][k][meta][req] = False
    for k in node.keys():
      check_tree(tree[fields][k], node[k])


# convert types from sets to string
def finish_tree(tree, node):
  ts = tree[meta][types]
  if type(ts) != str:
    if len(ts) == 1:
      tree[meta][types] = list(ts)[0]
    elif len(ts) == 2 and 'NoneType' in ts:
      ts.remove('NoneType')
      assert len(ts) == 1
      tree[meta][types] = list(ts)[0]
      tree[meta][nullable] = True
    else:
      raise(Exception(f"TODO support multiple types {list(ts)}"))

  if type(node) == list:
    for ele in node:
      finish_tree(tree[fields], ele)
  elif type(node) == dict:
    for k in tree[fields].keys():
      if not k in node:
        tree[fields][k][meta][req] = False
    for k in node.keys():
      finish_tree(tree[fields][k], node[k])
  

def render_tree(tree, name=None, depth=0):
  if name == None:
    print("pub const Root = {")
  
  if not meta in tree or not types in tree[meta]:
    return
  
  qmark = '?' if (nullable in tree[meta] and tree[meta][nullable]) or (req in tree[meta] and not tree[meta][req]) else ''
  t = tree[meta][types]
  if t == 'list':
    print(f'{qmark}[]const ', end='')
    render_tree(tree[fields], name, depth)
  elif t == 'dict':
    print(f'{qmark}struct {{', end='')
    keys = list(tree[fields].keys())
    for key in keys:
      pad = ' ' * depth*4
      # print('//', tree[fields][key][fields].keys())
      print(f'\n{pad}{key}: ', end='')
      # if a field is always given as an empty array, render as type '[]const struct{}'
      if fields in tree[fields][key] and len(tree[fields][key][fields].keys()) == 0:
        print('[]const struct {}', end='')
      else:
        render_tree(tree[fields][key], key, depth+1)
      default_value = ' = null' if not tree[fields][key][meta][req] else ''
      print(f'{default_value},', end='')
    print()
    render_tree(tree[fields], name, depth+1)

    if debug_json:
      print(' ' * (depth)*4 + 'pub const jsonParse = jsonhelper.JsonParse(@This()).jsonParse;\n', end='')
      print(' ' * (depth-1)*4 + '}', end='')
    else:
      print(' ' * (depth-1)*4 + '}', end='')
  elif t == 'str':
    print(f'{qmark}[]const u8', end='')
  elif t == 'int':
    print(f'{qmark}i64', end='')
  elif t == 'float':
    print(f'{qmark}f64', end='')
  elif t == 'bool':
    print(f'{qmark}bool', end='')
  elif t == 'NoneType':
    # render ?u0 when a field is always null.  std.json won't parse ?void.
    print(f'?u0', end='')
  else:
    raise(Exception(f"TODO support field type {t}"))

def render(tree, node):
  print('pub const Root = ', end = '')
  render_tree(tree, js, 1)
  print(';')
  if debug_json:
    print('const jsonhelper = @import("json-helper");')



# js = json.load(open(json_path)) if json_path != None else json.load(sys.stdin)
js = json.load(open(json_path))

tree = {}
build_tree(tree, js)
check_tree(tree, js)
finish_tree(tree, js)
if dump_tree:
  print(json.dumps(tree))
else:
  render(tree, js)