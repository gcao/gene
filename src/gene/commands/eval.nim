import parseopt, strutils
import ../types
import ../vm
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
    code: string

proc handle*(cmd: string, args: seq[string]): string

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
]

proc parse_options(args: seq[string]): Options =
  result = Options()
  var code_parts: seq[string] = @[]
  
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
      else:
        echo "Unknown option: ", key
    of cmdEnd:
      discard
  
  result.code = code_parts.join(" ")

proc handle*(cmd: string, args: seq[string]): string =
  let options = parse_options(args)
  setup_logger(options.debugging)
  
  if options.code.len == 0:
    return "Error: no code provided to evaluate"
  
  init_app_and_vm()
  
  try:
    let value = VM.exec(options.code, "<eval>")
    
    if options.print_result or true:  # Always print result for eval
      if options.csv:
        # Basic CSV output - could be enhanced
        echo $value
      elif options.gene:
        # Output as gene expression format
        echo $value
      else:
        echo $value
        
  except ValueError as e:
    return "Error: " & e.msg

when isMainModule:
  let cmd = DEFAULT_COMMAND
  let args: seq[string] = @[]
  let status = handle(cmd, args)
  if status.len > 0:
    echo "Failed with error: " & status