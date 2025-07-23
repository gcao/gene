import ../types
import tables
import sets

proc process_args*(matcher: RootMatcher, args: Value, scope: Scope) =
  ## Process function arguments and bind them to the scope
  ## Handles both positional and named arguments
  
  
  # Ensure scope.members has enough slots for all parameters
  for i, param in matcher.children:
    scope.members.add(NIL)
  
  if args.kind != VkGene:
    # No arguments provided, use defaults where available
    for i, param in matcher.children:
      if param.default_value.kind != VkNil:
        scope.members[i] = param.default_value
    return
  
  let positional = args.gene.children
  let named = args.gene.props
  
  # First pass: bind named arguments
  var used_indices = initHashSet[int]()
  for i, param in matcher.children:
    if param.is_prop and named.hasKey(param.name_key):
      # Named argument provided
      scope.members[i] = named[param.name_key]
      used_indices.incl(i)
  
  # Second pass: bind positional arguments
  var pos_index = 0
  for i, param in matcher.children:
    if i notin used_indices and pos_index < positional.len:
      # Fill in positional argument
      scope.members[i] = positional[pos_index]
      pos_index.inc()
    elif i notin used_indices and param.default_value.kind != VkNil:
      # Use default value
      scope.members[i] = param.default_value
    elif i notin used_indices:
      # No value provided and no default - keep as NIL
      discard
  
