# Async/Await Implementation Design for Gene VM

## Overview

After analyzing the reference implementation in gene-new, this document outlines the design for implementing async/await functionality in our stack-based VM.

## Reference Implementation Analysis

### Key Components in gene-new

1. **Future Type** (`VkFuture`)
   - Wraps Nim's `Future[Value]` from asyncdispatch
   - States: pending, success, failure
   - Supports callbacks via `on_success` and `on_failure`

2. **async operator**
   - Creates a Future that wraps the execution result
   - If expression throws, Future fails with the exception
   - Returns immediately with a Future object

3. **await operator**
   - Blocks until Future completes
   - Polls async operations every 2ms (AWAIT_INTERVAL)
   - Returns the Future's value or re-throws exception

4. **Async function attribute (`^^async`)**
   - Functions marked with `^^async` automatically wrap their return value in a Future

5. **$await_all operator**
   - Waits for all pending futures in the VM

## VM Architecture Design

### 1. Future Type Implementation

```nim
# In types.nim
type
  FutureState* = enum
    FsPending
    FsSuccess
    FsFailure
    
  FutureObj* = ref object
    state*: FutureState
    value*: Value              # Result value or exception
    success_callbacks*: seq[Value]  # Success callback functions
    failure_callbacks*: seq[Value]  # Failure callback functions
    
  # Add to Value:
  # VkFuture with future: FutureObj field
```

### 2. VM Instructions

New instructions needed:
- `IkAsync`: Wrap expression result in a Future
- `IkAwait`: Block until Future completes
- `IkCheckFutures`: Check and execute ready Future callbacks

### 3. Implementation Strategy

#### Phase 1: Basic Future Support
1. Add Future type to types.nim ✓
2. Implement Future class with methods:
   - `new gene/Future` constructor
   - `.complete(value)` - complete with success
   - `.fail(exception)` - complete with failure
   - `.on_success(callback)` - register success callback
   - `.on_failure(callback)` - register failure callback

#### Phase 2: async/await Operators
1. Implement `async` compilation:
   ```gene
   (async expr) → 
   compile expr
   IkAsync
   ```
   
2. Implement `await` compilation:
   ```gene
   (await future) →
   compile future
   IkAwait
   ```

#### Phase 3: Callback Execution
1. Add future tracking to VM:
   - List of pending futures
   - Periodic callback check mechanism
   
2. Implement callback execution:
   - When future completes, execute registered callbacks
   - Callbacks run in new frames with future value as argument

#### Phase 4: Async Functions
1. Support `^^async` function attribute
2. Automatically wrap return values in Futures

### 4. Key Design Decisions

1. **No Real OS Async (Initially)**
   - Start with "pseudo futures" that complete synchronously
   - Later can integrate with Nim's asyncdispatch for real async ops

2. **Callback Execution Timing**
   - Check futures after every N instructions (e.g., 10)
   - Or check during IkAwait when blocking

3. **Exception Handling**
   - async captures exceptions and stores in Future
   - await re-throws exceptions from failed Futures

4. **Memory Management**
   - Futures are ref objects, handled by Nim's GC
   - Callbacks stored as Value objects (functions)

### 5. Implementation Steps

1. **Add Future type and basic methods** ✓
2. **Add IkAsync instruction**
   - Compile async expressions
   - VM handler wraps result in Future
3. **Add IkAwait instruction**
   - Compile await expressions
   - VM handler blocks until Future ready
4. **Implement callback system**
   - Store callbacks in FutureObj
   - Execute when Future completes
5. **Add future checking mechanism**
   - Track pending futures in VM
   - Check periodically or on await

### 6. Example Flow

```gene
(var future (async (+ 1 2)))  ; Creates Future with value 3
(future .on_success (x -> (println x)))  ; Register callback
(await future)  ; Returns 3, callback already executed
```

VM execution:
1. `(+ 1 2)` evaluates to 3
2. `IkAsync` creates Future(state=FsSuccess, value=3)
3. `.on_success` adds callback to future
4. Since future is already complete, callback executes immediately
5. `IkAwait` returns 3 immediately since future is complete

### 7. Testing Strategy

Enable tests progressively:
1. Basic Future creation and completion
2. Simple async/await
3. Callbacks (on_success, on_failure)
4. Exception handling in async
5. Async functions
6. Multiple futures with await_all

### 8. Current Implementation Status

#### Completed:
- ✅ Basic Future type (VkFuture, FutureObj)
- ✅ IkAsync instruction - wraps values in futures
- ✅ IkAwait instruction - waits for future completion
- ✅ Basic async/await compilation
- ✅ Future class initialization
- ✅ get_class support for VkFuture

#### Issues Found:
1. **Exception Handling in Async**: When `(async (throw))` is executed, the exception escapes instead of being captured in the future
   - Need to wrap the async body execution in exception handling
   - Store exceptions in the future instead of propagating them

2. **Method Calls on Futures**: `.on_success`, `.complete` etc. don't work yet
   - Need to implement the Future constructor and methods

3. **^^async Function Attribute**: Not implemented
   - Functions marked with ^^async should wrap their return values in futures

### 9. Future Enhancements

1. **Real Async Operations**
   - Integrate with asyncdispatch for sleep_async, etc.
   - Implement proper event loop integration

2. **Advanced Features**
   - Future chaining/composition
   - Timeout support
   - Cancellation
   - Progress reporting

## Questions

1. **Instruction Execution Model**: Should we check futures after every instruction or only at specific points?
   - **Decision**: Check at specific points (await, explicit check instruction) to minimize overhead

2. **Callback Frame Context**: What frame/scope should callbacks execute in?
   - **Decision**: New frame with captured context from callback creation time

3. **Future Tracking**: Should VM maintain global list of pending futures?
   - **Decision**: Yes, for $await_all and periodic checking

4. **Integration with Nim Async**: Should we use Nim's Future[Value] internally?
   - **Decision**: Start with custom FutureObj, consider Nim integration later