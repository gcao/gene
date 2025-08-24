import ../types
import std/strformat

# Future methods
proc future_on_success(self: VirtualMachine, args: Value): Value =
  # Extract future and callback from args
  if args.kind != VkGene or args.gene.children.len < 2:
    raise new_exception(types.Exception, "Future.on_success requires 2 arguments (self and callback)")
  
  let future_arg = args.gene.children[0]
  let callback_arg = args.gene.children[1]
  
  if future_arg.kind != VkFuture:
    raise new_exception(types.Exception, "on_success can only be called on a Future")
  
  # Validate callback is callable
  if callback_arg.kind notin {VkFunction, VkNativeFn, VkBlock}:
    raise new_exception(types.Exception, "on_success callback must be a function or block")
  
  let future_obj = future_arg.ref.future
  
  # If future is already completed successfully, execute callback immediately
  if future_obj.state == FsSuccess:
    # TODO: Execute callback with value
    # For now, just store it
    future_obj.success_callbacks.add(callback_arg)
  elif future_obj.state == FsPending:
    # Store callback for later execution
    future_obj.success_callbacks.add(callback_arg)
  # If failed, don't add to success callbacks
  
  # Return the future for chaining
  return future_arg

proc future_on_failure(self: VirtualMachine, args: Value): Value =
  # Extract future and callback from args
  if args.kind != VkGene or args.gene.children.len < 2:
    raise new_exception(types.Exception, "Future.on_failure requires 2 arguments (self and callback)")
  
  let future_arg = args.gene.children[0]
  let callback_arg = args.gene.children[1]
  
  if future_arg.kind != VkFuture:
    raise new_exception(types.Exception, "on_failure can only be called on a Future")
  
  # Validate callback is callable
  if callback_arg.kind notin {VkFunction, VkNativeFn, VkBlock}:
    raise new_exception(types.Exception, "on_failure callback must be a function or block")
  
  let future_obj = future_arg.ref.future
  
  # If future is already failed, execute callback immediately
  if future_obj.state == FsFailure:
    # TODO: Execute callback with error
    # For now, just store it
    future_obj.failure_callbacks.add(callback_arg)
  elif future_obj.state == FsPending:
    # Store callback for later execution
    future_obj.failure_callbacks.add(callback_arg)
  # If succeeded, don't add to failure callbacks
  
  # Return the future for chaining
  return future_arg

proc future_state(self: VirtualMachine, args: Value): Value =
  # Get the state of a future
  # When called as a method, args contains the future as the first child
  if args.kind != VkGene:
    raise new_exception(types.Exception, fmt"Future.state expects Gene args, got {args.kind}")
  if args.gene.children.len == 0:
    raise new_exception(types.Exception, "Future.state requires a future object")
  
  let future_arg = args.gene.children[0]
  
  if future_arg.kind != VkFuture:
    raise new_exception(types.Exception, "state can only be called on a Future")
  
  let future_obj = future_arg.ref.future
  
  # Return state as a symbol
  case future_obj.state:
    of FsPending:
      return "pending".to_symbol_value()
    of FsSuccess:
      return "success".to_symbol_value()
    of FsFailure:
      return "failure".to_symbol_value()

proc future_value(self: VirtualMachine, args: Value): Value =
  # Get the value of a completed future
  # When called as a method, args contains the future as the first child
  if args.kind != VkGene or args.gene.children.len == 0:
    raise new_exception(types.Exception, "Future.value requires a future object")
  
  let future_arg = args.gene.children[0]
  
  if future_arg.kind != VkFuture:
    raise new_exception(types.Exception, "value can only be called on a Future")
  
  let future_obj = future_arg.ref.future
  
  # Return value if completed, NIL if pending
  if future_obj.state in {FsSuccess, FsFailure}:
    return future_obj.value
  else:
    return NIL

# Initialize async support
proc init_async*() =
  VmCreatedCallbacks.add proc() =
    # Ensure App is initialized
    if App == NIL or App.kind != VkApplication:
      return
    
    # Native function to complete a future
    proc complete_future_fn(self: VirtualMachine, args: Value): Value =
      # complete_future(future, value) - completes the given future with the value
      if args.kind != VkGene or args.gene.children.len != 2:
        raise new_exception(types.Exception, "complete_future requires exactly 2 arguments (future and value)")
      
      let future_arg = args.gene.children[0]
      let value_arg = args.gene.children[1]
      
      if future_arg.kind != VkFuture:
        raise new_exception(types.Exception, "First argument must be a Future")
      
      let future_obj = future_arg.ref.future
      future_obj.complete(value_arg)
      return NIL
    
    # Add to global namespace
    let complete_fn_ref = new_ref(VkNativeFn)
    complete_fn_ref.native_fn = complete_future_fn
    App.app.global_ns.ref.ns["complete_future".to_key()] = complete_fn_ref.to_ref_value()
    
    # Create Future class
    let future_class = new_class("Future")
    # Don't set parent yet - will be set later when object_class is available
    
    # Add Future constructor
    proc future_constructor(self: VirtualMachine, args: Value): Value =
      # Create a new Future instance
      let future_val = new_future_value()
      # If initial value is provided, complete the future immediately
      if args.kind == VkGene and args.gene.children.len > 0:
        let initial_value = args.gene.children[0]
        future_val.ref.future.complete(initial_value)
      return future_val
    
    future_class.def_native_constructor(future_constructor)
    
    # Add complete method  
    proc future_complete(self: VirtualMachine, args: Value): Value =
      # Complete the future with a value
      # When called as a method, args contains [future, value]
      if args.kind != VkGene:
        raise new_exception(types.Exception, fmt"Future.complete expects Gene args, got {args.kind}")
      if args.gene.children.len < 2:
        raise new_exception(types.Exception, "Future.complete requires a future and a value")
      
      let future_arg = args.gene.children[0]
      let value_arg = args.gene.children[1]
      
      if future_arg.kind != VkFuture:
        raise new_exception(types.Exception, "complete can only be called on a Future")
      
      let future_obj = future_arg.ref.future
      future_obj.complete(value_arg)
      return NIL
    
    # Add Future methods
    future_class.def_native_method("complete", future_complete)
    future_class.def_native_method("on_success", future_on_success)
    future_class.def_native_method("on_failure", future_on_failure)
    future_class.def_native_method("state", future_state)
    future_class.def_native_method("value", future_value)
    
    # Store in Application
    let future_class_ref = new_ref(VkClass)
    future_class_ref.class = future_class
    App.app.future_class = future_class_ref.to_ref_value()
    
    # Add to gene namespace if it exists
    if App.app.gene_ns.kind == VkNamespace:
      App.app.gene_ns.ref.ns["Future".to_key()] = App.app.future_class

# Call init_async to register the callback
init_async()