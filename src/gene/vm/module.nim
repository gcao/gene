import tables, strutils, os

import ../types
import ../parser
import ../compiler

type
  ImportItem* = object
    name*: string
    alias*: string
    children*: seq[string]  # For nested imports like n/[a b]

# Global module cache
var ModuleCache* = initTable[string, Namespace]()

proc parse_import_statement*(gene: ptr Gene): tuple[module_path: string, imports: seq[ImportItem]] =
  ## Parse import statement into module path and list of imports
  var module_path = ""
  var imports: seq[ImportItem] = @[]
  var i = 0
  
  while i < gene.children.len:
    let child = gene.children[i]
    
    if child.kind == VkSymbol and child.str == "from":
      # Handle "from module" syntax
      if i + 1 < gene.children.len and gene.children[i + 1].kind == VkString:
        module_path = gene.children[i + 1].str
        i += 2
        continue
      else:
        not_allowed("'from' must be followed by a string module path")
    
    # Parse import items
    case child.kind:
      of VkSymbol:
        var item = ImportItem(name: child.str)
        
        # Check for alias syntax (a:b)
        if i + 1 < gene.children.len and gene.children[i + 1].kind == VkGene:
          let alias_gene = gene.children[i + 1].gene
          if alias_gene.type.kind == VkSymbol and alias_gene.type.str == ":" and
             alias_gene.children.len == 1 and alias_gene.children[0].kind == VkSymbol:
            item.alias = alias_gene.children[0].str
            i += 1
        
        imports.add(item)
      
      of VkComplexSymbol:
        # Handle n/f or similar
        let parts = child.ref.csymbol
        if parts.len > 0:
          # Create import item with full path as name
          var item = ImportItem(name: parts.join("/"))
          
          # Check for alias
          if i + 1 < gene.children.len and gene.children[i + 1].kind == VkGene:
            let alias_gene = gene.children[i + 1].gene
            if alias_gene.type.kind == VkSymbol and alias_gene.type.str == ":" and
               alias_gene.children.len == 1 and alias_gene.children[0].kind == VkSymbol:
              item.alias = alias_gene.children[0].str
              i += 1
          
          imports.add(item)
      
      of VkGene:
        # Could be n/[a b] syntax or other complex forms
        let g = child.gene
        if g.type.kind == VkComplexSymbol:
          let parts = g.type.ref.csymbol
          if parts.len >= 2 and g.children.len > 0:
            # This is n/[a b] syntax
            let prefix = parts[0..^2].join("/")
            for sub_child in g.children:
              if sub_child.kind == VkSymbol:
                var item = ImportItem(name: prefix & "/" & sub_child.str)
                imports.add(item)
              elif sub_child.kind == VkGene:
                # Could be a:alias inside the brackets
                let sub_g = sub_child.gene
                if sub_g.type.kind == VkSymbol and sub_g.children.len == 1 and
                   sub_g.children[0].kind == VkSymbol:
                  var item = ImportItem(
                    name: prefix & "/" & sub_g.type.str,
                    alias: sub_g.children[0].str
                  )
                  imports.add(item)
        else:
          not_allowed("Invalid import syntax: " & $child)
      
      else:
        not_allowed("Invalid import item type: " & $child.kind)
    
    i += 1
  
  return (module_path, imports)

proc load_module*(vm: VirtualMachine, path: string): Namespace =
  ## Load a module from file and return its namespace
  # Check cache first
  if ModuleCache.hasKey(path):
    return ModuleCache[path]
  
  # Read module file
  var code: string
  try:
    code = readFile(path)
  except IOError as e:
    not_allowed("Failed to read module '" & path & "': " & e.msg)
  
  # Create namespace for module
  let module_ns = new_namespace(path)
  
  # For now, we'll just return an empty namespace
  # The actual module execution will need to be handled by the VM
  # when it processes import instructions
  
  # Cache the module
  ModuleCache[path] = module_ns
  
  return module_ns

proc resolve_import_value*(ns: Namespace, path: string): Value =
  ## Resolve a value from a namespace given a path like "n/f"
  let parts = path.split("/")
  var current_ns = ns
  var result = NIL
  
  for i, part in parts:
    let key = part.to_key()
    if not current_ns.members.hasKey(key):
      not_allowed("Symbol '" & part & "' not found in namespace")
    
    let value = current_ns.members[key]
    
    if i == parts.len - 1:
      # Last part - this is our result
      result = value
    else:
      # Intermediate part - must be a namespace
      if value.kind != VkNamespace:
        not_allowed("'" & part & "' is not a namespace")
      current_ns = value.ref.ns
  
  return result

proc handle_import*(vm: VirtualMachine, import_gene: ptr Gene) =
  ## Handle an import statement
  let (module_path, imports) = parse_import_statement(import_gene)
  
  if module_path == "":
    not_allowed("Module path not specified in import statement")
  
  # Load the module
  let module_ns = vm.load_module(module_path)
  
  # Import requested symbols
  for item in imports:
    let value = resolve_import_value(module_ns, item.name)
    
    # Determine the name to import as
    let import_name = if item.alias != "": 
      item.alias 
    else:
      # Use the last part of the path
      let parts = item.name.split("/")
      parts[^1]
    
    # Add to current namespace
    vm.frame.ns.members[import_name.to_key()] = value