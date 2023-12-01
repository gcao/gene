import parseopt, times

import ../types
import ../vm
import ./base

const DEFAULT_COMMAND = "run"
const COMMANDS = @[DEFAULT_COMMAND]

type
  Options = ref object
    benchmark: bool
    debugging: bool
    print_result: bool
    repl_on_error: bool
    file: string
    args: seq[string]

proc handle*(cmd: string, args: seq[string]): string

proc init*(manager: CommandManager) =
  manager.register(COMMANDS, handle)
  manager.add_help("run <file>: parse and execute <file>")

let short_no_val = {'d'}
let long_no_val = @[
  "repl-on-error",
]
proc parse_options(args: seq[string]): Options =
  result = Options()
  var found_file = false
  for kind, key, value in get_opt(args, short_no_val, long_no_val):
    case kind
    of cmdArgument:
      if not found_file:
        found_file = true
        result.file = key
      result.args.add(key)
    of cmdLongOption, cmdShortOption:
      if found_file:
        result.args.add(key)
        if value != "":
          result.args.add(value)
      else:
        case key
        of "d", "debug":
          result.debugging = true
        of "repl-on-error":
          result.repl_on_error = true
        else:
          echo "Unknown option: ", key
          discard
    of cmdEnd:
      discard

proc handle*(cmd: string, args: seq[string]): string =
  var options = parse_options(args)
  setup_logger(options.debugging)

  # let thread_id = get_free_thread()
  # init_thread(thread_id)
  init_app_and_vm()
  # VM.thread_id = thread_id
  # VM.repl_on_error = options.repl_on_error
  # VM.app.args = options.args

  var file = options.file
  let start = cpu_time()
  var value: Value
  todo()
  # if file.ends_with(".gar"):
  #   value = run_archive_file(file)
  # else:
  #   value = run_file(file)
  # if options.print_result:
  #   echo value.to_s
  if options.benchmark:
    echo "Time: " & $(cpu_time() - start)

when isMainModule:
  var cmd = DEFAULT_COMMAND
  var args: seq[string] = @[]
  var status = handle(cmd, args)
  if status.len > 0:
    echo "Failed with error: " & status
