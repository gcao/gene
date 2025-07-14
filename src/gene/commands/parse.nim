import parseopt, os

import ../types
import ../parser
import ./base

const DEFAULT_COMMAND = "parse"
const COMMANDS = @[DEFAULT_COMMAND]

type
  Options = ref object
    debugging: bool
    pretty: bool
    file: string

proc handle*(cmd: string, args: seq[string]): string

proc init*(manager: CommandManager) =
  manager.register(COMMANDS, handle)
  manager.add_help("parse <file|code>: parse Gene code and output AST")

let short_no_val = {'d', 'p'}
let long_no_val = @["debug", "pretty"]

proc parse_options(args: seq[string]): Options =
  result = Options(pretty: true)  # Default to pretty output
  var found_file = false
  for kind, key, value in get_opt(args, short_no_val, long_no_val):
    case kind
    of cmdArgument:
      if not found_file:
        found_file = true
        result.file = key
    of cmdLongOption, cmdShortOption:
      case key
      of "d", "debug":
        result.debugging = true
      of "p", "pretty":
        result.pretty = true
      else:
        echo "Unknown option: ", key
    of cmdEnd:
      discard

proc handle*(cmd: string, args: seq[string]): string =
  let options = parse_options(args)
  setup_logger(options.debugging)

  if options.file == "":
    echo "Error: No file or code provided"
    return "Error: No input"

  try:
    let content = if file_exists(options.file):
                    read_file(options.file)
                  else:
                    options.file  # Treat as direct code input

    let parsed = read_all(content)
    
    for ast_node in parsed:
      echo $ast_node
      
  except system.Exception as e:
    echo "Parse error: ", e.msg
    return "Parse error: " & e.msg

  return ""