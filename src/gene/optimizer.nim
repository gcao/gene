import tables
import ./types

# Peephole optimization patterns
type
  OptimizationPattern = object
    name: string
    pattern: seq[InstructionKind]
    replacement: proc(instructions: seq[Instruction], start: int): seq[Instruction]

var optimization_patterns: seq[OptimizationPattern] = @[]

proc register_pattern(name: string, pattern: seq[InstructionKind], 
                     replacement: proc(instructions: seq[Instruction], start: int): seq[Instruction]) =
  optimization_patterns.add(OptimizationPattern(
    name: name,
    pattern: pattern,
    replacement: replacement
  ))

# Initialize optimization patterns
proc init_patterns() =
  # Only enable safe constant folding optimizations for now
  # Pattern: PushValue + PushValue + Add -> PushValue (folded)
  register_pattern("constant_fold_add", @[IkPushValue, IkPushValue, IkAdd], 
    proc(instructions: seq[Instruction], start: int): seq[Instruction] =
      let a = instructions[start].arg0
      let b = instructions[start + 1].arg0
      if a.kind == VkInt and b.kind == VkInt:
        @[Instruction(kind: IkPushValue, arg0: (a.int64 + b.int64).to_value())]
      elif a.kind == VkFloat or b.kind == VkFloat:
        let fa = if a.kind == VkInt: a.int64.float64 else: a.float
        let fb = if b.kind == VkInt: b.int64.float64 else: b.float
        @[Instruction(kind: IkPushValue, arg0: (fa + fb).to_value())]
      else:
        @[] # Cannot optimize
  )
  
  # Pattern: PushValue + PushValue + Sub -> PushValue (folded)
  register_pattern("constant_fold_sub", @[IkPushValue, IkPushValue, IkSub],
    proc(instructions: seq[Instruction], start: int): seq[Instruction] =
      let a = instructions[start].arg0
      let b = instructions[start + 1].arg0
      if a.kind == VkInt and b.kind == VkInt:
        @[Instruction(kind: IkPushValue, arg0: (a.int64 - b.int64).to_value())]
      elif a.kind == VkFloat or b.kind == VkFloat:
        let fa = if a.kind == VkInt: a.int64.float64 else: a.float
        let fb = if b.kind == VkInt: b.int64.float64 else: b.float
        @[Instruction(kind: IkPushValue, arg0: (fa - fb).to_value())]
      else:
        @[]
  )
  
  # Pattern: PushValue + PushValue + Lt -> PushValue (folded)
  register_pattern("constant_fold_lt", @[IkPushValue, IkPushValue, IkLt],
    proc(instructions: seq[Instruction], start: int): seq[Instruction] =
      let a = instructions[start].arg0
      let b = instructions[start + 1].arg0
      if a.kind == VkInt and b.kind == VkInt:
        @[Instruction(kind: IkPushValue, arg0: (a.int64 < b.int64).to_value())]
      elif a.kind == VkFloat or b.kind == VkFloat:
        let fa = if a.kind == VkInt: a.int64.float64 else: a.float
        let fb = if b.kind == VkInt: b.int64.float64 else: b.float
        @[Instruction(kind: IkPushValue, arg0: (fa < fb).to_value())]
      else:
        @[]
  )
  
  # Pattern: PushValue + SubValue -> PushValue (folded)
  register_pattern("fold_sub_value", @[IkPushValue, IkSubValue],
    proc(instructions: seq[Instruction], start: int): seq[Instruction] =
      let a = instructions[start].arg0
      let b = instructions[start + 1].arg0
      if a.kind == VkInt and b.kind == VkInt:
        @[Instruction(kind: IkPushValue, arg0: (a.int64 - b.int64).to_value())]
      elif a.kind == VkFloat or b.kind == VkFloat:
        let fa = if a.kind == VkInt: a.int64.float64 else: a.float
        let fb = if b.kind == VkInt: b.int64.float64 else: b.float
        @[Instruction(kind: IkPushValue, arg0: (fa - fb).to_value())]
      else:
        @[]
  )
  
  # Pattern: PushValue + LtValue -> PushValue (folded)
  register_pattern("fold_lt_value", @[IkPushValue, IkLtValue],
    proc(instructions: seq[Instruction], start: int): seq[Instruction] =
      let a = instructions[start].arg0
      let b = instructions[start + 1].arg0
      if a.kind == VkInt and b.kind == VkInt:
        @[Instruction(kind: IkPushValue, arg0: (a.int64 < b.int64).to_value())]
      elif a.kind == VkFloat or b.kind == VkFloat:
        let fa = if a.kind == VkInt: a.int64.float64 else: a.float
        let fb = if b.kind == VkInt: b.int64.float64 else: b.float
        @[Instruction(kind: IkPushValue, arg0: (fa < fb).to_value())]
      else:
        @[]
  )
  
  # Pattern: Jump to next instruction -> remove
  # DISABLED: May be breaking scope tracking
  # register_pattern("eliminate_redundant_jump", @[IkJump],
  #   proc(instructions: seq[Instruction], start: int): seq[Instruction] =
  #     if start + 1 < instructions.len and instructions[start].arg0.int64 == start + 1:
  #       @[] # Remove redundant jump
  #     else:
  #       @[instructions[start]] # Keep the jump
  # )
  
  # Pattern: PushValue + Pop -> remove both
  register_pattern("eliminate_push_pop", @[IkPushValue, IkPop],
    proc(instructions: seq[Instruction], start: int): seq[Instruction] =
      @[] # Remove both instructions
  )
  
  # Pattern: VarResolve + VarResolve (same index) -> VarResolve + Dup
  register_pattern("optimize_duplicate_loads", @[IkVarResolve, IkVarResolve],
    proc(instructions: seq[Instruction], start: int): seq[Instruction] =
      if instructions[start].arg0.int64 == instructions[start + 1].arg0.int64:
        @[instructions[start], Instruction(kind: IkDup)]
      else:
        @[] # Cannot optimize
  )
  
  # Pattern: Var + VarResolve (same index) -> Dup + Var  
  register_pattern("store_load_same", @[IkVar, IkVarResolve],
    proc(instructions: seq[Instruction], start: int): seq[Instruction] =
      if instructions[start].arg0.int64 == instructions[start + 1].arg0.int64:
        @[Instruction(kind: IkDup), instructions[start]]
      else:
        @[] # Cannot optimize
  )
  
  # Pattern: JumpIfFalse to a Jump -> conditional jump to final target
  register_pattern("optimize_jump_chain", @[IkJumpIfFalse],
    proc(instructions: seq[Instruction], start: int): seq[Instruction] =
      let target = instructions[start].arg0.int64
      if target < instructions.len and instructions[target].kind == IkJump:
        @[Instruction(kind: IkJumpIfFalse, arg0: instructions[target].arg0)]
      else:
        @[] # Cannot optimize
  )
  
  # Pattern: Not + JumpIfFalse -> JumpIfTrue (invert condition)
  register_pattern("optimize_not_jump", @[IkNot, IkJumpIfFalse],
    proc(instructions: seq[Instruction], start: int): seq[Instruction] =
      # Since we don't have IkJumpIfTrue, we can't optimize this
      @[]
  )
  
  # Pattern: PushNil + Pop -> remove both
  register_pattern("eliminate_nil_pop", @[IkPushNil, IkPop],
    proc(instructions: seq[Instruction], start: int): seq[Instruction] =
      @[]
  )

# Optimize a compilation unit
proc optimize*(cu: CompilationUnit): CompilationUnit =
  if optimization_patterns.len == 0:
    init_patterns()
  
  result = CompilationUnit(
    kind: cu.kind,
    skip_return: cu.skip_return,
    instructions: @[],
    labels: initTable[Label, int](),
    matcher: cu.matcher,
  )
  
  var i = 0
  var optimized = false
  
  when defined(DEBUG_OPTIMIZER):
    echo "Starting optimization with ", cu.instructions.len, " instructions"
  
  while i < cu.instructions.len:
    var matched = false
    
    # Try to match patterns
    for pattern in optimization_patterns:
      if i + pattern.pattern.len <= cu.instructions.len:
        # Check if pattern matches
        var matches = true
        for j, kind in pattern.pattern:
          if cu.instructions[i + j].kind != kind:
            matches = false
            break
        
        if matches:
          # Apply replacement
          let replacement = pattern.replacement(cu.instructions, i)
          if replacement.len >= 0:  # Empty means pattern matched but couldn't optimize
            result.instructions.add(replacement)
            i += pattern.pattern.len
            matched = true
            optimized = true
            when defined(DEBUG_OPTIMIZER):
              echo "Applied optimization: ", pattern.name, " at instruction ", i
            break
    
    if not matched:
      # No pattern matched, keep original instruction
      result.instructions.add(cu.instructions[i])
      i += 1
  
  # Update labels if we optimized
  if optimized:
    # Need to properly recalculate label positions
    # For now, just copy the labels and let the VM handle it
    result.labels = cu.labels
  else:
    result.labels = cu.labels
  
  # Multi-pass optimization - disabled for now to avoid potential infinite loops
  # if optimized:
  #   let second_pass = optimize(result)
  #   if second_pass.instructions.len < result.instructions.len:
  #     return second_pass
  
  return result

# Public API for enabling/disabling optimization
var optimization_enabled* = false  # Disabled until we fix label/scope tracking issues

proc enable_optimization*() =
  optimization_enabled = true

proc disable_optimization*() =
  optimization_enabled = false