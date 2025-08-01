## Instruction Fusion Optimization
## 
## This module implements instruction fusion - combining multiple VM instructions
## into single fused instructions for better performance.
##
## The fusion process modifies the CompilationUnit in place to avoid memory
## management issues that can occur when creating new CompilationUnits during
## nested compilation scenarios.

import ./types

# Public API
var fusion_enabled* = true

type
  FusionPattern = object
    name: string
    pattern: seq[InstructionKind]
    canFuse: proc(instructions: seq[Instruction], start: int): bool
    fuse: proc(instructions: seq[Instruction], start: int): Instruction

var fusion_patterns: seq[FusionPattern] = @[]

proc register_fusion(name: string, pattern: seq[InstructionKind], 
                    canFuse: proc(instructions: seq[Instruction], start: int): bool,
                    fuse: proc(instructions: seq[Instruction], start: int): Instruction) =
  fusion_patterns.add(FusionPattern(
    name: name,
    pattern: pattern,
    canFuse: canFuse,
    fuse: fuse
  ))

# Initialize fusion patterns
proc init_fusion_patterns*() =
  # Pattern: VarResolve + LtValue -> VarLtValue
  register_fusion("var_lt_value", @[IkVarResolve, IkLtValue],
    proc(instructions: seq[Instruction], start: int): bool = 
      instructions[start].arg0.kind == VkInt,
    proc(instructions: seq[Instruction], start: int): Instruction =
      Instruction(kind: IkVarLtValue, 
                 arg0: instructions[start + 1].arg0,  # value to compare
                 arg1: instructions[start].arg0.int64.int32)  # variable index
  )
  
  # Pattern: VarResolve + PushValue + Lt -> VarLtValue
  register_fusion("var_push_lt", @[IkVarResolve, IkPushValue, IkLt],
    proc(instructions: seq[Instruction], start: int): bool = 
      instructions[start].arg0.kind == VkInt,
    proc(instructions: seq[Instruction], start: int): Instruction =
      Instruction(kind: IkVarLtValue,
                 arg0: instructions[start + 1].arg0,  # value to compare
                 arg1: instructions[start].arg0.int64.int32)  # variable index
  )

# Apply instruction fusion to a compilation unit (modifies in place)
proc apply_fusion*(cu: CompilationUnit): CompilationUnit =
  # Return original if fusion is disabled or no instructions
  if not fusion_enabled or cu.instructions.len == 0:
    return cu
    
  if fusion_patterns.len == 0:
    init_fusion_patterns()
  
  # Build the fused instruction list
  var new_instructions: seq[Instruction] = @[]
  var i = 0
  
  while i < cu.instructions.len:
    var fused = false
    
    # Try to match fusion patterns
    for pattern in fusion_patterns:
      if i + pattern.pattern.len <= cu.instructions.len:
        # Check if pattern matches
        var matches = true
        for j, kind in pattern.pattern:
          if cu.instructions[i + j].kind != kind:
            matches = false
            break
        
        if matches and pattern.canFuse(cu.instructions, i):
          # Apply fusion
          new_instructions.add(pattern.fuse(cu.instructions, i))
          i += pattern.pattern.len
          fused = true
          break
    
    if not fused:
      # No fusion applied, keep original instruction
      new_instructions.add(cu.instructions[i])
      i += 1
  
  # Replace instructions in place
  cu.instructions = new_instructions
  
  # Update jump targets if needed
  # Note: For now, fusion patterns don't change instruction positions
  # so jump targets remain valid
  
  return cu

proc enable_fusion*() =
  fusion_enabled = true

proc disable_fusion*() =
  fusion_enabled = false