import os, strutils, tables
import gene/commands/base
import gene/commands/[run, eval, repl, help, parse, compile]

var CommandMgr = CommandManager(data: initTable[string, Command](), help: "")

# Initialize all commands
run.init(CommandMgr)
eval.init(CommandMgr)
repl.init(CommandMgr)
help.init(CommandMgr)
parse.init(CommandMgr)
compile.init(CommandMgr)

proc main() =
  var args = command_line_params()
  
  if args.len == 0:
    # No arguments, show help
    discard CommandMgr["help"]("help", @[])
    return
  
  var cmd = args[0]
  var cmd_args = args[1 .. ^1]
  
  # Check if it's a known command
  if not CommandMgr.data.hasKey(cmd):
    echo "Error: Unknown command: ", cmd
    echo ""
    discard CommandMgr["help"]("help", @[])
    quit(1)
  
  # Execute the command
  let handler = CommandMgr[cmd]
  if handler.is_nil():
    echo "Error: Unknown command: ", cmd
    quit(1)
  
  let status = handler(cmd, cmd_args)
  if status.len > 0:
    echo status
    quit(1)

when isMainModule:
  main()
