import tables, strutils, strformat
import httpclient, uri
import std/json
import asynchttpserver, asyncdispatch
import std/os

include ../gene/extension/boilerplate
import ../gene/compiler
import ../gene/vm

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
    # Args is a Gene with children as the arguments
    if args.kind != VkGene:
      raise new_exception(types.Exception, "http_get: args is not a Gene")

    if args.gene.children.len < 1:
      raise new_exception(types.Exception, "http_get requires at least 1 argument (url)")

    let url = args.gene.children[0].str
    var headers = initTable[string, string]()

    if args.gene.children.len > 1 and args.gene.children[1].kind == VkMap:
      let r = args.gene.children[1].ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str

    let content = http_get(url, headers)
    return new_str_value(content)

proc vm_http_get_json(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene:
      raise new_exception(types.Exception, "http_get_json: args is not a Gene")

    if args.gene.children.len < 1:
      raise new_exception(types.Exception, "http_get_json requires at least 1 argument (url)")

    let url = args.gene.children[0].str
    var headers = initTable[string, string]()

    if args.gene.children.len > 1 and args.gene.children[1].kind == VkMap:
      let r = args.gene.children[1].ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str

    return http_get_json(url, headers)

proc vm_http_get_async(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    # Simulated async: returns a Future that is already completed with the GET result
    if args.kind != VkGene:
      raise new_exception(types.Exception, "http_get_async: args is not a Gene")
    if args.gene.children.len < 1:
      raise new_exception(types.Exception, "http_get_async requires at least 1 argument (url)")

    let url = args.gene.children[0].str
    var headers = initTable[string, string]()
    if args.gene.children.len > 1 and args.gene.children[1].kind == VkMap:
      let r = args.gene.children[1].ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str

    # Perform the request synchronously for now
    let content = http_get(url, headers)

    # Wrap in a Future and complete immediately
    var futVal = new_future_value()
    futVal.ref.future.complete(new_str_value(content))
    return futVal


proc vm_http_post(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene:
      raise new_exception(types.Exception, "http_post: args is not a Gene")

    if args.gene.children.len < 1:
      raise new_exception(types.Exception, "http_post requires at least 1 argument (url)")

    let url = args.gene.children[0].str
    var body = ""
    var headers = initTable[string, string]()

    if args.gene.children.len > 1:
      if args.gene.children[1].kind == VkString:
        body = args.gene.children[1].str
      elif args.gene.children[1].kind in {VkMap, VkVector, VkArray}:
        body = to_json(args.gene.children[1])
        headers["Content-Type"] = "application/json"

    if args.gene.children.len > 2 and args.gene.children[2].kind == VkMap:
      let r = args.gene.children[2].ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str

    let content = http_post(url, body, headers)
    return new_str_value(content)

proc vm_http_post_json(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene:
      raise new_exception(types.Exception, "http_post_json: args is not a Gene")

    if args.gene.children.len < 2:
      raise new_exception(types.Exception, "http_post_json requires at least 2 arguments (url, body)")

    let url = args.gene.children[0].str
    let body = args.gene.children[1]
    var headers = initTable[string, string]()

    if args.gene.children.len > 2 and args.gene.children[2].kind == VkMap:
      let r = args.gene.children[2].ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str

    return http_post_json(url, body, headers)

proc vm_http_put(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene:
      raise new_exception(types.Exception, "http_put: args is not a Gene")

    if args.gene.children.len < 1:
      raise new_exception(types.Exception, "http_put requires at least 1 argument (url)")

    let url = args.gene.children[0].str
    var body = ""
    var headers = initTable[string, string]()

    if args.gene.children.len > 1 and args.gene.children[1].kind == VkString:
      body = args.gene.children[1].str

    if args.gene.children.len > 2 and args.gene.children[2].kind == VkMap:
      let r = args.gene.children[2].ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str

    let content = http_put(url, body, headers)
    return new_str_value(content)

proc vm_http_delete(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene:
      raise new_exception(types.Exception, "http_delete: args is not a Gene")

    if args.gene.children.len < 1:
      raise new_exception(types.Exception, "http_delete requires at least 1 argument (url)")

    let url = args.gene.children[0].str
    var headers = initTable[string, string]()

    if args.gene.children.len > 1 and args.gene.children[1].kind == VkMap:
      let r = args.gene.children[1].ref
      for k, v in r.map:
        if v.kind == VkString:
          headers[get_symbol(cast[int](k))] = v.str

    let content = http_delete(url, headers)
    return new_str_value(content)

proc vm_json_parse(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene:
      raise new_exception(types.Exception, "json_parse: args is not a Gene")

    if args.gene.children.len < 1:
      raise new_exception(types.Exception, "json_parse requires 1 argument (json_string)")

    if args.gene.children[0].kind != VkString:
      raise new_exception(types.Exception, "json_parse requires a string argument")

    return parse_json(args.gene.children[0].str)

proc vm_json_stringify(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene:
      raise new_exception(types.Exception, "json_stringify: args is not a Gene")

    if args.gene.children.len < 1:
      raise new_exception(types.Exception, "json_stringify requires 1 argument")

    let json_str = to_json(args.gene.children[0])
    return new_str_value(json_str)

# ============= HTTP Server Support =============

# Helper to decode URL query parameters
proc decode_query(query: string): Table[string, string] =
  result = initTable[string, string]()
  if query.len == 0:
    return

  for pair in query.split('&'):
    let parts = pair.split('=', 1)
    if parts.len == 2:
      result[parts[0]] = parts[1].decodeUrl()
    elif parts.len == 1 and parts[0].len > 0:
      result[parts[0]] = ""

# HTTP Request and Response custom classes
type
  HttpRequest* = ref object of CustomValue
    path*: string
    meth*: string
    params*: Table[string, string]
    headers*: Table[string, string]
    body*: string

  HttpResponse* = ref object of CustomValue
    status*: int
    body*: string
    headers*: Table[string, string]

var RequestClass*: Class
var ResponseClass*: Class

# Create a request Value from async request
proc create_request_value(req: asynchttpserver.Request): Value =
  echo "Creating request value for: ", req.url
  let parsed_url = parseUri($req.url)

  # Create HttpRequest custom object
  var http_req = HttpRequest()
  http_req.path = parsed_url.path
  http_req.meth = $req.reqMethod
  http_req.body = req.body

  # Add query params
  http_req.params = initTable[string, string]()
  for k, v in decode_query(parsed_url.query):
    http_req.params[k] = v

  # Add headers
  http_req.headers = initTable[string, string]()
  for key, val in req.headers.pairs:
    http_req.headers[key] = val

  # Return as custom value
  var result_ref = new_ref(VkCustom)
  result_ref.custom_data = http_req
  result_ref.custom_class = RequestClass
  return result_ref.to_ref_value()

# Native function: respond helper
proc vm_respond(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene:
      raise new_exception(types.Exception, "respond: args is not a Gene")

    # Create HttpResponse custom object
    var http_resp = HttpResponse()



    http_resp.status = 200
    http_resp.body = ""
    http_resp.headers = initTable[string, string]()

    if args.gene.children.len >= 1:
      let first = args.gene.children[0]
      case first.kind:
      of VkInt:
        http_resp.status = first.to_int
        if args.gene.children.len >= 2:
          http_resp.body = args.gene.children[1].str
      of VkString:
        http_resp.body = first.str
      else:
        http_resp.body = $first

    if args.gene.children.len >= 3 and args.gene.children[2].kind == VkMap:
      let r = args.gene.children[2].ref
      for k, v in r.map:
        if v.kind == VkString:
          http_resp.headers[get_symbol(cast[int](k))] = v.str

    # Return as custom value
    var result_ref = new_ref(VkCustom)
    result_ref.custom_data = http_resp
    result_ref.custom_class = ResponseClass
    return result_ref.to_ref_value()

# Extract URL-encoded form fields from request body
proc vm_request_body_params(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene or args.gene.children.len < 1:
      raise new_exception(types.Exception, "request_body_params: invalid arguments")
    let self = args.gene.children[0]
    if self.kind != VkCustom:
      raise new_exception(types.Exception, "request_body_params: self is not a custom value")
    let req = cast[HttpRequest](self.ref.custom_data)
    var params_map = initTable[Key, Value]()
    for k, v in decode_query(req.body):
      params_map[to_key(k)] = v.to_value
    return new_map_value(params_map)

# Native methods for Request class
proc vm_request_path(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene or args.gene.children.len < 1:
      raise new_exception(types.Exception, "request_path: invalid arguments")

    let self = args.gene.children[0]
    if self.kind != VkCustom:
      raise new_exception(types.Exception, "request_path: self is not a custom value")

    let req = cast[HttpRequest](self.ref.custom_data)
    return req.path.to_value

proc vm_request_method(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene or args.gene.children.len < 1:
      raise new_exception(types.Exception, "request_method: invalid arguments")

    let self = args.gene.children[0]
    if self.kind != VkCustom:
      raise new_exception(types.Exception, "request_method: self is not a custom value")

    let req = cast[HttpRequest](self.ref.custom_data)
    return req.meth.to_value

proc vm_request_params(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene or args.gene.children.len < 1:
      raise new_exception(types.Exception, "request_params: invalid arguments")

    let self = args.gene.children[0]
    if self.kind != VkCustom:
      raise new_exception(types.Exception, "request_params: self is not a custom value")

    let req = cast[HttpRequest](self.ref.custom_data)
    var params_map = initTable[Key, Value]()
    for k, v in req.params:
      params_map[to_key(k)] = v.to_value
    return new_map_value(params_map)

proc vm_request_body(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene or args.gene.children.len < 1:
      raise new_exception(types.Exception, "request_body: invalid arguments")

    let self = args.gene.children[0]
    if self.kind != VkCustom:
      raise new_exception(types.Exception, "request_body: self is not a custom value")

    let req = cast[HttpRequest](self.ref.custom_data)
    return req.body.to_value

proc vm_request_headers(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene or args.gene.children.len < 1:
      raise new_exception(types.Exception, "request_headers: invalid arguments")

    let self = args.gene.children[0]
    if self.kind != VkCustom:
      raise new_exception(types.Exception, "request_headers: self is not a custom value")

    let req = cast[HttpRequest](self.ref.custom_data)
    var headers_map = initTable[Key, Value]()
    for k, v in req.headers:
      headers_map[to_key(k)] = v.to_value
    return new_map_value(headers_map)

proc vm_request_url(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene or args.gene.children.len < 1:
      raise new_exception(types.Exception, "request_url: invalid arguments")

    let self = args.gene.children[0]
    if self.kind != VkCustom:
      raise new_exception(types.Exception, "request_url: self is not a custom value")

    let req = cast[HttpRequest](self.ref.custom_data)
    # Construct full URL
    var url = req.path
    if req.params.len > 0:
      url &= "?"
      var pairs: seq[string] = @[]
      for k, v in req.params:
        pairs.add(k & "=" & v)
      url &= pairs.join("&")
    return url.to_value

# Native methods for Response class
proc vm_response_status(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene or args.gene.children.len < 1:
      raise new_exception(types.Exception, "response_status: invalid arguments")

    let self = args.gene.children[0]
    if self.kind != VkCustom:
      raise new_exception(types.Exception, "response_status: self is not a custom value")

    let resp = cast[HttpResponse](self.ref.custom_data)
    return resp.status.to_value

# Convenience: redirect helper returns a Response with 302 and Location header
proc vm_redirect(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene or args.gene.children.len < 1:
      raise new_exception(types.Exception, "redirect requires 1 argument (location)")
    let location = args.gene.children[0].str
    var http_resp = HttpResponse()
    http_resp.status = 302
    http_resp.body = ""
    http_resp.headers = initTable[string, string]()
    http_resp.headers["Location"] = location
    var result_ref = new_ref(VkCustom)
    result_ref.custom_data = http_resp
    result_ref.custom_class = ResponseClass
    return result_ref.to_ref_value()

# Constructor for Response class
proc vm_response_new(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene:
      raise new_exception(types.Exception, "Response.new: args is not a Gene")

    # Create HttpResponse custom object
    var http_resp = HttpResponse()
    http_resp.status = 200
    http_resp.body = ""
    http_resp.headers = initTable[string, string]()



    # Parse arguments - (new Response status body headers)
    # Skip first arg which is the class itself
    let actual_args = if args.gene.children.len > 0: args.gene.children[1..^1] else: @[]

    if actual_args.len >= 1:
      let first = actual_args[0]
      case first.kind:
      of VkInt:
        http_resp.status = first.to_int
        if actual_args.len >= 2:
          http_resp.body = actual_args[1].str
        if actual_args.len >= 3 and actual_args[2].kind == VkMap:
          let r = actual_args[2].ref
          for k, v in r.map:
            if v.kind == VkString:
              http_resp.headers[get_symbol(cast[int](k))] = v.str
      of VkString:
        http_resp.status = 200
        http_resp.body = first.str
        if actual_args.len >= 2 and actual_args[1].kind == VkMap:
          let r = actual_args[1].ref
          for k, v in r.map:
            if v.kind == VkString:
              http_resp.headers[get_symbol(cast[int](k))] = v.str
      else:
        http_resp.body = $first

    # Return as custom value
    var result_ref = new_ref(VkCustom)
    result_ref.custom_data = http_resp
    result_ref.custom_class = ResponseClass
    return result_ref.to_ref_value()

# Global handler storage (simple approach for now)
var global_handler: Value
var global_vm: VirtualMachine

# Native function: start HTTP server
proc vm_start_server(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    if args.kind != VkGene:
      raise new_exception(types.Exception, "start_server: args is not a Gene")

    if args.gene.children.len < 2:
      raise new_exception(types.Exception, "start_server requires 2 arguments (port, handler)")

    let port = args.gene.children[0].to_int
    global_handler = args.gene.children[1]
    global_vm = vm  # Store ref
    # Handler registered

    proc handle_request(req: asynchttpserver.Request) {.async.} =
      echo "[HTTP] Request received:"
      echo "  Method: ", req.reqMethod
      echo "  URL: ", req.url
      echo "  Path: ", req.url.path
      echo "  Headers count: ", req.headers.len
      {.cast(gcsafe).}:
        # Create request value
        echo "Creating request value..."
        let gene_req = create_request_value(req)
        echo "Request value created, kind: ", gene_req.kind

        try:
          echo "[HTTP] Processing request with handler..."
          # Call the Gene handler function
          var response_val: Value
          echo "[HTTP] Global handler kind: ", global_handler.kind
          echo "[HTTP] Global VM nil? ", global_vm == nil
          if global_handler.kind == VkFunction:
            # Create a gene with the request as argument
            var args_gene = new_gene(NIL)
            args_gene.children.add(gene_req)
            let args_value = args_gene.to_gene_value()

            echo "[HTTP] Calling handler function..."
            # Call the handler function through the VM
            if global_handler.kind != VkFunction:
              echo "[HTTP] ERROR: Handler is not a function, it's: ", global_handler.kind
              raise new_exception(types.Exception, "Handler is not a function")
            
            # Functions should always be references
            if global_handler.ref == nil:
              echo "[HTTP] ERROR: Handler has nil ref"
              raise new_exception(types.Exception, "Handler has nil ref")
            
            let f = global_handler.ref.fn
            echo "[HTTP] Function object exists: ", f != nil
            if f.body_compiled == nil:
              echo "[HTTP] Compiling function body..."
              f.compile()
            echo "[HTTP] Function compiled"

            # Save current VM state
            let saved_cu = global_vm.cu
            let saved_frame = global_vm.frame
            let saved_pc = global_vm.pc

            # Set up for function execution
            global_vm.cu = f.body_compiled
            global_vm.pc = 0
            global_vm.frame = new_frame()
            global_vm.frame.args = args_value
            global_vm.frame.ns = f.ns
            global_vm.frame.scope = new_scope(f.scope_tracker, f.parent_scope)

            echo "[HTTP] Executing handler..."
            # Execute the handler
            response_val = global_vm.exec()
            echo "[HTTP] Handler executed, result: ", response_val

            # Restore VM state
            global_vm.cu = saved_cu
            global_vm.frame = saved_frame
            global_vm.pc = saved_pc
          else:
            # Fallback to hardcoded responses
            let parsed_url = parseUri(req.url.path)
            var http_resp = HttpResponse()

            if parsed_url.path == "/hello":
              http_resp.status = 200
              http_resp.body = "Hello, World!"
            elif parsed_url.path == "/api/status":
              http_resp.status = 200
              http_resp.body = """{"status": "ok"}"""
              http_resp.headers["Content-Type"] = "application/json"
            elif parsed_url.path == "/":
              http_resp.status = 200
              http_resp.body = "Welcome to Gene HTTP Server"
            else:
              http_resp.status = 404
              http_resp.body = "Not Found"

            response_val = new_ref(VkCustom).to_ref_value()
            response_val.ref.custom_data = http_resp
            response_val.ref.custom_class = ResponseClass

          # Extract response data
          echo "Response value kind: ", response_val.kind
          if response_val.kind == VkCustom and response_val.ref.custom_class == ResponseClass:
            let http_resp = cast[HttpResponse](response_val.ref.custom_data)
            var resp_headers = newHttpHeaders()
            for k, v in http_resp.headers:
              resp_headers[k] = v
            await req.respond(HttpCode(http_resp.status), http_resp.body, resp_headers)
          elif response_val.kind == VkString:
            # Simple string response
            await req.respond(Http200, response_val.str)
          else:
            # Response is not a proper Response object
            await req.respond(Http200, $response_val)
        except CatchableError as e:
          echo "Error in handler: ", e.msg
          await req.respond(Http500, "Internal Server Error: " & e.msg)

    echo fmt"[HTTP] Starting HTTP server on port {port}..."

    # Start the async server
    var server = newAsyncHttpServer()
    echo "[HTTP] Creating async server..."

    # Start serving
    echo "[HTTP] Server listening on port ", port

    try:
      # Start the server and register it with async dispatcher
      asyncCheck server.serve(Port(port), handle_request)
      echo "[HTTP] Server registered with async dispatcher"
      echo "[HTTP] Has pending operations after registration: ", hasPendingOperations()

      # Return control to VM - VM will handle polling
      return NIL

    except OSError as e:
      echo "Error starting server: ", e.msg
      raise new_exception(types.Exception, "Failed to start server: " & e.msg)
    except CatchableError as e:
      echo "Unexpected error: ", e.msg
      raise new_exception(types.Exception, "Server error: " & e.msg)

# Native function: run_event_loop (for keeping server running)
proc vm_run_event_loop(vm: VirtualMachine, args: Value): Value {.gcsafe, nimcall.} =
  {.cast(gcsafe).}:
    echo "[HTTP] Starting event loop..."
    echo "[HTTP] hasPendingOperations at start: ", hasPendingOperations()

    var pollCount = 0
    # Main event loop - runs indefinitely
    while true:
      try:
        # Poll for async events
        poll(10)  # Poll with 10ms timeout
        pollCount.inc
        
        if pollCount mod 100 == 0:
          echo "[HTTP] Event loop: ", pollCount, " polls, has ops: ", hasPendingOperations()
        
        # Small sleep to prevent CPU hogging
        if pollCount mod 10 == 0:
          os.sleep(1)
      except CatchableError as e:
        echo "[HTTP] Error in event loop: ", e.msg
        # Continue running even on error
        os.sleep(10)

    return NIL

{.push dynlib, exportc.}

proc http_get_wrapper(vm: VirtualMachine, args: Value): Value {.gcsafe.} =
  # Wrapper that can be called directly
  vm_http_get(vm, args)

proc init*(vm: ptr VirtualMachine): Namespace =
  result = new_namespace("http")

  # Initialize Request and Response classes
  RequestClass = new_class("Request", nil)
  ResponseClass = new_class("Response", nil)

  # Add Request class methods
  var meth: Method

  # Request.path method
  meth = Method(name: "path", callable: NIL)
  var method_fn = new_ref(VkNativeFn)
  method_fn.native_fn = vm_request_path
  meth.callable = method_fn.to_ref_value()
  RequestClass.methods["path".to_key()] = meth

  # Request.method method
  meth = Method(name: "method", callable: NIL)
  method_fn = new_ref(VkNativeFn)
  method_fn.native_fn = vm_request_method
  meth.callable = method_fn.to_ref_value()
  RequestClass.methods["method".to_key()] = meth

  # Request.url method
  meth = Method(name: "url", callable: NIL)
  method_fn = new_ref(VkNativeFn)
  method_fn.native_fn = vm_request_url
  meth.callable = method_fn.to_ref_value()
  RequestClass.methods["url".to_key()] = meth

  # Request.params method
  meth = Method(name: "params", callable: NIL)
  method_fn = new_ref(VkNativeFn)
  method_fn.native_fn = vm_request_params
  meth.callable = method_fn.to_ref_value()
  RequestClass.methods["params".to_key()] = meth

  # Request.body method
  meth = Method(name: "body", callable: NIL)
  method_fn = new_ref(VkNativeFn)
  method_fn.native_fn = vm_request_body
  meth.callable = method_fn.to_ref_value()
  RequestClass.methods["body".to_key()] = meth

  # Request.headers method
  meth = Method(name: "headers", callable: NIL)
  method_fn = new_ref(VkNativeFn)
  method_fn.native_fn = vm_request_headers
  meth.callable = method_fn.to_ref_value()
  RequestClass.methods["headers".to_key()] = meth

  # Request.body_params method
  meth = Method(name: "body_params", callable: NIL)
  method_fn = new_ref(VkNativeFn)
  method_fn.native_fn = vm_request_body_params
  meth.callable = method_fn.to_ref_value()
  RequestClass.methods["body_params".to_key()] = meth

  # Response constructor
  var resp_constructor = new_ref(VkNativeFn)
  resp_constructor.native_fn = vm_response_new
  ResponseClass.constructor = resp_constructor.to_ref_value()

  # Response.status method
  meth = Method(name: "status", callable: NIL)
  method_fn = new_ref(VkNativeFn)
  method_fn.native_fn = vm_response_status
  meth.callable = method_fn.to_ref_value()
  ResponseClass.methods["status".to_key()] = meth

  # HTTP functions
  var fn = new_ref(VkNativeFn)
  fn.native_fn = vm_http_get
  result["get".to_key()] = fn.to_ref_value()

  fn = new_ref(VkNativeFn)
  fn.native_fn = vm_http_get_json
  result["get_json".to_key()] = fn.to_ref_value()

  fn = new_ref(VkNativeFn)
  fn.native_fn = vm_http_get_async
  result["get_async".to_key()] = fn.to_ref_value()

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

  # HTTP Server functions
  fn = new_ref(VkNativeFn)
  fn.native_fn = vm_respond
  result["respond".to_key()] = fn.to_ref_value()

  fn = new_ref(VkNativeFn)
  fn.native_fn = vm_redirect
  result["redirect".to_key()] = fn.to_ref_value()

  fn = new_ref(VkNativeFn)
  fn.native_fn = vm_start_server
  result["start_server".to_key()] = fn.to_ref_value()

  fn = new_ref(VkNativeFn)
  fn.native_fn = vm_run_event_loop
  result["run_event_loop".to_key()] = fn.to_ref_value()

  # Register request accessor functions
  fn = new_ref(VkNativeFn)
  fn.native_fn = vm_request_path
  result["request_path".to_key()] = fn.to_ref_value()

  fn = new_ref(VkNativeFn)
  fn.native_fn = vm_request_method
  result["request_method".to_key()] = fn.to_ref_value()

  fn = new_ref(VkNativeFn)
  fn.native_fn = vm_request_params
  result["request_params".to_key()] = fn.to_ref_value()

  # Export Request and Response classes
  var req_ref = new_ref(VkClass)
  req_ref.class = RequestClass
  result["Request".to_key()] = req_ref.to_ref_value()

  var resp_ref = new_ref(VkClass)
  resp_ref.class = ResponseClass
  result["Response".to_key()] = resp_ref.to_ref_value()

{.pop.}