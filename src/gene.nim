import os, tables
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
    let result = CommandMgr.lookup("help")
    if result != nil:
      let helpResult = result("help", @[])
      if helpResult.output.len > 0:
        echo helpResult.output
    return
  
  var cmd = args[0]
  var cmd_args = args[1 .. ^1]
  
  # Use safe lookup
  let handler = CommandMgr.lookup(cmd)
  if handler.isNil:
    echo "Error: Unknown command: ", cmd
    echo ""
    let helpHandler = CommandMgr.lookup("help")
    if helpHandler != nil:
      let helpResult = helpHandler("help", @[])
      if helpResult.output.len > 0:
        echo helpResult.output
    quit(1)
  
  # Execute the command
  let result = handler(cmd, cmd_args)
  if not result.success:
    if result.error.len > 0:
      echo "Error: ", result.error
    quit(1)
  elif result.output.len > 0:
    echo result.output

when isMainModule:
  main()
