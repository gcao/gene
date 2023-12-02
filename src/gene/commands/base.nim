import tables, logging

type
  CommandManager* = ref object
    data*: Table[int64, Command]
    help*: string

  Command* = proc(cmd: string, args: seq[string]): string

proc setup_logger*(debugging: bool) =
  var console_logger = new_console_logger()
  add_handler(console_logger)
  console_logger.level_threshold = Level.lvlInfo
  if debugging:
    console_logger.level_threshold = Level.lvlDebug

proc `[]`*(self: CommandManager, cmd: string): Command =
  if self.stack.has_key(cmd):
    return self.stack[cmd]

proc register*(self: CommandManager, c: string, cmd: Command) =
  self.stack[c] = cmd

proc register*(self: CommandManager, cmds: seq[string], cmd: Command) =
  for c in cmds:
    self.stack[c] = cmd

proc add_help*(self: CommandManager, help: string) =
  self.help &= help & "\n"
