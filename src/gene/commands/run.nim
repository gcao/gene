import parseopt, times, strformat, terminal, os, strutils

import ../types
import ../vm
import ../parser
import ../compiler
import ./base

const DEFAULT_COMMAND = "run"
const COMMANDS = @[DEFAULT_COMMAND]

type
  Options = ref object
    benchmark: bool
    debugging: bool
    print_result: bool
    repl_on_error: bool
    trace: bool
    trace_instruction: bool
    compile: bool
    profile: bool
    file: string
    args: seq[string]

proc handle*(cmd: string, args: seq[string]): string

proc init*(manager: CommandManager) =
  manager.register(COMMANDS, handle)
  manager.add_help("run <file>: parse and execute <file>")

let short_no_val = {'d'}
let long_no_val = @[
  "repl-on-error",
  "trace",
  "trace-instruction",
  "compile",
  "profile",
]
proc parse_options(args: seq[string]): Options =
  result = Options()
  var found_file = false
  
  # Workaround: get_opt reads from command line when given empty args
  if args.len == 0:
    return
  
  for kind, key, value in get_opt(args, short_no_val, long_no_val):
    case kind
    of cmdArgument:
      if not found_file:
        found_file = true
        result.file = key
      result.args.add(key)
    of cmdLongOption, cmdShortOption:
      if found_file:
        result.args.add(key)
        if value != "":
          result.args.add(value)
      else:
        case key
        of "d", "debug":
          result.debugging = true
        of "repl-on-error":
          result.repl_on_error = true
        of "trace":
          result.trace = true
        of "trace-instruction":
          result.trace_instruction = true
        of "compile":
          result.compile = true
        of "profile":
          result.profile = true
        else:
          echo "Unknown option: ", key
          discard
    of cmdEnd:
      discard

proc handle*(cmd: string, args: seq[string]): string =
  let options = parse_options(args)
  setup_logger(options.debugging)

  # let thread_id = get_free_thread()
  # init_thread(thread_id)
  init_app_and_vm()
  # VM.thread_id = thread_id
  # VM.repl_on_error = options.repl_on_error
  # VM.app.args = options.args

  var file = options.file
  var code: string
  
  # Check if file is provided or read from stdin
  if file == "":
    # No file provided, try to read from stdin
    if not stdin.isatty():
      var lines: seq[string] = @[]
      var line: string
      while stdin.readLine(line):
        lines.add(line)
      if lines.len > 0:
        code = lines.join("\n")
        file = "<stdin>"
      else:
        return "Error: No input provided. Provide a file to run."
    else:
      return "Error: No file provided to run."
  else:
    # Read the file and execute it
    if not fileExists(file):
      return "Error: File not found: " & file
    code = readFile(file)
  
  let start = cpu_time()
  var value: Value
  
  # Initialize the VM if not already initialized
  init_app_and_vm()
  
  # Enable tracing if requested
  if options.trace:
    VM.trace = true
  
  # Enable profiling if requested
  if options.profile:
    VM.profiling = true
  
  if options.trace_instruction:
    # Show both compilation and execution with trace
    echo "=== Compilation Output ==="
    let compiled = compile(read_all(code))
    echo "Instructions:"
    for i, instr in compiled.instructions:
      echo fmt"{i:04X} {instr}"
    echo ""
    echo "=== Execution Trace ==="
    VM.trace = true
    # Initialize frame if needed
    if VM.frame == nil:
      VM.frame = new_frame(new_namespace(file))
    VM.cu = compiled
    value = VM.exec()
  elif options.compile or options.debugging:
    echo "=== Compilation Output ==="
    let compiled = compile(read_all(code))
    echo "Instructions:"
    for i, instr in compiled.instructions:
      echo fmt"{i:03d}: {instr}"
    echo ""
    
    if not options.trace:  # If not tracing, just show compilation
      VM.cu = compiled
      value = VM.exec()
    else:
      echo "=== Execution Trace ==="
      VM.cu = compiled
      value = VM.exec()
  else:
    value = VM.exec(code, file)
  
  if options.print_result:
    echo value
  if options.benchmark:
    echo "Time: " & $(cpu_time() - start)
  if options.profile:
    VM.print_profile()

when isMainModule:
  let cmd = DEFAULT_COMMAND
  let args: seq[string] = @[]
  let status = handle(cmd, args)
  if status.len > 0:
    echo "Failed with error: " & status
