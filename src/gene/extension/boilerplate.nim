# Boilerplate for Gene VM extensions
# All extensions should include this file

import ../types

# Global VM pointer set by the main program
var VM*: ptr VirtualMachine

proc set_globals*(vm: ptr VirtualMachine) {.exportc, dynlib.} =
  ## Called by the main program to set global VM pointer
  VM = vm

# Helper to create native function value
proc wrap_native_fn*(fn: NativeFn): Value =
  fn

# Wrappers for exception handling
template wrap_exception*(body: untyped): untyped =
  try:
    body
  except CatchableError as e:
    raise new_exception(types.Exception, e.msg)