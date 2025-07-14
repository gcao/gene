import parseopt, os, strutils

import ../types
import ../vm
import ./base

const DEFAULT_COMMAND = "repl"
const COMMANDS = @[DEFAULT_COMMAND, "i", "interactive"]

type
  Options = ref object
    debugging: bool
    load_file: string

proc handle*(cmd: string, args: seq[string]): string

proc init*(manager: CommandManager) =
  manager.register(COMMANDS, handle)
  manager.add_help("repl: start interactive Gene REPL")

let short_no_val = {'d'}
let long_no_val = @["debug", "load"]

proc parse_options(args: seq[string]): Options =
  result = Options()
  for kind, key, value in get_opt(args, short_no_val, long_no_val):
    case kind
    of cmdArgument:
      # Could support loading files as arguments
      discard
    of cmdLongOption, cmdShortOption:
      case key
      of "d", "debug":
        result.debugging = true
      of "load":
        result.load_file = value
      else:
        echo "Unknown option: ", key
    of cmdEnd:
      discard

proc print_banner() =
  echo "Gene Programming Language REPL"
  echo "Type 'exit' or 'quit' to exit, 'help' for help"
  echo "Use Ctrl+C to interrupt"

proc print_help() =
  echo """
Available commands:
  exit, quit - Exit the REPL
  help       - Show this help
  clear      - Clear variables (restart VM)
  
Enter any Gene expression to evaluate it.
"""

proc handle*(cmd: string, args: seq[string]): string =
  let options = parse_options(args)
  setup_logger(options.debugging)
  
  init_app_and_vm()
  
  # Load initial file if specified
  if options.load_file != "" and file_exists(options.load_file):
    try:
      let content = read_file(options.load_file)
      discard VM.exec(content, options.load_file)
      echo "Loaded: " & options.load_file
    except system.Exception as e:
      echo "Error loading file: ", e.msg

  print_banner()
  
  var line_number = 1
  var input = ""
  
  while true:
    try:
      let prompt = if input == "": "gene:" & $line_number & "> " else: "gene:" & $line_number & "| "
      stdout.write(prompt)
      stdout.flush_file()
      
      var line: string
      if not stdin.readLine(line):
        # EOF (Ctrl+D)
        echo "\nGoodbye!"
        break
        
      let trimmed = line.strip()
      
      # Handle special commands
      if input == "" and trimmed in ["exit", "quit"]:
        echo "Goodbye!"
        break
      elif input == "" and trimmed == "help":
        print_help()
        continue
      elif input == "" and trimmed == "clear":
        init_app_and_vm()
        echo "VM restarted"
        continue
      elif input == "" and trimmed == "":
        continue
      
      # Build multi-line input
      input &= line & "\n"
      
      # Try to parse and execute
      try:
        let result = VM.exec(input, "repl:" & $line_number)
        echo $result
        input = ""
        line_number += 1
      except system.Exception as e:
        let error_msg = e.msg
        # Check if it's a parse error that might be incomplete input
        if "unexpected end" in error_msg.to_lower() or "incomplete" in error_msg.to_lower():
          # Continue reading more input
          continue
        else:
          echo "Error: ", error_msg
          input = ""
          line_number += 1
          
    except:
      echo "\nInterrupted"
      input = ""
      continue

  return ""