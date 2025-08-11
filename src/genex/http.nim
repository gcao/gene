import tables, strutils
import httpclient, uri
import std/json

include ../gene/extension/boilerplate

proc parse_json_internal(node: json.JsonNode): Value

proc parse_json*(json_str: string): Value =
  let json_node = json.parseJson(json_str)
  return parse_json_internal(json_node)

proc parse_json_internal(node: json.JsonNode): Value =
  case node.kind:
  of json.JNull:
    return NIL
  of json.JBool:
    return to_value(node.bval)
  of json.JInt:
    return to_value(node.num)
  of json.JFloat:
    return to_value(node.fnum)
  of json.JString:
    return new_str_value(node.str)
  of json.JObject:
    var map_table = initTable[Key, Value]()
    for k, v in node.fields:
      map_table[to_key(k)] = parse_json_internal(v)
    result = new_map_value(map_table)
  of json.JArray:
    var arr: seq[Value] = @[]
    for elem in node.elems:
      arr.add(parse_json_internal(elem))
    result = new_array_value(arr)

proc to_json*(val: Value): string =
  case val.kind:
  of VkNil:
    return "null"
  of VkBool:
    return $val.to_bool
  of VkInt:
    return $val.to_int
  of VkFloat:
    return $val.to_float
  of VkString:
    return json.escapeJson(val.str)
  of VkArray, VkVector:
    var items: seq[string] = @[]
    let r = val.ref
    for item in r.arr:
      items.add(to_json(item))
    return "[" & items.join(",") & "]"
  of VkMap:
    var items: seq[string] = @[]
    let r = val.ref
    for k, v in r.map:
      # Convert Key to symbol string
      let key_val = cast[Value](k)  # Key is a packed symbol value
      let key_str = if key_val.kind == VkSymbol:
        key_val.str
      else:
        "unknown_key"
      items.add("\"" & json.escapeJson(key_str) & "\":" & to_json(v))
    return "{" & items.join(",") & "}"
  else:
    return "null"

proc http_get*(url: string, headers: Table[string, string] = initTable[string, string]()): string =
  var client = newHttpClient()
  for k, v in headers:
    client.headers[k] = v
  result = client.getContent(url)
  client.close()

proc http_get_json*(url: string, headers: Table[string, string] = initTable[string, string]()): Value =
  let content = http_get(url, headers)
  return parse_json(content)

proc http_post*(url: string, body: string = "", headers: Table[string, string] = initTable[string, string]()): string =
  var client = newHttpClient()
  for k, v in headers:
    client.headers[k] = v
  result = client.postContent(url, body)
  client.close()

proc http_post_json*(url: string, body: Value, headers: Table[string, string] = initTable[string, string]()): Value =
  var hdrs = headers
  hdrs["Content-Type"] = "application/json"
  let json_body = to_json(body)
  let content = http_post(url, json_body, hdrs)
  return parse_json(content)

proc http_put*(url: string, body: string = "", headers: Table[string, string] = initTable[string, string]()): string =
  var client = newHttpClient()
  for k, v in headers:
    client.headers[k] = v
  result = client.request(url, HttpPut, body).body
  client.close()

proc http_delete*(url: string, headers: Table[string, string] = initTable[string, string]()): string =
  var client = newHttpClient()
  for k, v in headers:
    client.headers[k] = v
  result = client.request(url, HttpDelete).body
  client.close()

# Native function wrappers for VM
proc vm_http_get(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    let args_ref = args.ref
    if args_ref.arr.len < 1:
      raise new_exception(types.Exception, "http_get requires at least 1 argument (url)")
    
    let url = args_ref.arr[0].str
    var headers = initTable[string, string]()
    
    if args_ref.arr.len > 1 and args_ref.arr[1].kind == VkMap:
      let r = args_ref.arr[1].ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str
    
    let content = http_get(url, headers)
    return new_str_value(content)

proc vm_http_get_json(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    let args_ref = args.ref
    if args_ref.arr.len < 1:
      raise new_exception(types.Exception, "http_get_json requires at least 1 argument (url)")
    
    let url = args_ref.arr[0].str
    var headers = initTable[string, string]()
    
    if args_ref.arr.len > 1 and args_ref.arr[1].kind == VkMap:
      let r = args_ref.arr[1].ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str
    
    return http_get_json(url, headers)

proc vm_http_post(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    let args_ref = args.ref
    if args_ref.arr.len < 1:
      raise new_exception(types.Exception, "http_post requires at least 1 argument (url)")
    
    let url = args_ref.arr[0].str
    var body = ""
    var headers = initTable[string, string]()
    
    if args_ref.arr.len > 1:
      if args_ref.arr[1].kind == VkString:
        body = args_ref.arr[1].str
      elif args_ref.arr[1].kind in {VkMap, VkVector, VkArray}:
        body = to_json(args_ref.arr[1])
        headers["Content-Type"] = "application/json"
    
    if args_ref.arr.len > 2 and args_ref.arr[2].kind == VkMap:
      let r = args_ref.arr[2].ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str
    
    let content = http_post(url, body, headers)
    return new_str_value(content)

proc vm_http_post_json(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    let args_ref = args.ref
    if args_ref.arr.len < 2:
      raise new_exception(types.Exception, "http_post_json requires at least 2 arguments (url, body)")
    
    let url = args_ref.arr[0].str
    let body = args_ref.arr[1]
    var headers = initTable[string, string]()
    
    if args_ref.arr.len > 2 and args_ref.arr[2].kind == VkMap:
      let r = args_ref.arr[2].ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str
    
    return http_post_json(url, body, headers)

proc vm_http_put(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    let args_ref = args.ref
    if args_ref.arr.len < 1:
      raise new_exception(types.Exception, "http_put requires at least 1 argument (url)")
    
    let url = args_ref.arr[0].str
    var body = ""
    var headers = initTable[string, string]()
    
    if args_ref.arr.len > 1 and args_ref.arr[1].kind == VkString:
      body = args_ref.arr[1].str
    
    if args_ref.arr.len > 2 and args_ref.arr[2].kind == VkMap:
      let r = args_ref.arr[2].ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str
    
    let content = http_put(url, body, headers)
    return new_str_value(content)

proc vm_http_delete(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    let args_ref = args.ref
    if args_ref.arr.len < 1:
      raise new_exception(types.Exception, "http_delete requires at least 1 argument (url)")
    
    let url = args_ref.arr[0].str
    var headers = initTable[string, string]()
    
    if args_ref.arr.len > 1 and args_ref.arr[1].kind == VkMap:
      let r = args_ref.arr[1].ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str
    
    let content = http_delete(url, headers)
    return new_str_value(content)

proc vm_json_parse(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    let args_ref = args.ref
    if args_ref.arr.len < 1:
      raise new_exception(types.Exception, "json_parse requires 1 argument (json_string)")
    
    if args_ref.arr[0].kind != VkString:
      raise new_exception(types.Exception, "json_parse requires a string argument")
    
    return parse_json(args_ref.arr[0].str)

proc vm_json_stringify(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    let args_ref = args.ref
    if args_ref.arr.len < 1:
      raise new_exception(types.Exception, "json_stringify requires 1 argument")
    
    let json_str = to_json(args_ref.arr[0])
    return new_str_value(json_str)

{.push dynlib, exportc.}

proc init*(vm: ptr VirtualMachine): Namespace =
  result = new_namespace("http")
  
  # HTTP functions
  var fn = new_ref(VkNativeFn)
  fn.native_fn = vm_http_get
  result["get".to_key()] = fn.to_ref_value()
  
  fn = new_ref(VkNativeFn)
  fn.native_fn = vm_http_get_json
  result["get_json".to_key()] = fn.to_ref_value()
  
  fn = new_ref(VkNativeFn)
  fn.native_fn = vm_http_post
  result["post".to_key()] = fn.to_ref_value()
  
  fn = new_ref(VkNativeFn)
  fn.native_fn = vm_http_post_json
  result["post_json".to_key()] = fn.to_ref_value()
  
  fn = new_ref(VkNativeFn)
  fn.native_fn = vm_http_put
  result["put".to_key()] = fn.to_ref_value()
  
  fn = new_ref(VkNativeFn)
  fn.native_fn = vm_http_delete
  result["delete".to_key()] = fn.to_ref_value()
  
  # JSON functions
  fn = new_ref(VkNativeFn)
  fn.native_fn = vm_json_parse
  result["json_parse".to_key()] = fn.to_ref_value()
  
  fn = new_ref(VkNativeFn)
  fn.native_fn = vm_json_stringify
  result["json_stringify".to_key()] = fn.to_ref_value()

{.pop.}