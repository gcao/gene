import parseopt, strutils, os, terminal
import ../types
import ../parser
import ../compiler
import ./base

const DEFAULT_COMMAND = "compile"

type
  CompileOptions = object
    help: bool
    files: seq[string]
    code: string
    format: string  # "pretty" (default), "compact", "bytecode"
    show_addresses: bool

proc handle*(cmd: string, args: seq[string]): string

let short_no_val = {'h', 'a'}
let long_no_val = @[
  "help",
  "addresses",
]

let help_text = """
Usage: gene compile [options] [<file>...]

Compile Gene code and output the bytecode instructions.

Options:
  -h, --help              Show this help message
  -e, --eval <code>       Compile the given code string
  -f, --format <format>   Output format: pretty (default), compact, bytecode
  -a, --addresses         Show instruction addresses

Examples:
  gene compile file.gene                  # Compile and display instructions
  gene compile -e "(+ 1 2)"               # Compile a code string
  gene compile --format bytecode file.gene # Output raw bytecode format
  gene compile -a file.gene               # Show with addresses
"""

proc parseArgs(args: seq[string]): CompileOptions =
  result.format = "pretty"
  
  # Workaround: get_opt reads from command line when given empty args
  if args.len == 0:
    return
  
  for kind, key, value in get_opt(args, short_no_val, long_no_val):
    case kind
    of cmdArgument:
      result.files.add(key)
    of cmdLongOption, cmdShortOption:
      case key
      of "h", "help":
        result.help = true
      of "a", "addresses":
        result.show_addresses = true
      of "e", "eval":
        result.code = value
      of "f", "format":
        if value in ["pretty", "compact", "bytecode"]:
          result.format = value
        else:
          stderr.writeLine("Error: Invalid format '" & value & "'. Must be: pretty, compact, or bytecode")
          quit(1)
      else:
        stderr.writeLine("Error: Unknown option: " & key)
        quit(1)
    of cmdEnd:
      discard

proc formatInstruction(inst: Instruction, index: int, format: string, show_addresses: bool): string =
  case format
  of "bytecode":
    # Raw bytecode format
    result = $inst.kind
    case inst.kind
    of IkPushValue:
      result &= " " & $inst.arg0
    of IkJump, IkJumpIfFalse, IkJumpIfMatchSuccess:
      result &= " " & $inst.arg0.int64
    of IkSetMember, IkGetMember, IkGetMemberOrNil, IkGetMemberDefault:
      let key = inst.arg0.Key
      let symbol_value = cast[Value](key)
      let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
      result &= " " & get_symbol(symbol_index.int)
    of IkSetChild, IkGetChild:
      result &= " " & $inst.arg0.int64
    of IkCallInit:
      result &= " " & $inst.arg0
    else:
      if inst.arg0.kind != VkNil:
        result &= " " & $inst.arg0
      if inst.arg1.kind != VkNil:
        result &= " " & $inst.arg1
  of "compact":
    result = $inst
  else:  # "pretty"
    if show_addresses:
      result = "[" & index.toHex(4) & "] "
    else:
      result = "  "
    
    result &= ($inst.kind).alignLeft(20)
    
    # Add arguments based on instruction type
    case inst.kind
    of IkPushValue:
      result &= " " & $inst.arg0
    of IkJump, IkJumpIfFalse, IkJumpIfMatchSuccess:
      result &= " -> " & inst.arg0.int64.toHex(4)
    of IkSetMember, IkGetMember, IkGetMemberOrNil, IkGetMemberDefault:
      let key = inst.arg0.Key
      let symbol_value = cast[Value](key)
      let symbol_index = cast[uint64](symbol_value) and PAYLOAD_MASK
      result &= " ." & get_symbol(symbol_index.int)
    of IkSetChild, IkGetChild:
      result &= " [" & $inst.arg0.int64 & "]"
    of IkCallInit:
      result &= " <compiled unit>"
    of IkClass:
      if inst.arg0.kind == VkString:
        result &= " " & inst.arg0.str
    of IkNew:
      if inst.arg0.kind == VkInt:
        result &= " argc=" & $inst.arg0.int64
    of IkThrow:
      result &= " <exception>"
    of IkCallMethodNoArgs:
      result &= " ." & inst.arg0.str & "()"
    of IkCallerEval:
      result &= " frames_back=" & $inst.arg0.int64
    else:
      if inst.arg0.kind != VkNil:
        result &= " " & $inst.arg0
      if inst.arg1.kind != VkNil:
        result &= " " & $inst.arg1

proc handle*(cmd: string, args: seq[string]): string =
  let options = parseArgs(args)
  
  if options.help:
    echo help_text
    return ""
  
  var code: string
  var source_name: string
  
  if options.code != "":
    code = options.code
    source_name = "<eval>"
  elif options.files.len > 0:
    # Compile files
    for file in options.files:
      if not fileExists(file):
        stderr.writeLine("Error: File not found: " & file)
        quit(1)
      
      code = readFile(file)
      source_name = file
      
      echo "=== Compiling: " & source_name & " ==="
      
      try:
        let parsed = read_all(code)
        let compiled = compile(parsed)
        
        echo "Instructions (" & $compiled.instructions.len & "):"
        for i, inst in compiled.instructions:
          echo formatInstruction(inst, i, options.format, options.show_addresses)
        
        # TODO: Add matcher display when $ operator is available
        
        echo ""
      except ParseError as e:
        stderr.writeLine("Parse error in " & source_name & ": " & e.msg)
        quit(1)
      except CatchableError as e:
        stderr.writeLine("Compilation error in " & source_name & ": " & e.msg)
        quit(1)
    
    return ""
  else:
    # No code or files provided, try to read from stdin
    if not stdin.isatty():
      var lines: seq[string] = @[]
      var line: string
      while stdin.readLine(line):
        lines.add(line)
      if lines.len > 0:
        code = lines.join("\n")
        source_name = "<stdin>"
      else:
        stderr.writeLine("Error: No input provided. Use -e for code or provide a file.")
        quit(1)
    else:
      stderr.writeLine("Error: No input provided. Use -e for code or provide a file.")
      quit(1)
  
  # Compile single code string
  try:
    let parsed = read_all(code)
    let compiled = compile(parsed)
    
    echo "Instructions (" & $compiled.instructions.len & "):"
    for i, inst in compiled.instructions:
      echo formatInstruction(inst, i, options.format, options.show_addresses)
    
    # TODO: Add matcher display when $ operator is available
  except ParseError as e:
    stderr.writeLine("Parse error: " & e.msg)
    quit(1)
  except CatchableError as e:
    stderr.writeLine("Compilation error: " & e.msg)
    quit(1)
  
  return ""

proc init*(manager: CommandManager) =
  manager.register("compile", handle)
  manager.add_help("  compile  Compile Gene code and output bytecode")