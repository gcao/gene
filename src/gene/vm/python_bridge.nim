import ../types
import ./ffi
import std/[tables, strformat, os]

# Helper for runtime errors
proc runtime_error(msg: string) =
  raise new_exception(types.Exception, msg)

type
  PythonObject* = ref object
    py_obj*: pointer  # PyObject*
    ref_count*: int
    
  PythonInterpreter* = ref object
    initialized*: bool
    main_module*: pointer
    globals*: pointer
    locals*: pointer
    lib*: FFILibrary

var python_interpreter: PythonInterpreter = nil

# Python C API function signatures
type
  Py_InitializeEx = proc(initsigs: cint) {.cdecl.}
  Py_FinalizeEx = proc(): cint {.cdecl.}
  PyRun_SimpleString = proc(command: cstring): cint {.cdecl.}
  PyImport_ImportModule = proc(name: cstring): pointer {.cdecl.}
  PyObject_GetAttrString = proc(obj: pointer, attr: cstring): pointer {.cdecl.}
  PyObject_CallObject = proc(callable: pointer, args: pointer): pointer {.cdecl.}
  Py_DecRef = proc(obj: pointer) {.cdecl.}
  Py_IncRef = proc(obj: pointer) {.cdecl.}
  PyLong_AsLongLong = proc(obj: pointer): clonglong {.cdecl.}
  PyFloat_AsDouble = proc(obj: pointer): cdouble {.cdecl.}
  PyUnicode_AsUTF8 = proc(obj: pointer): cstring {.cdecl.}
  PyLong_FromLongLong = proc(val: clonglong): pointer {.cdecl.}
  PyFloat_FromDouble = proc(val: cdouble): pointer {.cdecl.}
  PyUnicode_FromString = proc(str: cstring): pointer {.cdecl.}
  PyTuple_New = proc(size: cint): pointer {.cdecl.}
  PyTuple_SetItem = proc(tup: pointer, pos: cint, item: pointer): cint {.cdecl.}
  PyList_New = proc(size: cint): pointer {.cdecl.}
  PyList_SetItem = proc(list: pointer, pos: cint, item: pointer): cint {.cdecl.}
  PyDict_New = proc(): pointer {.cdecl.}
  PyDict_SetItemString = proc(dict: pointer, key: cstring, val: pointer): cint {.cdecl.}

proc find_python_lib(): string =
  # Try to find Python library
  when defined(windows):
    # Try common Python versions on Windows
    for version in ["39", "38", "37", "36"]:
      let path = &"python{version}.dll"
      if fileExists(path):
        return path
  elif defined(macosx):
    # macOS typically has Python framework
    return "/usr/local/Frameworks/Python.framework/Versions/Current/Python"
  else:
    # Linux
    for version in ["3.9", "3.8", "3.7", "3.6"]:
      let path = &"libpython{version}.so"
      if fileExists(&"/usr/lib/{path}"):
        return &"/usr/lib/{path}"
      elif fileExists(&"/usr/local/lib/{path}"):
        return &"/usr/local/lib/{path}"
  
  runtime_error("Could not find Python library")

proc init_python*(): PythonInterpreter =
  if python_interpreter != nil and python_interpreter.initialized:
    return python_interpreter
  
  let lib_path = find_python_lib()
  let lib = load_library("python", lib_path)
  
  # Initialize Python interpreter
  let py_init = cast[Py_InitializeEx](lib.get_function("Py_InitializeEx", 
    FFISignature(return_type: FtVoid, param_types: @[FtInt32], calling_convention: CcCdecl)).fn_ptr)
  
  if py_init != nil:
    py_init(0)  # Don't register signal handlers
  
  python_interpreter = PythonInterpreter(
    initialized: true,
    main_module: nil,
    globals: nil,
    locals: nil,
    lib: lib
  )
  
  # Get main module
  let import_module = cast[PyImport_ImportModule](lib.get_function("PyImport_ImportModule",
    FFISignature(return_type: FtPointer, param_types: @[FtString], calling_convention: CcCdecl)).fn_ptr)
  
  if import_module != nil:
    python_interpreter.main_module = import_module("__main__")
  
  return python_interpreter

proc finalize_python*() =
  if python_interpreter != nil and python_interpreter.initialized:
    let py_finalize = cast[Py_FinalizeEx](python_interpreter.lib.get_function("Py_FinalizeEx",
      FFISignature(return_type: FtInt32, param_types: @[], calling_convention: CcCdecl)).fn_ptr)
    
    if py_finalize != nil:
      discard py_finalize()
    
    python_interpreter.initialized = false

proc value_to_pyobject*(v: Value): pointer =
  let interp = init_python()
  let lib = interp.lib
  
  case v.kind:
  of VkNil:
    return nil  # Python None
  of VkBool:
    # Python bool is a subtype of int
    let from_long = cast[PyLong_FromLongLong](lib.get_function("PyLong_FromLongLong",
      FFISignature(return_type: FtPointer, param_types: @[FtInt64], calling_convention: CcCdecl)).fn_ptr)
    if from_long != nil:
      return from_long(if v.bool: 1 else: 0)
  of VkInt:
    let from_long = cast[PyLong_FromLongLong](lib.get_function("PyLong_FromLongLong",
      FFISignature(return_type: FtPointer, param_types: @[FtInt64], calling_convention: CcCdecl)).fn_ptr)
    if from_long != nil:
      return from_long(v.int64)
  of VkFloat:
    let from_double = cast[PyFloat_FromDouble](lib.get_function("PyFloat_FromDouble",
      FFISignature(return_type: FtPointer, param_types: @[FtFloat64], calling_convention: CcCdecl)).fn_ptr)
    if from_double != nil:
      return from_double(v.float)
  of VkString:
    let from_string = cast[PyUnicode_FromString](lib.get_function("PyUnicode_FromString",
      FFISignature(return_type: FtPointer, param_types: @[FtString], calling_convention: CcCdecl)).fn_ptr)
    if from_string != nil:
      return from_string(v.str.cstring)
  of VkArray:
    let new_list = cast[PyList_New](lib.get_function("PyList_New",
      FFISignature(return_type: FtPointer, param_types: @[FtInt32], calling_convention: CcCdecl)).fn_ptr)
    let set_item = cast[PyList_SetItem](lib.get_function("PyList_SetItem",
      FFISignature(return_type: FtInt32, param_types: @[FtPointer, FtInt32, FtPointer], calling_convention: CcCdecl)).fn_ptr)
    
    if new_list != nil and set_item != nil:
      let py_list = new_list(v.ref.arr.len.cint)
      for i, item in v.ref.arr:
        discard set_item(py_list, i.cint, value_to_pyobject(item))
      return py_list
  else:
    runtime_error(&"Cannot convert {v.kind} to Python object")

proc pyobject_to_value*(obj: pointer): Value =
  if obj == nil:
    return NIL
  
  # This would need proper type checking using Python C API
  # For now, return as opaque pointer
  result = to_value(obj)

proc python_import*(module_name: string): Value =
  let interp = init_python()
  let lib = interp.lib
  
  let import_module = cast[PyImport_ImportModule](lib.get_function("PyImport_ImportModule",
    FFISignature(return_type: FtPointer, param_types: @[FtString], calling_convention: CcCdecl)).fn_ptr)
  
  if import_module != nil:
    let py_module = import_module(module_name.cstring)
    if py_module != nil:
      return pyobject_to_value(py_module)
  
  runtime_error(&"Failed to import Python module: {module_name}")

proc python_eval*(code: string): Value =
  let interp = init_python()
  let lib = interp.lib
  
  let run_string = cast[PyRun_SimpleString](lib.get_function("PyRun_SimpleString",
    FFISignature(return_type: FtInt32, param_types: @[FtString], calling_convention: CcCdecl)).fn_ptr)
  
  if run_string != nil:
    let result = run_string(code.cstring)
    if result == 0:
      return TRUE
    else:
      return FALSE
  
  runtime_error("Failed to execute Python code")

proc python_call*(callable: Value, args: seq[Value]): Value =
  let interp = init_python()
  let lib = interp.lib
  
  if callable.kind != VkPointer:
    runtime_error("Python callable must be a pointer")
  
  let new_tuple = cast[PyTuple_New](lib.get_function("PyTuple_New",
    FFISignature(return_type: FtPointer, param_types: @[FtInt32], calling_convention: CcCdecl)).fn_ptr)
  let set_item = cast[PyTuple_SetItem](lib.get_function("PyTuple_SetItem",
    FFISignature(return_type: FtInt32, param_types: @[FtPointer, FtInt32, FtPointer], calling_convention: CcCdecl)).fn_ptr)
  let call_object = cast[PyObject_CallObject](lib.get_function("PyObject_CallObject",
    FFISignature(return_type: FtPointer, param_types: @[FtPointer, FtPointer], calling_convention: CcCdecl)).fn_ptr)
  
  if new_tuple != nil and set_item != nil and call_object != nil:
    let py_args = new_tuple(args.len.cint)
    for i, arg in args:
      discard set_item(py_args, i.cint, value_to_pyobject(arg))
    
    let result = call_object(cast[pointer](callable.int64), py_args)
    return pyobject_to_value(result)
  
  runtime_error("Failed to call Python function")

# Register Python bridge operations with VM
proc register_python_ops*(vm: VirtualMachine) =
  # These would be registered as native functions
  discard