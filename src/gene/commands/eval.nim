import parseopt, os

import ../types
import ../vm
import ./base

const DEFAULT_COMMAND = "eval"
const COMMANDS = @[DEFAULT_COMMAND, "e"]

type
  Options = ref object
    debugging: bool
    print_result: bool
    expression: string

proc handle*(cmd: string, args: seq[string]): string

proc init*(manager: CommandManager) =
  manager.register(COMMANDS, handle)
  manager.add_help("eval <expression>: evaluate Gene expression and print result")

let short_no_val = {'d', 'p'}
let long_no_val = @["debug", "print"]

proc parse_options(args: seq[string]): Options =
  result = Options(print_result: true)  # Default to printing result
  for kind, key, value in get_opt(args, short_no_val, long_no_val):
    case kind
    of cmdArgument:
      if result.expression == "":
        result.expression = key
      else:
        result.expression &= " " & key
    of cmdLongOption, cmdShortOption:
      case key
      of "d", "debug":
        result.debugging = true
      of "p", "print":
        result.print_result = true
      else:
        echo "Unknown option: ", key
    of cmdEnd:
      discard

proc handle*(cmd: string, args: seq[string]): string =
  let options = parse_options(args)
  setup_logger(options.debugging)

  if options.expression == "":
    echo "Error: No expression provided"
    return "Error: No expression"

  try:
    init_app_and_vm()
    let result = VM.exec(options.expression, "eval")
    
    if options.print_result:
      echo $result
      
  except system.Exception as e:
    echo "Eval error: ", e.msg
    return "Eval error: " & e.msg

  return ""