# Gene IR (`.gir`) — Compile & Run

This document introduces a fast-start workflow for Gene by compiling source to a **Gene IR** file (`.gir`) and running it directly in the VM.

> TL;DR  
> - `gene compile x.gene` → writes `build/x.gir`  
> - `gene run x.gir` → runs precompiled IR directly (no parse/compile on startup)  
> - `gene run x.gene` → runs source; optionally uses a matching up‑to‑date `build/x.gir` cache

---

## Why `.gir`?

Compiling once and running many times reduces startup latency by skipping:
- Tokenization & parsing
- AST construction
- Compile-time symbol interning & constant folding

On typical scripts this yields 2–5× faster cold start (and often more on large programs).

---

## Commands

### `gene compile`
Compile a Gene source file (or files) to **GIR**.

```bash
gene compile x.gene
# => build/x.gir
```

**Rules & behavior**
- Output directory defaults to `build/` mirroring the input path layout.
- The compiler emits a versioned, relocatable GIR with constant pool & imports table.
- A content hash and dependency fingerprint are embedded for cache validation.

**Options**
```
-o, --out-dir <dir>     Override output directory (default: build/)
--force                 Rebuild even if cache is up-to-date
--emit-debug            Include line/column maps for better stack traces
--strip-debug           Remove debug info to shrink artifacts
--ir-version <N>        Target a specific IR version (defaults to current)
--no-color              Disable colored diagnostics
-q, --quiet             Reduce logging
-v, --verbose           Extra diagnostics
```

**Examples**
```bash
# Single file
gene compile src/app/main.gene            # build/src/app/main.gir

# Many files (shell globbing)
gene compile src/**/*.gene                # build/src/**.gir

# Custom output directory
gene compile -o out src/app/main.gene     # out/src/app/main.gir
```

---

### `gene run`
Run either **source** or **precompiled** Gene IR.

```bash
# Run a GIR directly (fastest path)
gene run build/x.gir

# Run from source (will parse/compile)
gene run x.gene
```

**Smart cache (optional default behavior):**
- If you run `gene run x.gene` and a **matching** `build/x.gir` exists that is **valid and newer** than `x.gene` and all tracked dependencies, the VM will **load the GIR** instead of recompiling.
- Pass `--no-gir-cache` to force running from source every time.

**Options**
```
--no-gir-cache          Ignore GIR cache even if valid
--trace                 Enable VM trace output
--profile               Enable VM function/instruction profiler
--args a b c            Positional args passed to the program
```

**Examples**
```bash
gene run build/x.gir
gene run x.gene -- --flag1 value
gene run --no-gir-cache x.gene
```

---

## File layout

```
myproj/
  src/
    x.gene
  build/
    x.gir           # produced by `gene compile src/x.gene`
```

With nested sources, the relative layout under `build/` mirrors `src/`:

```
src/app/main.gene  ->  build/src/app/main.gir
```

Use `-o out/` to customize:

```
gene compile -o out src/app/main.gene  ->  out/src/app/main.gir
```

---

## GIR validity & cache rules

A `.gir` is considered **valid** when:
- `ir_version` matches the VM’s supported range
- `compiler_version` / `vm_abi` fingerprint is compatible
- The embedded **source+deps hash** matches current inputs (or the `.gir` has a **publish** flag that opts out of cache checks)

If any check fails, the loader will refuse the artifact and (when invoked via `gene run x.gene`) fall back to recompilation.

**Flags embedded in `.gir`:**
- `ir_version` — bump on incompatible IR changes
- `compiler_version` — string or hash
- `vm_abi` — endianness, word-size, NaN-boxing schema, etc.
- `debug` — whether line/col maps are present
- `published` — treat as a release artifact; skip local source hash checks

---

## Safety & portability

- Never store raw host pointers in `.gir`. Use indices into a constant pool. The loader rebuilds boxed `Value`s.
- All integers/floats are serialized with a stable, little‑endian on-disk format (floats as IEEE‑754 bits; canonicalize NaNs).
- Imports (native functions, classes) are recorded by **symbolic name** and resolved at load‑time; signature mismatches cause a load error.
- Optional signing: you may require a valid signature to run external `.gir` files.

---

## Makefile / Script examples

```makefile
# Makefile
BUILD_DIR := build

SOURCES := $(shell find src -name '*.gene')
ARTIFACTS := $(patsubst %.gene,$(BUILD_DIR)/%.gir,$(SOURCES))

$(BUILD_DIR)/%.gir: %.gene
	@mkdir -p $(dir $@)
	gene compile -o $(BUILD_DIR) $<

build: $(ARTIFACTS)

run: $(BUILD_DIR)/src/app/main.gir
	gene run $<
```

```bash
# Simple build script
set -euo pipefail
for f in $(find src -name '*.gene'); do
  gene compile "$f" -o build
done
gene run build/src/app/main.gir
```

---

## Programmatic API (optional)

```nim
# Pseudocode / sketch
let cu = loadGIR("build/x.gir")       # fast load path
vm.run(cu, args=@["--flag1","value"]) # execute
```

---

## FAQ

**Q: Can I ship `.gir` without source?**  
A: Yes. Mark artifacts as `published` (or ship without source hashes). Imports are relinked on the target host. Include debug info if you want readable stack traces.

**Q: What happens if I change macros or natives?**  
A: If their names or ABI signatures change, the loader will refuse old `.gir` and ask for recompilation. If behavior changed but signatures didn’t, it’s treated like any other dependency change—use the dependency hash to invalidate the cache.

**Q: Is `.gir` stable forever?**  
A: It’s stable **per IR version**. We reserve the right to bump `ir_version` for breaking changes.

---

## Proposed CLI spec changes (summary)

- **New**: `gene compile <files...>` → writes `.gir` under `build/` (default) or `--out-dir`.
- **Updated**: `gene run` accepts both `*.gene` and `*.gir`.  
  When given `*.gene`, it **may** auto‑use a valid `build/*.gir` cache unless `--no-gir-cache` is set.

---

Happy fast‑starts! 🚀