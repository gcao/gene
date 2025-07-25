import ../types

# Initialize async support
proc init_async*() =
  VmCreatedCallbacks.add proc() =
    # Ensure App is initialized
    if App == NIL or App.kind != VkApplication:
      return
    
    # Create Future class
    let future_class = new_class("Future")
    # Don't set parent yet - will be set later when object_class is available
    
    # Methods table is already initialized by new_class
    
    # Store in Application
    let future_class_ref = new_ref(VkClass)
    future_class_ref.class = future_class
    App.app.future_class = future_class_ref.to_ref_value()
    
    # Add to gene namespace if it exists
    if App.app.gene_ns.kind == VkNamespace:
      App.app.gene_ns.ref.ns["Future".to_key()] = App.app.future_class

# Call init_async to register the callback
init_async()