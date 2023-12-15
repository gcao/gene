import tables, strutils, strformat

import ./types
import ./parser
import ./compiler

proc handle_args*(self: VirtualMachine, matcher: RootMatcher, args: Value) {.inline.} =
  case matcher.hint_mode:
    of MhNone:
      discard
    of MhSimpleData:
      for i, value in args.gene.children:
        {.push checks: off}
        let field = matcher.children[i]
        {.pop.}
        self.frame.match_result.fields.add(MfSuccess)
        self.frame.scope.def_member(field.name_key, value)
      if args.gene.children.len < matcher.children.len:
        for i in args.gene.children.len..matcher.children.len-1:
          self.frame.match_result.fields.add(MfMissing)
    else:
      todo($matcher.hint_mode)

# proc print_stack(self: VirtualMachine) =
#   var s = "Stack: "
#   for i, reg in self.frame.stack:
#     if i > 0:
#       s &= ", "
#     if i == self.frame.stack_index.int:
#       s &= "=> "
#     s &= $self.frame.stack[i]
#   echo s

proc exec*(self: VirtualMachine): Value =
  self.state = VmRunning
  var indent = ""

  var frame = self.frame
  while true:
    {.push checks: off}
    let inst = self.cur_block.instructions[self.pc].addr
    {.pop.}
    if self.trace:
      if inst.kind == IkStart: # This is part of INDENT_LOGIC
        indent &= "  "
      # self.print_stack()
      echo fmt"{indent}{self.pc:03} {inst[]}"
    case inst.kind:
      of IkNoop:
        discard

      of IkStart:
        if not self.trace: # This is part of INDENT_LOGIC
          indent &= "  "
        if self.cur_block.matcher != nil:
          self.handle_args(self.cur_block.matcher, frame.args)

      of IkEnd:
        indent.delete(indent.len-2..indent.len-1)
        let v = frame.default
        let caller = frame.caller
        if caller == nil:
          return v
        else:
          update(self.frame, frame, caller.frame)
          if not self.cur_block.skip_return:
            frame.push(v)
          self.cur_block = self.code_mgr.data[caller.address.id]
          self.pc = caller.address.pc
          continue

      of IkVar:
        frame.scope.def_member(inst.arg0.Key, frame.current())

      of IkAssign:
        let value = frame.current()
        frame.scope[inst.arg0.Key] = value

      of IkResolveSymbol:
        case inst.arg0.int64:
          of SYM_UNDERSCORE:
            frame.push(PLACEHOLDER)
          of SYM_SELF:
            frame.push(frame.self)
          of SYM_GENE:
            frame.push(App.app.gene_ns)
          else:
            let scope = frame.scope
            let name = inst.arg0.Key
            if scope.has_key(name):
              frame.push(scope[name])
            elif frame.ns.has_key(name):
              frame.push(frame.ns[name])
            else:
              not_allowed("Unknown symbol " & name.int.get_symbol())

      of IkSelf:
        frame.push(frame.self)

      of IkSetMember:
        let name = inst.arg0.Key
        var value: Value
        frame.pop2(value)
        var target: Value
        frame.pop2(target)
        case target.kind:
          of VkMap:
            target.ref.map[name] = value
          of VkGene:
            target.gene.props[name] = value
          of VkNamespace:
            target.ref.ns[name] = value
          of VkClass:
            target.ref.class.ns[name] = value
          of VkInstance:
            target.ref.instance_props[name] = value
          else:
            todo($target.kind)
        frame.push(value)

      of IkGetMember:
        let name = inst.arg0.Key
        var value: Value
        frame.pop2(value)
        case value.kind:
          of VkMap:
            frame.push(value.ref.map[name])
          of VkGene:
            frame.push(value.gene.props[name])
          of VkNamespace:
            frame.push(value.ref.ns[name])
          of VkClass:
            frame.push(value.ref.class.ns[name])
          of VkInstance:
            frame.push(value.ref.instance_props[name])
          else:
            todo($value.kind)

      of IkGetChild:
        let i = inst.arg0.int
        var value: Value
        frame.pop2(value)
        case value.kind:
          of VkArray:
            frame.push(value.ref.arr[i])
          of VkGene:
            frame.push(value.gene.children[i])
          else:
            todo($value.kind)

      of IkJump:
        self.pc = inst.arg0.int
        continue
      of IkJumpIfFalse:
        var value: Value
        frame.pop2(value)
        if not value.to_bool():
          self.pc = inst.arg0.int
          continue

      of IkJumpIfMatchSuccess:
        if frame.match_result.fields[inst.arg0.int64] == MfSuccess:
          self.pc = inst.arg1.int
          continue

      of IkLoopStart, IkLoopEnd:
        discard

      of IkContinue:
        self.pc = self.cur_block.find_loop_start(self.pc)
        continue

      of IkBreak:
        self.pc = self.cur_block.find_loop_end(self.pc)
        continue

      of IkPushValue:
        frame.push(inst.arg0)
      of IkPushNil:
        frame.push(NIL)
      of IkPop:
        discard frame.pop()

      of IkArrayStart:
        frame.push(new_array_value())
      of IkArrayAddChild:
        var child: Value
        frame.pop2(child)
        frame.current().ref.arr.add(child)
      of IkArrayEnd:
        discard

      of IkMapStart:
        frame.push(new_map_value())
      of IkMapSetProp:
        let key = inst.arg0.Key
        var value: Value
        frame.pop2(value)
        frame.current().ref.map[key] = value
      of IkMapEnd:
        discard

      of IkGeneStart:
        frame.push(new_gene_value())

      of IkGeneStartDefault:
        var v: Value
        frame.pop2(v)
        frame.push(new_gene_value(v))
        case inst.arg1.int:
          of 1:   # Fn
            case v.kind:
              of VkFunction, VkNativeFn, VkNativeFn2:
                self.pc = inst.arg0.int
                continue
              of VkMacro:
                not_allowed("Macro not allowed here")
              of VkBoundMethod:
                if v.ref.bound_method.method.is_macro:
                  not_allowed("Macro not allowed here")
                else:
                  self.pc = inst.arg0.int
                  continue
              else:
                todo($v.kind)

          of 2:   # Macro
            case v.kind:
              of VkFunction, VkNativeFn, VkNativeFn2:
                not_allowed("Macro expected here")
              of VkMacro:
                discard
              of VkBoundMethod:
                if v.ref.bound_method.method.is_macro:
                  discard
                else:
                  not_allowed("Macro expected here")
              else:
                todo($v.kind)

          else:   # Not sure
            case v.kind:
              of VkFunction, VkNativeFn, VkNativeFn2:
                inst.arg1 = 1.Value
                self.pc = inst.arg0.int
                continue
              of VkMacro:
                inst.arg1 = 2.Value
              of VkBoundMethod:
                if v.ref.bound_method.method.is_macro:
                  inst.arg1 = 2.Value
                else:
                  inst.arg1 = 1.Value
                  self.pc = inst.arg0.int
                  continue
              else:
                todo($v.kind)

      of IkGeneSetType:
        var value: Value
        frame.pop2(value)
        frame.current().gene.type = value
      of IkGeneSetProp:
        let key = inst.arg0.Key
        var value: Value
        frame.pop2(value)
        frame.current().gene.props[key] = value
      of IkGeneAddChild:
        var child: Value
        frame.pop2(child)
        frame.current().gene.children.add(child)

      of IkGeneEnd:
        let v = frame.current()
        let gene_type = v.gene.type
        if gene_type != nil:
          case gene_type.kind:
            of VkFunction:
              self.pc.inc()
              discard frame.pop()

              gene_type.ref.fn.compile()
              self.code_mgr.data[gene_type.ref.fn.body_compiled.id] = gene_type.ref.fn.body_compiled

              let caller = Caller(
                address: Address(id: self.cur_block.id, pc: self.pc),
              )
              caller.frame.update(frame)
              update(self.frame, frame, new_frame(caller))
              frame.scope.set_parent(gene_type.ref.fn.parent_scope, gene_type.ref.fn.parent_scope_max)
              frame.ns = gene_type.ref.fn.ns
              frame.args = v
              self.cur_block = gene_type.ref.fn.body_compiled
              self.pc = 0
              continue

            of VkMacro:
              self.pc.inc()
              discard frame.pop()

              gene_type.ref.macro.compile()
              self.code_mgr.data[gene_type.ref.macro.body_compiled.id] = gene_type.ref.macro.body_compiled

              let caller = Caller(
                address: Address(id: self.cur_block.id, pc: self.pc),
              )
              caller.frame.update(frame)
              update(self.frame, frame, new_frame(caller))
              frame.scope.set_parent(gene_type.ref.macro.parent_scope, gene_type.ref.macro.parent_scope_max)
              frame.ns = gene_type.ref.macro.ns
              frame.args = v
              self.cur_block = gene_type.ref.macro.body_compiled
              self.pc = 0
              continue

            of VkClass:
              todo($v)

            of VkBoundMethod:
              discard frame.pop()

              let meth = gene_type.ref.bound_method.method
              case meth.callable.kind:
                of VkNativeFn:
                  frame.push(meth.callable.ref.native_fn(self, v))
                of VkFunction:
                  self.pc.inc()

                  let fn = meth.callable.ref.fn
                  fn.compile()
                  self.code_mgr.data[fn.body_compiled.id] = fn.body_compiled

                  let caller = Caller(
                    address: Address(id: self.cur_block.id, pc: self.pc),
                  )
                  caller.frame.update(frame)
                  update(self.frame, frame, new_frame(caller))
                  frame.scope.set_parent(fn.parent_scope, fn.parent_scope_max)
                  frame.ns = fn.ns
                  frame.self = gene_type.ref.bound_method.self
                  frame.args = v
                  self.cur_block = fn.body_compiled
                  self.pc = 0
                  continue
                else:
                  todo("Bound method: " & $meth.callable.kind)

            else:
              discard

      of IkAdd:
        var second: Value
        frame.pop2(second)
        frame.replace(frame.current().int + second.int)

      of IkSub:
        var second: Value
        frame.pop2(second)
        frame.replace(frame.current().int - second.int)
      of IkSubValue:
        frame.replace(frame.current().int - inst.arg0.int)

      of IkMul:
        frame.push(frame.pop().int * frame.pop().int)

      of IkDiv:
        let second = frame.pop().int
        let first = frame.pop().int
        frame.push(first / second)

      of IkLt:
        var second: Value
        frame.pop2(second)
        frame.replace(frame.current().int < second.int)
      of IkLtValue:
        var first: Value
        frame.pop2(first)
        frame.push(first.int < inst.arg0.int)

      of IkLe:
        let second = frame.pop().int
        let first = frame.pop().int
        frame.push(first <= second)

      of IkGt:
        let second = frame.pop().int
        let first = frame.pop().int
        frame.push(first > second)

      of IkGe:
        let second = frame.pop().int
        let first = frame.pop().int
        frame.push(first >= second)

      of IkEq:
        let second = frame.pop().int
        let first = frame.pop().int
        frame.push(first == second)

      of IkNe:
        let second = frame.pop().int
        let first = frame.pop().int
        frame.push(first != second)

      of IkAnd:
        let second = frame.pop()
        let first = frame.pop()
        frame.push(first.to_bool and second.to_bool)

      of IkOr:
        let second = frame.pop()
        let first = frame.pop()
        frame.push(first.to_bool or second.to_bool)

      of IkCompileInit:
        let input = frame.pop()
        let compiled = compile_init(input)
        self.code_mgr.data[compiled.id] = compiled
        frame.push(compiled.id.Value)

      of IkCallInit:
        let id = frame.pop().Id
        let compiled = self.code_mgr.data[id]
        let obj = frame.current()
        var ns: Namespace
        case obj.kind:
          of VkNamespace:
            ns = obj.ref.ns
          of VkClass:
            ns = obj.ref.class.ns
          else:
            todo($obj.kind)

        self.pc.inc()
        let caller = Caller(
          address: Address(id: self.cur_block.id, pc: self.pc),
        )
        caller.frame.update(frame)
        update(self.frame, frame, new_frame(caller))
        frame.self = obj
        frame.ns = ns
        self.cur_block = compiled
        self.pc = 0
        continue

      of IkFunction:
        let f = to_function(inst.arg0)
        f.ns = frame.ns
        let r = new_ref(VkFunction)
        r.fn = f
        let v = r.to_ref_value()
        f.ns[f.name.to_key()] = v
        f.parent_scope.update(frame.scope)
        f.parent_scope_max = frame.scope.max
        frame.push(v)

      of IkMacro:
        let m = to_macro(inst.arg0)
        m.ns = frame.ns
        let r = new_ref(VkMacro)
        r.macro = m
        let v = r.to_ref_value()
        m.ns[m.name.to_key()] = v
        frame.push(v)

      of IkReturn:
        let caller = frame.caller
        if caller == nil:
          not_allowed("Return from top level")
        else:
          let v = frame.pop()
          update(self.frame, frame, caller.frame)
          self.cur_block = self.code_mgr.data[caller.address.id]
          self.pc = caller.address.pc
          frame.push(v)
          continue

      of IkNamespace:
        let name = inst.arg0
        let ns = new_namespace(name.str)
        let r = new_ref(VkNamespace)
        r.ns = ns
        let v = r.to_ref_value()
        frame.ns[name.Key] = v
        frame.push(v)

      of IkClass:
        let name = inst.arg0
        let class = new_class(name.str)
        let r = new_ref(VkClass)
        r.class = class
        let v = r.to_ref_value()
        frame.ns[name.Key] = v
        frame.push(v)

      of IkNew:
        let v = frame.pop()
        let instance = new_ref(VkInstance)
        instance.instance_class = v.gene.type.ref.class
        frame.push(instance.to_ref_value())

        let class = instance.instance_class
        case class.constructor.kind:
          of VkFunction:
            class.constructor.ref.fn.compile()
            let compiled = class.constructor.ref.fn.body_compiled
            compiled.skip_return = true

            self.pc.inc()
            let caller = Caller(
              address: Address(id: self.cur_block.id, pc: self.pc),
            )
            caller.frame.update(frame)
            update(self.frame, frame, new_frame(caller))
            frame.self = instance.to_ref_value()
            frame.ns = class.constructor.ref.fn.ns
            self.cur_block = compiled
            self.pc = 0
            continue
          of VkNil:
            discard
          else:
            todo($class.constructor.kind)

      of IkSubClass:
        let name = inst.arg0
        let class = new_class(name.str)
        class.parent = frame.pop().ref.class
        let r = new_ref(VkClass)
        r.class = class
        frame.ns[name.Key] = r.to_ref_value()
        frame.push(r.to_ref_value())

      of IkResolveMethod:
        let v = frame.pop()
        let class = v.get_class()
        let meth = class.get_method(inst.arg0.str)
        let r = new_ref(VkBoundMethod)
        r.bound_method = BoundMethod(
          self: v,
          # class: class,
          `method`: meth,
        )
        frame.push(r.to_ref_value())

      of IkCallMethodNoArgs:
        let v = frame.pop()

        let class = v.get_class()
        let meth = class.get_method(inst.arg0.str)
        case meth.callable.kind:
          of VkNativeFn:
            frame.push(meth.callable.ref.native_fn(self, v))
          of VkFunction:
            self.pc.inc()

            let fn = meth.callable.ref.fn
            fn.compile()
            self.code_mgr.data[fn.body_compiled.id] = fn.body_compiled

            let caller = Caller(
              address: Address(id: self.cur_block.id, pc: self.pc),
            )
            caller.frame.update(frame)
            update(self.frame, frame, new_frame(caller))
            frame.scope.set_parent(fn.parent_scope, fn.parent_scope_max)
            frame.ns = fn.ns
            frame.self = v
            self.cur_block = fn.body_compiled
            self.pc = 0
            continue
          else:
            todo("CallMethodNoArgs: " & $meth.callable.kind)

      # of IkInternal:
      #   case inst.arg0.str:
      #     of "$_trace_start":
      #       self.trace = true
      #       frame.push(NIL)
      #     of "$_trace_end":
      #       self.trace = false
      #       frame.push(NIL)
      #     of "$_debug":
      #       if inst.arg1:
      #         echo "$_debug ", frame.current()
      #       else:
      #         frame.push(NIL)
      #     of "$_print_instructions":
      #       echo self.cur_block
      #       if inst.arg1:
      #         discard frame.pop()
      #       frame.push(NIL)
      #     of "$_print_stack":
      #       self.print_stack()
      #       frame.push(NIL)
      #     else:
      #       todo(inst.arg0.str)

      else:
        todo($inst.kind)

    self.pc.inc
    if self.pc >= self.cur_block.len:
      break

proc exec*(self: VirtualMachine, code: string, module_name: string): Value =
  let compiled = compile(read_all(code))

  let ns = new_namespace(module_name)
  self.frame.update(new_frame(ns))
  self.code_mgr.data[compiled.id] = compiled
  self.cur_block = compiled

  self.exec()

include "./vm/core"
