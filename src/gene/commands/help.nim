import strutils, tables
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
  echo "  run <file>: parse and execute <file>"
  echo "  eval <code>: evaluate <code> as a gene expression"
  echo "  repl: start an interactive REPL"
  echo "  help: show this help message"
  echo ""
  echo "Additional help:"
  echo "  gene help <command> - Show detailed help for a specific command"
  echo "  gene <file.gene> - Run a Gene file directly"
  echo ""
  
  return ""

when isMainModule:
  let cmd = DEFAULT_COMMAND
  let args: seq[string] = @[]
  let status = handle(cmd, args)
  if status.len > 0:
    echo "Failed with error: " & status