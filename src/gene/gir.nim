# Gene Intermediate Representation (GIR) serialization/deserialization
import streams, hashes, os, times, json, strutils
import ./types

const 
  GIR_MAGIC = "GENE"
  GIR_VERSION* = 1'u32
  COMPILER_VERSION = "0.1.0"
  
type
  GirHeader* = object
    magic*: array[4, char]
    version*: uint32
    compiler_version*: string
    vm_abi*: string
    timestamp*: int64
    debug*: bool
    published*: bool
    source_hash*: Hash
    
  GirFile* = object
    header*: GirHeader
    constants*: seq[Value]
    symbols*: seq[string]
    instructions*: seq[Instruction]
    metadata*: JsonNode

# Serialization helpers
proc writeString(stream: Stream, s: string) =
  stream.write(s.len.uint32)
  if s.len > 0:
    stream.write(s)

proc readString(stream: Stream): string =
  let len = stream.readUint32()
  if len > 0:
    result = newString(len)
    discard stream.readData(result[0].addr, len.int)

proc writeValue(stream: Stream, v: Value) =
  # Special handling for scope trackers - write NIL instead
  if v.kind == VkScopeTracker:
    stream.write(VkNil.uint16)
    return
  
  # Write value kind
  stream.write(v.kind.uint16)
  
  case v.kind:
  of VkNil, VkVoid, VkPlaceholder:
    # No data
    discard
  of VkBool:
    stream.write(if v == TRUE: 1'u8 else: 0'u8)
  of VkInt:
    stream.write(v.int64)
  of VkFloat:
    stream.write(v.float64)
  of VkString:
    stream.writeString(v.str)
  of VkSymbol:
    stream.writeString(v.str)
  of VkChar:
    stream.write(v.char.uint32)
  else:
    # Complex types stored as indices into constant pool
    # or serialized separately
    stream.write(cast[uint64](v))

proc readValue(stream: Stream): Value =
  let kind = cast[ValueKind](stream.readUint16())
  
  case kind:
  of VkNil:
    result = NIL
  of VkVoid:
    result = VOID
  of VkPlaceholder:
    result = PLACEHOLDER
  of VkBool:
    result = if stream.readUint8() == 1: TRUE else: FALSE
  of VkInt:
    result = stream.readInt64().to_value()
  of VkFloat:
    result = stream.readFloat64().to_value()
  of VkString:
    result = stream.readString().to_value()
  of VkSymbol:
    result = stream.readString().to_symbol_value()
  of VkChar:
    result = stream.readUint32().char.to_value()
  else:
    # Complex types - read raw value for now
    result = cast[Value](stream.readUint64())

proc writeInstruction(stream: Stream, inst: Instruction) =
  stream.write(inst.kind.uint16)
  stream.write(inst.label.uint32)
  stream.writeValue(inst.arg0)
  stream.write(inst.arg1)

proc readInstruction(stream: Stream): Instruction =
  result.kind = cast[InstructionKind](stream.readUint16())
  result.label = stream.readUint32().Label
  result.arg0 = stream.readValue()
  result.arg1 = stream.readInt32()

# Main serialization functions
proc saveGir*(cu: CompilationUnit, path: string, source_path: string = "", debug: bool = false) =
  ## Save a compilation unit to a GIR file
  let dir = path.parentDir()
  if dir != "" and not dirExists(dir):
    createDir(dir)
  
  var stream = newFileStream(path, fmWrite)
  if stream == nil:
    raise new_exception(types.Exception, "Failed to open file for writing: " & path)
  defer: stream.close()
  
  # Write header
  var header: GirHeader
  header.magic = ['G', 'E', 'N', 'E']
  header.version = GIR_VERSION
  header.compiler_version = COMPILER_VERSION
  header.vm_abi = "nim-" & NimVersion & "-" & $sizeof(pointer) & "bit"
  header.timestamp = 0'i64  # TODO: Fix epochTime conversion
  header.debug = debug
  header.published = false
  
  # Calculate source hash if provided
  if source_path != "" and fileExists(source_path):
    let source_content = readFile(source_path)
    header.source_hash = hash(source_content)
  
  # Write header fields
  stream.write(header.magic)
  stream.write(header.version)
  stream.writeString(header.compiler_version)
  stream.writeString(header.vm_abi)
  stream.write(header.timestamp)
  stream.write(header.debug)
  stream.write(header.published)
  stream.write(header.source_hash.int64)
  
  # Collect constants from instructions
  var constants: seq[Value] = @[]
  # Skip constant collection for now - causing issues
  # TODO: Fix constant pooling
  
  # Write constants
  stream.write(constants.len.uint32)
  for c in constants:
    stream.writeValue(c)
  
  # Write symbol table (for now empty - will be populated from global symbols)
  stream.write(0'u32)  # symbol count
  
  # Write instructions
  stream.write(cu.instructions.len.uint32)
  for inst in cu.instructions:
    stream.writeInstruction(inst)
  
  # Write metadata as simple values for now
  stream.writeString($cu.kind)
  stream.write(cast[int64](cu.id))
  stream.write(cu.skip_return)

proc loadGir*(path: string): CompilationUnit =
  ## Load a compilation unit from a GIR file
  if not fileExists(path):
    raise new_exception(types.Exception, "GIR file not found: " & path)
  
  var stream = newFileStream(path, fmRead)
  defer: stream.close()
  
  # Read and validate header
  var header: GirHeader
  discard stream.readData(header.magic[0].addr, 4)
  if header.magic != ['G', 'E', 'N', 'E']:
    raise new_exception(types.Exception, "Invalid GIR file: bad magic")
  
  header.version = stream.readUint32()
  if header.version != GIR_VERSION:
    raise new_exception(types.Exception, "Unsupported GIR version: " & $header.version)
  
  header.compiler_version = stream.readString()
  header.vm_abi = stream.readString()
  header.timestamp = stream.readInt64()
  header.debug = stream.readBool()
  header.published = stream.readBool()
  header.source_hash = stream.readInt64().Hash
  
  # Read constants
  let constant_count = stream.readUint32()
  var constants: seq[Value] = @[]
  for i in 0..<constant_count:
    constants.add(stream.readValue())
  
  # Read symbol table
  let symbol_count = stream.readUint32()
  var symbols: seq[string] = @[]
  for i in 0..<symbol_count:
    symbols.add(stream.readString())
  
  # Read instructions
  let instruction_count = stream.readUint32()
  result = new_compilation_unit()
  for i in 0..<instruction_count:
    result.instructions.add(stream.readInstruction())
  
  # Read metadata
  let kind_str = stream.readString()
  if kind_str != "":
    result.kind = parseEnum[CompilationUnitKind](kind_str)
  result.id = stream.readInt64().Id
  result.skip_return = stream.readBool()

proc isGirUpToDate*(gir_path: string, source_path: string): bool =
  ## Check if a GIR file is up-to-date with its source
  if not fileExists(gir_path):
    return false
  
  if not fileExists(source_path):
    return true  # No source to compare against
  
  # Check modification times
  let gir_info = getFileInfo(gir_path)
  let source_info = getFileInfo(source_path)
  
  if source_info.lastWriteTime > gir_info.lastWriteTime:
    return false
  
  # TODO: Check source hash from GIR header
  return true

proc getGirPath*(source_path: string, out_dir: string = "build"): string =
  ## Get the output path for a GIR file based on source path
  let (dir, name, _) = splitFile(source_path)
  let rel_dir = if dir.startsWith("/"): dir[1..^1] else: dir
  result = out_dir / rel_dir / name & ".gir"