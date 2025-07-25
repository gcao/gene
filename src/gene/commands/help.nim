import ./base

const DEFAULT_COMMAND = "help"
const COMMANDS = @[DEFAULT_COMMAND, "h", "--help", "-h"]

proc handle*(cmd: string, args: seq[string]): string

proc init*(manager: CommandManager) =
  manager.register(COMMANDS, handle)
  manager.add_help("help [command]: show help for all commands or specific command")

proc handle*(cmd: string, args: seq[string]): string =
  echo "Gene Programming Language"
  echo "Usage: gene <command> [options] [args]"
  echo ""
  echo "Commands:"
  echo "  run      Execute a Gene file"
  echo "  eval     Evaluate Gene code"
  echo "  repl     Start interactive REPL"
  echo "  parse    Parse Gene code and output AST"
  echo "  compile  Compile Gene code and output bytecode"
  echo "  help     Show this help message"
  echo ""
  echo "Examples:"
  echo "  gene run script.gene    # Run a Gene file"
  echo "  gene eval '(+ 1 2)'     # Evaluate an expression"
  echo "  gene repl               # Start interactive mode"
  echo "  gene parse file.gene    # Parse and show AST"
  echo ""
  
  return ""

when isMainModule:
  let cmd = DEFAULT_COMMAND
  let args: seq[string] = @[]
  let status = handle(cmd, args)
  if status.len > 0:
    echo "Failed with error: " & status