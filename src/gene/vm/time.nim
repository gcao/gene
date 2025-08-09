# Time module for Gene VM
import times
import ../types

proc init_time_ns*(): Namespace =
  result = new_namespace("time")
  
  # Add time/now function
  result["now".to_key()] = new_native_fn("now", proc(vm_data: pointer, args: Value): Value =
    # Return current time as a float (seconds since epoch)
    let now = epochTime()
    return now.to_value()
  )
  
  # Add time/sleep function  
  result["sleep".to_key()] = new_native_fn("sleep", proc(vm_data: pointer, args: Value): Value =
    if args.kind != VkGene or args.gene.children.len < 2:
      raise new_exception(types.Exception, "sleep requires 1 argument")
    
    let duration = args.gene.children[1]
    case duration.kind:
      of VkInt:
        sleep(duration.int64.int * 1000)  # Convert seconds to milliseconds
      of VkFloat:
        sleep((duration.float64 * 1000).int)  # Convert seconds to milliseconds
      else:
        raise new_exception(types.Exception, "sleep requires a number")
    
    return NIL
  )