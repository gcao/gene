import parseopt, strutils, strformat
import ../types
import ../vm
import ../compiler
import ./base

const DEFAULT_COMMAND = "eval"
const COMMANDS = @[DEFAULT_COMMAND, "e"]

type
  Options = ref object
    debugging: bool
    print_result: bool
    csv: bool
    gene: bool
    line: bool
    trace: bool
    trace_instruction: bool
    compile: bool
    code: string

proc handle*(cmd: string, args: seq[string]): CommandResult

proc init*(manager: CommandManager) =
  manager.register(COMMANDS, handle)
  manager.add_help("eval <code>: evaluate <code> as a gene expression")
  manager.add_help("  -d, --debug: enable debug output")
  manager.add_help("  --csv: print result as CSV")
  manager.add_help("  --gene: print result as gene expression")
  manager.add_help("  --line: evaluate as a single line")

let short_no_val = {'d'}
let long_no_val = @[
  "csv",
  "gene",
  "line",
  "trace",
  "trace-instruction",
  "compile",
]

proc parse_options(args: seq[string]): Options =
  result = Options()
  var code_parts: seq[string] = @[]
  
  # Workaround: get_opt reads from command line when given empty args
  if args.len == 0:
    return
  
  for kind, key, value in get_opt(args, short_no_val, long_no_val):
    case kind
    of cmdArgument:
      code_parts.add(key)
    of cmdLongOption, cmdShortOption:
      case key
      of "d", "debug":
        result.debugging = true
      of "csv":
        result.csv = true
      of "gene":
        result.gene = true
      of "line":
        result.line = true
      of "trace":
        result.trace = true
      of "trace-instruction":
        result.trace_instruction = true
      of "compile":
        result.compile = true
      else:
        echo "Unknown option: ", key
    of cmdEnd:
      discard
  
  result.code = code_parts.join(" ")

proc handle*(cmd: string, args: seq[string]): CommandResult =
  let options = parse_options(args)
  setup_logger(options.debugging)
  
  var code = options.code
  
  # If no code provided via arguments, read from stdin
  if code.len == 0:
    # Try to read from stdin regardless of TTY status
    var lines: seq[string] = @[]
    var line: string
    while read_line(stdin, line):
      lines.add(line)
    if lines.len > 0:
      code = lines.join("\n")
    else:
      return failure("No code provided to evaluate")
  
  if code.len == 0:
    return failure("No code provided to evaluate")
  
  init_app_and_vm()
  
  try:
    # Enable tracing if requested
    if options.trace:
      VM.trace = true
    
    # Handle trace-instruction option
    if options.trace_instruction:
      # Show both compilation and execution with trace
      let compiled = parse_and_compile(code)
      echo "=== Compilation Output ==="
      echo "Instructions:"
      for i, instr in compiled.instructions:
        echo fmt"{i:04X} {instr}"
      echo ""
      echo "=== Execution Trace ==="
      VM.trace = true
      # Initialize frame if needed
      if VM.frame == nil:
        VM.frame = new_frame(new_namespace("<eval>"))
      VM.cu = compiled
      let value = VM.exec()
      echo "=== Final Result ==="
      echo $value
    # Show compilation details if requested
    elif options.compile or options.debugging:
      let compiled = parse_and_compile(code)
      echo "=== Compilation Output ==="
      echo "Instructions:"
      for i, instr in compiled.instructions:
        echo fmt"{i:03d}: {instr}"
      echo ""
      
      if not options.trace:  # If not tracing, just show compilation
        VM.cu = compiled
        let value = VM.exec()
        echo "=== Result ==="
        echo $value
      else:
        echo "=== Execution Trace ==="
        VM.cu = compiled
        let value = VM.exec()
        echo "=== Final Result ==="
        echo $value
    else:
      let value = VM.exec(code, "<eval>")
      echo $value
        
  except ValueError as e:
    return failure(e.msg)
  
  return success()

when isMainModule:
  let cmd = DEFAULT_COMMAND
  let args: seq[string] = @[]
  let result = handle(cmd, args)
  if not result.success:
    echo "Failed with error: " & result.error