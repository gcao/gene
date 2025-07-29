import tables
import ./types

const OPTIMIZATION_THRESHOLD = 100  # Optimize after 100 executions

proc should_optimize*(fn: Function): bool =
  # Check if function should be optimized
  if fn.is_optimized or fn.profile_data == nil:
    return false
  
  return fn.profile_data.execution_count >= OPTIMIZATION_THRESHOLD

proc is_invariant_symbol(pc: int, value: Value, profile: ProfileData): bool =
  # Check if a symbol resolution is invariant (always resolves to same value)
  if pc notin profile.symbol_resolutions:
    return false
  
  # For now, assume functions and compile functions are invariant
  case value.kind:
    of VkFunction, VkCompileFn, VkMacro:
      return true
    else:
      return false

proc rewrite_function*(fn: Function): CompilationUnit =
  ## Rewrite function bytecode using profiling information
  if fn.profile_data == nil or fn.body_compiled == nil:
    return fn.body_compiled
  
  let profile = fn.profile_data
  let original_cu = fn.body_compiled
  
  # Create new compilation unit
  var new_cu = CompilationUnit(
    kind: original_cu.kind,
    skip_return: original_cu.skip_return,
    instructions: @[],
    labels: initTable[Label, int](),
    matcher: original_cu.matcher,
  )
  
  # Collect invariant symbols
  var invariant_symbols = initTable[int, Value]()  # PC -> resolved value
  
  for pc, value in profile.symbol_resolutions:
    if is_invariant_symbol(pc, value, profile):
      invariant_symbols[pc] = value
  
  # Process and rewrite original instructions
  var pc = 0
  while pc < original_cu.instructions.len:
    let inst = original_cu.instructions[pc]
    
    case inst.kind:
      of IkResolveSymbol:
        if pc in invariant_symbols:
          # Replace with direct push of the resolved value
          new_cu.instructions.add(new_instr(IkPushValue, invariant_symbols[pc]))
        else:
          # Keep original instruction
          new_cu.instructions.add(inst)
      
      else:
        # Keep all other instructions unchanged
        new_cu.instructions.add(inst)
    
    pc.inc()
  
  return new_cu

proc optimize_function*(fn: Function) =
  ## Optimize a function if it meets the criteria
  if not should_optimize(fn):
    return
  
  # Rewrite the function
  let optimized_cu = rewrite_function(fn)
  
  # Store the optimized version
  fn.optimized_cu = optimized_cu
  fn.is_optimized = true
  
  # Clear profiling data to save memory
  fn.profile_data = nil