import parseopt, os

import ../types
import ../parser
import ../compiler
import ./base

const DEFAULT_COMMAND = "compile"
const COMMANDS = @[DEFAULT_COMMAND]

type
  Options = ref object
    debugging: bool
    output_file: string
    pretty: bool
    file: string

proc handle*(cmd: string, args: seq[string]): string

proc init*(manager: CommandManager) =
  manager.register(COMMANDS, handle)
  manager.add_help("compile <file|code>: compile Gene code to bytecode")

let short_no_val = {'d', 'p'}
let long_no_val = @["debug", "pretty"]

proc parse_options(args: seq[string]): Options =
  result = Options(pretty: true)
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
      of "o", "output":
        if value != "":
          result.output_file = value
        else:
          echo "Error: --output requires a value"
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
                    options.file

    let parsed = read_all(content)
    let compilation_unit = compile(parsed)
    
    if options.output_file != "":
      # Write bytecode to file (would need serialization)
      echo "Writing to file not yet implemented"
    else:
      # Print compilation unit
      echo compilation_unit
      
  except system.Exception as e:
    echo "Compile error: ", e.msg
    return "Compile error: " & e.msg

  return ""