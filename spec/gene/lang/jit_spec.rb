require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

include Gene::Lang::Jit

describe "JIT" do
  before do
    @compiler = Compiler.new
    APP.reset
  end

  describe "Atomic expressions" do
    it "
      1
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      'hello world'
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 'hello world'
    end

    it "
      true
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should be_true
    end

    it "
      false
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should be_false
    end

    it "
      null
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should be_nil
    end

    it "
      undefined
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == Gene::UNDEFINED
    end

    it "
      `a
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == Gene::Types::Symbol.new('a')
    end

    it "
      `1
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      `(a 1)
    " do
      mod = @compiler.parse_and_compile example.description
      result = APP.run(mod)
      result.type.should == Gene::Types::Symbol.new('a')
      result.data.should == [1]
    end

    it "
      %a
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == Gene::Types::Symbol.new('%a')
    end

    it "
      (%= 1)
    " do
      mod = @compiler.parse_and_compile example.description
      result = APP.run(mod)
      result.type.should == Gene::Types::Symbol.new('%=')
      result.data.should == [1]
    end

    it "
      [1 2]
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == [1, 2]
    end

    it "
      ARGV
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should be_kind_of Array
    end

    it "
      (var a 1)
      a
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      (var a 1)
      (undef a)
      a
    " do
      mod = @compiler.parse_and_compile example.description
      lambda {
        APP.run(mod)
      }.should raise_error
    end

    it "
      (var a 1)
      [a 2]
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == [1, 2]
    end

    it "
      {^a 1 ^b 2}
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == {'a' => 1, 'b' => 2}
    end

    it "
      (var a 1)
      {^a a ^b 2}
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == {'a' => 1, 'b' => 2}
    end

    it "
      (1 + 2)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 3
    end

    it "
      (true || false)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == true
    end

    it "
      (true && false)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == false
    end

    it "
      (! true)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == false
    end

    it "
      (! false)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == true
    end

    it "
      ($invoke 'abc' '[]' 1)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 'b'
    end

    it "
      ('' 1 2 '3')
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == '123'
    end

    it "
      (var a 1)
      a
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # a... should work
      (var a [1 2])
      [a... 3]
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == [1, 2, 3]
    end

    it "
      # += should work
      (var a 1)
      (a += 2)
      a
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 3
    end

    it "
      # -= should work
      (var a 3)
      (a -= 2)
      a
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # do should work
      (do 1 2)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 2
    end

    it "
      # if should work
      (if true 1 else 2)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # else should work
      (if false 1 else 2)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 2
    end

    it "
      # loop...break should work
      (loop (if true (break)))
      1
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # for should work
      (var sum 0)
      (for (var i 0) (i <= 4) (i += 1)
        (sum += i)
      )
      sum
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 10
    end

    it "
      # function should work
      (fn f _ 1)
      (f)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # When function name is prefixed with '$', arguments are not evaluated
      # Is this a good idea?
      (fn f a
        a
      )
      ($f b)
    " do
      pending
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == Gene::Types::Symbol.new('b')
    end

    it "
      # function should work
      (fnx)
    " do
      mod = @compiler.parse_and_compile example.description
      result = APP.run(mod)
      result.should be_a Gene::Lang::Jit::Function
    end

    it "
      # function should work
      ((fnx a a) 1)
    " do
      mod = @compiler.parse_and_compile example.description
      result = APP.run(mod)
      result.should == 1
    end

    it "
      # function should work
      (fnxx)
    " do
      mod = @compiler.parse_and_compile example.description
      result = APP.run(mod)
      result.should be_a Gene::Lang::Jit::Function
    end

    it "
      # function should work
      ((fnxx 1))
    " do
      mod = @compiler.parse_and_compile example.description
      result = APP.run(mod)
      result.should == 1
    end

    it "
      # function should work
      (fn f _ (fnxx 1))
      ((f))
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # passing argument to function should work
      (fn f a a)
      (f 1)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # Passing multiple arguments should work
      (fn f [a b] (a + b))
      (f 1 2)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 3
    end

    it "
      # argument default value should work
      (fn f [a = 1] a)
      (f)
    " do
      pending
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # Scope inheritance should work
      (fn g _ 1)
      (fn f _ (g))
      (f)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # varargs should work
      (fn f a... a)
      (f 1 2)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == [1, 2]
    end

    it "
      # varargs should work
      (fn f [a b...] b)
      (f 1 2 3)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == [2, 3]
    end

    it "
      # varargs should work
      (fn f [a... b] b)
      (f 1 2 3)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 3
    end

    it "
      # return should work
      (fn f _
        (return 1)
        2
      )
      (f)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # fn...if should work
      (fn f [a b c]
        (if a b else c)
      )
      (f true 1 2)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # fn...if should work
      (fn f [a b c]
        (if a b else c)
      )
      (f false 1 2)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 2
    end

    it "
      # fn...for should work
      (fn f a
        (var sum 0)
        (for (var i 0) (i <= a) (i += 1)
          (sum += i)
        )
        sum
      )
      (f 4)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 10
    end

    it "
      # fn...loop should work
      (fn f _
        (loop
          (return 1)
        )
      )
      (f)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # fn...loop should work
      (fn f _
        (var i 0)
        (loop
          (if (i >= 5)
            (break)
          )
          (i += 1)
        )
        i
      )
      (f)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 5
    end

    it "
      # decorator should work
      (fn f a a)
      +f 1
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # decorator should work
      (fn f a
        (fnx b (a + b))
      )
      (+f 1) 2
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 3
    end

    it "
      # decorator should work
      (fn f a a)
      [+f 1 2]
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == [1, 2]
    end

    it "
      # class/method should work
      (class A
        (method test)
      )
    " do
      mod = @compiler.parse_and_compile example.description
      klass = APP.run(mod)
      klass.methods.size.should == 1
    end

    it "
      # class, new, method invocation should work
      (class A
        (method test _ 1)
      )
      ((new A) .test)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # method_resolver should work
      (class A
        (method_resolver [method props args]
          [method props args]
        )
      )
      ((new A) .test ^key 'val' 1 2)
    " do
      pending
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == ['method', {'key' => 'val'}, [1, 2]]
    end

    it "
      # class initialization should work
      (class A
        (init a
          (@a = a)
        )
        (method test _ @a)
      )
      ((new A 1) .test)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # (.test) should work
      (class A
        (method test _ 1)
        (method test2 _ (.test))
      )
      ((new A) .test2)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # self should work
      (class A
        (method test _ self)
      )
      (var a (new A))
      (a == (a .test))
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == true
    end

    it "
      # property access should work
      (class A
        (method test _
          (@a = 1)
          @a
        )
      )
      ((new A) .test)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # super should work
      (class A
        (method test _
          1
        )
      )
      (class B extend A
        (method test _
          (super)
        )
      )
      ((new B) .test)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # module should work
      (module M
        (method test)
      )
    " do
      mod = @compiler.parse_and_compile example.description
      m = APP.run(mod)
      m.methods.size.should == 1
    end

    it "
      # init is not allowed in a module
      # Ideally this should be caught during the compilation phase.
      # However because Gene is a dynamic and flexible language, it might be too hard to handle all different scenarios.
      (module M
        (init)
      )
    " do
      lambda {
        mod = @compiler.parse_and_compile example.description
        APP.run(mod)
      }.should raise_error
    end

    it "
      # namespace should work
      (ns N)
    " do
      mod = @compiler.parse_and_compile example.description
      result = APP.run(mod)
      result.class.should == Gene::Lang::Jit::Namespace
      result.name.should  == "N"
    end

    it "
      # namespace should work
      (ns N
        (fn f _ 1)
      )
      (N/f)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # namespace should work
      (ns N
        (var a 1)
      )
      N/a
    " do
      mod = @compiler.parse_and_compile example.description
      lambda {
        APP.run(mod)
      }.should raise_error
    end

    it "
      # namespace should work
      (ns N
        (ns O
          (fn f _ 1)
        )
      )
      (N/O/f)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # class as a namespace should work
      (class C
        (fn f _ 1)
      )
      (C/f)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # namespace should work
      (ns N
        (module M
          (fn f _ (g))
        )
      )
      (fn g _ 1)
      (N/M/f)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # namespace should work
      (ns N
        (ns M)
      )
      (class N/M/C)
      N/M/C
    " do
      pending
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should_not be_nil
    end

    it "
      # namespace should work
      (ns N
        (module M
          (fn f _ (g))
        )
        (fn g _ 1)
      )
      (N/M/f)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # define variable on namespace
      (ns N
        (var self/a 1)
      )
      N/a
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # define variable on namespace
      (ns N)
      (var N/a 1)
      N/a
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # function can be used as a namespace
      (fn f)
      (var f/a 1)
      f/a
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # global should work
      (fn global/f _ 1)
      (global/f)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # import should work
      (import test_function from 'spec/gene/lang/test')
      (test_function)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # assert should work
      (assert false 'Houston, we have a problem')
    " do
      mod = @compiler.parse_and_compile example.description
      lambda {
        APP.run(mod)
      }.should raise_error('Houston, we have a problem')
    end

    it "
      # assert should work
      (assert true 'Houston, we have a problem')
      1
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # assert_not should work
      (assert_not true 'Houston, we have a problem')
    " do
      mod = @compiler.parse_and_compile example.description
      lambda {
        APP.run(mod)
      }.should raise_error('Houston, we have a problem')
    end

    it "
      # assert_not should work
      (assert_not false 'Houston, we have a problem')
      1
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # eval should work
      (var a 1)
      # `a => Symbol a => eval-ed to variable a's value
      (eval `a)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # eval should work
      (var a 1)
      (eval
        (if true
          `(do (var b 2) (a + b))
        else
          `a
        )
      )
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 3
    end

    it "
      # render should work
      (var a 1)
      (render %a)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # render should work
      (var a 1)
      (render (%= a))
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # render should work
      (var a 1)
      (fn f b b)
      (render (f %a))
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # throw should work
      (throw 'error')
    " do
      mod = @compiler.parse_and_compile example.description
      lambda {
        APP.run(mod)
      }.should raise_error('error')
    end

    it "
      # try...catch should work
      (class Error) # Error is the ancestor of all error types
      (try
        (throw 'error')
      catch Error
        # TODO: thrown error can be accessed as $error
        1
      )
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # label/goto should work
      # TODO: goto is only allowed to jump to same block
      # TODO: label has to be defined before goto
      (var a 0)
      (label x)
      (if (a < 5)
        (a += 1)
        (goto x)
      )
      a
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 5
    end

    it "
      (fn f [a b]
        (yield a)
        (var c (yield b))
        (yield ^^last c)
      )
      (var x (callcc f))
      (var first  (x 1 2))  # => 1
      (var second (x))      # => 2
      # (x .done?) => false
      (var third  (x 3))    # => 3
      # (x .done?) => true
      ((first + second) + third)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 6
    end

    it "
      # FFI (Foreign Function Interface) should work
      (fn f a
        (a + 1)
      )
    " do
      mod = @compiler.parse_and_compile example.description
      f = APP.run(mod)
      f.call(1).should == 2
    end

    it "
      # FFI (Foreign Function Interface)
      # Gene function to proc
      (fn f a
        (a + 1)
      )
    " do
      mod = @compiler.parse_and_compile example.description
      f = APP.run(mod)
      [1, 2].map(&f).should == [2, 3]
    end

    it "
      # FFI (Foreign Function Interface)
      # Wrap up native class
      # Implicitly extend RubyObject
      # (class A = ruby/A extend B # B must be a decendant of RubyObject
      (class MyString = rb/String # Or rb/A::B

        # If a class = a native class
        #   the instance is result of (init)
        # Else
        #   instance is created internally
        (init arg
          ($invoke ruby/String 'new' arg)
        )

        (method_missing [method args...]
          # Call native method
          ($invoke self method args...)
        )
      )
      (new MyString 'hello')
    " do
      pending
      mod = @compiler.parse_and_compile example.description
      p mod
      APP.run(mod, debug: true).should == "hello"
    end

    it "
      # FFI (Foreign Function Interface)
      (class A
        (method add [a b]
          (a + b)
        )
      )
      (new A)
    " do
      mod = @compiler.parse_and_compile example.description
      a = APP.run(mod)
      a.add(1, 2).should == 3
    end

    it "
      # FFI (Foreign Function Interface)
      (fnx [a b]
        (a + b)
      )
    " do
      mod = @compiler.parse_and_compile example.description
      callback = APP.run(mod)
      def testFFI a, b
        yield a, b
      end
      testFFI(1, 2, &callback).should == 3
    end

    it "
      # FFI (Foreign Function Interface)
      ('a' .size)
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 1
    end

    it "
      # FFI (Foreign Function Interface)
      (var sum 0)
      (4 .times (fnx i (sum += i)))
      sum # should be like 0 + 1 + 2 + 3 => 6
    " do
      mod = @compiler.parse_and_compile example.description
      APP.run(mod).should == 6
    end

    it "
      # FFI (Foreign Function Interface)
      # Passing global parameters to Gene program should work
      global/params/test
    " do
      mod = @compiler.parse_and_compile example.description
      APP.set_param 'test', 1
      APP.run(mod).should == 1
    end
  end

  describe "Complex expressions" do
    testcases = %Q~
      (assert (1 == 1))
    ~

    focus = testcases.include?('!focus!')
    if focus
      puts "\nRun focused tests only!\n"
    end

    testcases.split("\n\n").each do |testcase|
      next if focus and not testcase.include? '!focus!'

      it testcase do
        pending if testcase.index('!pending!') and not testcase.include? '!focus!'

        mod = @compiler.parse_and_compile testcase
        APP.run(mod)
      end
    end
  end
end
