import ../types
import std/[dynlib, tables, strformat]

# Helper for runtime errors
proc runtime_error(msg: string) =
  raise new_exception(types.Exception, msg)

type
  FFIType* = enum
    FtVoid
    FtBool
    FtInt8
    FtInt16
    FtInt32
    FtInt64
    FtUInt8
    FtUInt16
    FtUInt32
    FtUInt64
    FtFloat32
    FtFloat64
    FtPointer
    FtString
    
  CallingConvention* = enum
    CcCdecl
    CcStdcall
    CcFastcall
    
  FFISignature* = object
    return_type*: FFIType
    param_types*: seq[FFIType]
    calling_convention*: CallingConvention
    
  FFIFunction* = ref object
    name*: string
    lib_handle*: LibHandle
    fn_ptr*: pointer
    signature*: FFISignature
    
  FFILibrary* = ref object
    name*: string
    path*: string
    handle*: LibHandle
    functions*: Table[string, FFIFunction]

var loaded_libraries = initTable[string, FFILibrary]()

proc load_library*(name: string, path: string): FFILibrary =
  if name in loaded_libraries:
    return loaded_libraries[name]
  
  let handle = loadLib(path)
  if handle == nil:
    runtime_error(&"Failed to load library: {path}")
  
  result = FFILibrary(
    name: name,
    path: path,
    handle: handle,
    functions: initTable[string, FFIFunction]()
  )
  loaded_libraries[name] = result

proc unload_library*(name: string) =
  if name in loaded_libraries:
    let lib = loaded_libraries[name]
    unloadLib(lib.handle)
    loaded_libraries.del(name)

proc get_function*(lib: FFILibrary, symbol: string, signature: FFISignature): FFIFunction =
  if symbol in lib.functions:
    return lib.functions[symbol]
  
  let fn_ptr = symAddr(lib.handle, symbol)
  if fn_ptr == nil:
    runtime_error(&"Function {symbol} not found in library {lib.name}")
  
  result = FFIFunction(
    name: symbol,
    lib_handle: lib.handle,
    fn_ptr: fn_ptr,
    signature: signature
  )
  lib.functions[symbol] = result

# Type conversion helpers
proc ffi_type_to_nim*(ft: FFIType): string =
  case ft:
  of FtVoid: "void"
  of FtBool: "bool"
  of FtInt8: "int8"
  of FtInt16: "int16"
  of FtInt32: "int32"
  of FtInt64: "int64"
  of FtUInt8: "uint8"
  of FtUInt16: "uint16"
  of FtUInt32: "uint32"
  of FtUInt64: "uint64"
  of FtFloat32: "float32"
  of FtFloat64: "float64"
  of FtPointer: "pointer"
  of FtString: "cstring"

proc value_to_ffi*(v: Value, expected_type: FFIType): pointer =
  case expected_type:
  of FtInt32:
    if v.kind != VkInt:
      runtime_error("Expected integer for FFI parameter")
    var val = v.int64.int32
    result = addr val
  of FtInt64:
    if v.kind != VkInt:
      runtime_error("Expected integer for FFI parameter")
    var val = v.int64
    result = addr val
  of FtFloat32:
    if v.kind != VkFloat:
      runtime_error("Expected float for FFI parameter")
    var val = v.float.float32
    result = addr val
  of FtFloat64:
    if v.kind != VkFloat:
      runtime_error("Expected float for FFI parameter")
    var val = v.float
    result = addr val
  of FtPointer:
    # Handle various pointer types
    case v.kind:
    of VkTensor:
      result = v.ref.tensor.data_ptr
    of VkPointer:
      # For raw pointers, we need to extract the pointer value
      # This would need proper implementation based on how pointers are stored
      result = cast[pointer](v.int64)
    else:
      runtime_error("Cannot convert value to pointer for FFI")
  of FtString:
    if v.kind != VkString:
      runtime_error("Expected string for FFI parameter")
    var cstr = v.str.cstring
    result = addr cstr
  of FtBool:
    if v.kind != VkBool:
      runtime_error("Expected boolean for FFI parameter")
    var val = v.bool
    result = addr val
  else:
    runtime_error(&"Unsupported FFI type: {expected_type}")

proc ffi_to_value*(data: pointer, ffi_type: FFIType): Value =
  case ffi_type:
  of FtVoid:
    result = NIL
  of FtInt32:
    result = to_value(cast[ptr int32](data)[])
  of FtInt64:
    result = to_value(cast[ptr int64](data)[])
  of FtFloat32:
    result = to_value(cast[ptr float32](data)[])
  of FtFloat64:
    result = to_value(cast[ptr float64](data)[])
  of FtPointer:
    result = to_value(data)
  of FtString:
    let cstr = cast[ptr cstring](data)[]
    if cstr != nil:
      result = to_value($cstr)
    else:
      result = NIL
  of FtBool:
    result = to_value(cast[ptr bool](data)[])
  else:
    runtime_error(&"Unsupported FFI return type: {ffi_type}")

# Dynamic function call wrapper
proc call_ffi_function*(fn: FFIFunction, args: seq[Value]): Value =
  if args.len != fn.signature.param_types.len:
    runtime_error(&"FFI function {fn.name} expects {fn.signature.param_types.len} arguments, got {args.len}")
  
  # Convert arguments
  var ffi_args: seq[pointer] = @[]
  for i, arg in args:
    ffi_args.add(value_to_ffi(arg, fn.signature.param_types[i]))
  
  # Note: Actual FFI call would require platform-specific assembly or libffi
  # This is a simplified placeholder
  runtime_error("FFI calls not yet fully implemented - requires libffi integration")

# VM instruction handlers for FFI
proc handle_ffi_load*(vm: VirtualMachine, lib_name: string, lib_path: string) =
  let lib = load_library(lib_name, lib_path)
  vm.frame.push(to_value(lib_name))

proc handle_ffi_call*(vm: VirtualMachine, lib_name: string, fn_name: string, arg_count: int) =
  if lib_name notin loaded_libraries:
    runtime_error(&"Library {lib_name} not loaded")
  
  let lib = loaded_libraries[lib_name]
  
  # Pop arguments from stack
  var args: seq[Value] = @[]
  for i in 0..<arg_count:
    args.insert(vm.frame.pop(), 0)
  
  # Get function signature (would be stored in metadata)
  let signature = FFISignature(
    return_type: FtPointer,
    param_types: @[],
    calling_convention: CcCdecl
  )
  
  let fn = lib.get_function(fn_name, signature)
  let result = call_ffi_function(fn, args)
  vm.frame.push(result)

# Register FFI operations with VM
proc register_ffi_ops*(vm: VirtualMachine) =
  # These would be registered as native functions or VM instructions
  discard