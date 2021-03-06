require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

describe Gene::Lang::Interpreter do
  before do
    @application = Gene::Lang::Application.new
    @application.load_core_libs
  end

  describe "special built-in variables and functions" do
    it "# $application: the application object which is like the start of the universe
      (assert (($invoke ($invoke $application 'class') 'name') == 'Gene::Lang::Application'))
    " do
      @application.parse_and_process(example.description)
    end

    it "# runtime information
    " do
      pending "TODO: define a built-in variable that is a hash containing runtime information, e.g. interpreter, version - make this part of $application?"
    end

    it "# $context: the current context
      (assert (($invoke ($invoke $context 'class') 'name') == 'Gene::Lang::Context'))
    " do
      @application.parse_and_process(example.description)
    end

    it "# $global: the global scope object
      (assert (($invoke ($invoke $global 'class') 'name') == 'Gene::Lang::Scope'))
    " do
      @application.parse_and_process(example.description)
    end

    it "# $scope: the current scope object which may or may not inherit from ancestor scopes
      (fn f _
        $scope
      )
      (assert (($invoke ($invoke (f) 'class') 'name') == 'Gene::Lang::Scope'))
    " do
      @application.parse_and_process(example.description)
    end

    it "# $function: the current function/method that is being called
      (fn f []
        $function
      )
      (assert (($invoke ($invoke (f) 'class') 'name') == 'Gene::Lang::Function'))
    " do
      @application.parse_and_process(example.description)
    end

    it "# $arguments: arguments passed to current function
      (fn f []
        $arguments
      )
      (assert (((f 1 2) .data) == [1 2]))
    " do
      @application.parse_and_process(example.description)
    end

    it "# $invoke: a function that allows invocation of native methods on native objects (this should not be needed if whole interpreter is implemented in Gene Lang)
      (assert (($invoke 'a' 'length') == 1))
    " do
      @application.parse_and_process(example.description)
    end
  end

  describe "class" do
    it "(class A)" do
      result = @application.parse_and_process(example.description)
      result.class.should == Gene::Lang::Class
      result.name.should  == 'A'
    end

    it " # Can run code inside class definition
      (class A
        (var a 1)
        (assert (a == 1))
      )
     " do
      @application.parse_and_process(example.description)
    end

    it "(class A)(new A)" do
      result = @application.parse_and_process(example.description)
      result.class.class.should == Gene::Lang::Class
      result.class.name.should  == 'A'
    end

    it "(class A (method doSomething))" do
      result = @application.parse_and_process(example.description)
      result.class.should == Gene::Lang::Class
      result.name.should  == 'A'
      result.methods.size.should == 1
    end

    it "# self: the self object in a method
      (class A
        (method f _ self)
      )
      (var a (new A))
      (assert (((a .f) .class) == A))
    " do
      @application.parse_and_process(example.description)
    end

    it "# @a: access property `a` directly
      (class A
        (init a
          (@a = a)
        )
        (method test _
          @a
        )
      )
      (assert (((new A 1) .test) == 1))
    " do
      @application.parse_and_process(example.description)
    end

    it "# (@ a): access dynamic property
      (class A
        (init [name value]
          ((@ name) = value)
        )
        (method test name
          ((@ name))
        )
      )
      (assert (((new A 'a' 100) .test 'a') == 100))
    " do
      @application.parse_and_process(example.description)
    end

    it "# Typical usecase
      # Define class A
      (class A
        # Constructor
        (init a
          (@a = a)
        )

        # Define method incr_a
        (method incr_a _
          (@a += 1)
        )

        # Define method test
        (method test num
          # Here is how you call method from same class
          (.incr_a)
          (@a + num)
        )
      )

      # Instantiate A
      (var a (new A 1))

      # Call method on an instance
      (assert ((a .test 2) == 4))
    " do
      @application.parse_and_process(example.description)
    end

    it "# Class creates a namespace
      (class A
        (fn test _
          1
        )
      )
      (assert ((A/test) == 1))
    " do
      @application.parse_and_process(example.description)
    end
  end

  describe "properties" do
    it "# with custom getter/setter
      (class A
        # Define a property named x
        (prop x
          # TODO: rethink how getter/setter logic is defined
          ^get [@x]
          ^set [value (@x = value)]
        )
      )
      (var a (new A))
      # Property x can be accessed like methods
      (a .x= 'value')
      (assert ((a .x) == 'value'))
    " do
      @application.parse_and_process(example.description)
    end

    it "# (prop x) will create default getter/setter methods
      (class A (prop x))
      (var a (new A))
      (a .x= 'value')
      (assert ((a .x) == 'value'))
    " do
      @application.parse_and_process(example.description)
    end
  end

  describe "module" do
    it "# creating module, including module and inheritance etc should work
      (class A
        (method test _
          (@value = ($invoke @value 'push' 'A.test'))
          @value
        )
      )
      (module M)
      (module N
        (include M)
      )
      (module O)
      (class B extend A
        (include N)
        (include O)
        (init _ (@value = []))
        (method test _
          (super)
          (@value = ($invoke @value 'push' 'B.test'))
          @value
        )
      )
      (var b (new B))
      (assert ((b .test) == ['A.test' 'B.test']))
    " do
      @application.parse_and_process(example.description)
    end
  end

  describe "cast: will create a new object of the new class and shallow-copy all properties" do
    it "# `class` should return the new class
      (class A)
      (class B)
      (var a (new A))
      (assert (((cast a B) .class) == B))
    " do
      @application.parse_and_process(example.description)
    end

    it "# invoking method on the new class should work
      (class A)
      (class B
        (method test _ 'test in B')
      )
      (var a (new A))
      (assert (((cast a B) .test) == 'test in B'))
    " do
      @application.parse_and_process(example.description)
    end

    it "# Modification on casted object will not be lost
      (class A
        (method name _ @name)
      )
      (class B
        (method test _
          (@name = 'b')
        )
      )
      (var a (new A))
      ((cast a B) .test)
      (assert ((a .name) == 'b'))
    " do
      @application.parse_and_process(example.description)
    end
  end

  describe "inheritance" do
    it "# If a method is not defined in my class, search in parent classes
      (class A
        (method testA _ 'testA')
      )
      (class B extend A
      )
      (var b (new B))
      (assert ((b .testA) == 'testA'))
    " do
      @application.parse_and_process(example.description)
    end

    it "# Search method up to the top of class hierarchy
      (class A
        (method test _ 'test in A')
      )
      (class B extend A
      )
      (class C extend B
      )
      (var c (new C))
      (assert ((c .test) == 'test in A'))
    " do
      @application.parse_and_process(example.description)
    end

    it "# `super` will invoke same method in parent class
      (class A
        (method test [a b]
          (a + b)
        )
      )
      (class B extend A
        (method test [a b]
          (super a b)
        )
      )
      (var b (new B))
      (assert ((b .test 1 2) == 3))
    " do
      @application.parse_and_process(example.description)
    end

    it "# `init` should be inherited
      (class A
        (prop name)
        (init name
          (@name = name)
        )
      )
      (class B extend A
      )
      (var b (new B 'test'))
      (assert ((b .name) == 'test'))
    " do
      @application.parse_and_process(example.description)
    end
  end

  describe "fn" do
    it "(fn doSomething)" do
      result = @application.parse_and_process(example.description)
      result.class.should == Gene::Lang::Function
      result.name.should  == 'doSomething'
    end

    it "(fn doSomething [a] (a + 1))" do
      result = @application.parse_and_process(example.description)
      result.class.should == Gene::Lang::Function
      result.name.should  == 'doSomething'
      result.args_matcher.all_matchers.size.should == 1
      arg1 = result.args_matcher.data_matchers[0]
      arg1.index.should == 0
      arg1.name.should == 'a'
    end

    it "
      (fn f a
        ^!eval_arguments
        a
      )
      (var a 1)
      (assert ((f a) == :a))
    " do
      @application.parse_and_process(example.description)
    end

    it "
      (fn f a
        ^!eval_arguments
        a
      )
      (var a 1)
      (var result (f (:a + 1)))
      (assert ((result .type) == 1))
    " do
      pending
      @application.parse_and_process(example.description)
    end

    it "
      (fn f [^^a]
        a
      )
      (assert ((f ^a 1) == 1))
    " do
      @application.parse_and_process(example.description)
    end

    it "# Function parameters are passed by reference: check []
      (fn doSomething array
        ($invoke array 'push' 'doSomething')
      )
      (var a [])
      (doSomething a)
      (assert (a == ['doSomething']))
    " do
      @application.parse_and_process(example.description)
    end

    it "# Function parameters are passed by reference: check {}
      (fn doSomething hash
        ($invoke hash '[]=' 'key' 'value')
      )
      (var a {})
      (doSomething a)
      (assert (($invoke a '[]' 'key') == 'value'))
    " do
      @application.parse_and_process(example.description)
    end

    describe "Variable length arguments" do
      it "# In function definition
        (fn doSomething args... args)
        (assert ((doSomething 1 2) == [1 2]))
      " do
        @application.parse_and_process(example.description)
      end

      it "# In function definition
        (fn doSomething [args...] args)
        (assert ((doSomething 1 2) == [1 2]))
      " do
        @application.parse_and_process(example.description)
      end

      it "# can have arguments following it
        (fn doSomething [args... last] args)
        (assert ((doSomething 1 2) == [1]))
      " do
        pending
        @application.parse_and_process(example.description)
      end

      it "# In function invocation
        (fn doSomething [a b]
          (a + b)
        )
        (var array [1 2])
        (assert ((doSomething array...) == 3))
      " do
        @application.parse_and_process(example.description)
      end

      it "# In both function definition and function invocation
        (fn doSomething args...
          args
        )
        (var array [1 2])
        (assert ((doSomething array...) == [1 2]))
      " do
        @application.parse_and_process(example.description)
      end
    end

    it "# Define and invoke function without arguments
      (fn doSomething _ 1)
      (assert ((doSomething) == 1))
    " do
      @application.parse_and_process(example.description)
    end

    it "# return nothing
      (fn doSomething _
        return
        2
      )
      (assert ((doSomething) == undefined))
    " do
      @application.parse_and_process(example.description)
    end

    it "# return something
      (fn doSomething _
        (return 1)
        2
      )
      (assert ((doSomething) == 1))
    " do
      @application.parse_and_process(example.description)
    end

    it "# Invoke function immediately, note the double '(' and ')'
      (assert (((fn doSomething _ 1)) == 1))
    " do
      @application.parse_and_process(example.description)
    end

    it "(fn doSomething a 1)" do
      result = @application.parse_and_process(example.description)
      result.class.should == Gene::Lang::Function
      result.name.should  == 'doSomething'
      result.args_matcher.all_matchers.size.should == 1
      arg1 = result.args_matcher.data_matchers[0]
      arg1.index.should == 0
      arg1.name.should == 'a'
      result.statements.first.should == 1
    end

    it "# Define and invoke function with one argument
      (fn doSomething a a)
      (assert ((doSomething 1) == 1))
    " do
      @application.parse_and_process(example.description)
    end

    it "# Define and invoke function with multiple arguments
      (fn doSomething [a b]
        (a + b)
      )
      (assert ((doSomething 1 2) == 3))
    " do
      @application.parse_and_process(example.description)
    end

    it "# `call` invokes a function with a self, therefore makes the function behave like a method
      (fn f arg
        (.test arg)
      )
      (class A
        (method test arg arg)
      )
      (var a (new A))
      (assert ((call f a 'value') == 'value')) # self: a, arguments: 'value'
    " do
      @application.parse_and_process(example.description)
    end

    it "# By default, function will inherit the scope where it is defined (like in JavaScript)
      (var a 1)
      (fn f b (a + b)) # `a` is inherited, `b` is an argument
      (assert ((f 2) == 3))
    " do
      @application.parse_and_process(example.description)
    end
  end

  describe "Bound function" do
    it "# should work
      (fn f _
        (.class)
      )
      (var f2 (bind f (new Object)))
      (assert ((f2) == Object))
    " do
      @application.parse_and_process(example.description)
    end
  end

  describe "Method vs function" do
    it "# Method   WILL NOT   inherit the scope where it is defined in
      (class A
        (var x 1)
        (method doSomething _ x)
      )
      (var a (new A))
      (a .doSomething) # should throw error
    " do
      lambda {
        result = @application.parse_and_process(example.description)
      }.should raise_error
    end

    it "# Function   WILL   inherit the scope where it is defined in
      (var x 1)
      (fn doSomething _ x)
      (assert ((doSomething) == 1))
    " do
      @application.parse_and_process(example.description)
    end
  end

  describe "fnx - anonymous function" do
    it "# Define and invoke an anonymous function
      (assert (((fnx _ 1)) == 1))
    " do
      @application.parse_and_process(example.description)
    end

    it "# Can be assigned to a variable and invoked later
      (var f (fnx _ 1))
      (assert ((f) == 1))
    " do
      @application.parse_and_process(example.description)
    end
  end

  describe "fnxx - anonymous dummy function" do
    it "# Can be assigned to a variable and invoked later
      (var f (fnxx 1))
      (assert ((f) == 1))
    " do
      @application.parse_and_process(example.description)
    end
  end

  describe "Variable" do
    it "# Must be defined first
      a # should throw error
    " do
      lambda {
        @application.parse_and_process(example.description)
      }.should raise_error
    end
  end

  describe "Assignment" do
    it "# `=` should work
      (var a)
      (a = 1)
      (assert (a == 1))
    " do
      @application.parse_and_process(example.description)
    end
  end

  describe "Comparison" do
    it("((1 == 1) == true)")  { @application.parse_and_process(example.description).should be_true }
    it("((1 == 2) == false)") { @application.parse_and_process(example.description).should be_true }
    it("((1 != 1) == false)") { @application.parse_and_process(example.description).should be_true }
    it("((1 != 2) == true)")  { @application.parse_and_process(example.description).should be_true }
    it("((1 <  2) == true)")  { @application.parse_and_process(example.description).should be_true }
    it("((2 <  2) == false)") { @application.parse_and_process(example.description).should be_true }
    it("((3 <  2) == false)") { @application.parse_and_process(example.description).should be_true }
    it("((1 <= 2) == true)")  { @application.parse_and_process(example.description).should be_true }
    it("((2 <= 2) == true)")  { @application.parse_and_process(example.description).should be_true }
    it("((3 <= 2) == false)") { @application.parse_and_process(example.description).should be_true }
    it("((1 >  2) == false)") { @application.parse_and_process(example.description).should be_true }
    it("((2 >  2) == false)") { @application.parse_and_process(example.description).should be_true }
    it("((3 >  2) == true)")  { @application.parse_and_process(example.description).should be_true }
    it("((1 >= 2) == false)") { @application.parse_and_process(example.description).should be_true }
    it("((2 >= 2) == true)")  { @application.parse_and_process(example.description).should be_true }
    it("((3 >= 2) == true)")  { @application.parse_and_process(example.description).should be_true }
  end

  describe "Boolean operations" do
    it("((! true)         == false)") { @application.parse_and_process(example.description).should be_true }
    it("((true  && true)  == true)")  { @application.parse_and_process(example.description).should be_true }
    it("((true  && false) == false)") { @application.parse_and_process(example.description).should be_true }
    it("((false && false) == false)") { @application.parse_and_process(example.description).should be_true }
    it("((true  || true)  == true)")  { @application.parse_and_process(example.description).should be_true }
    it("((true  || false) == true)")  { @application.parse_and_process(example.description).should be_true }
    it("((false || false) == false)") { @application.parse_and_process(example.description).should be_true }

    it("((false && (throw 'error')) == false)")  { @application.parse_and_process(example.description).should be_true }
    it("((true  || (throw 'error')) == true)")   { @application.parse_and_process(example.description).should be_true }
  end

  describe "Binary expression" do
    it "(assert ((1 + 2) == 3))" do
      @application.parse_and_process(example.description)
    end
  end

  describe "Variable definition" do
    it "# Access undefined variable should throw error
      a
    " do
      lambda {
        @application.parse_and_process(example.description)
      }.should raise_error
    end

    it "(var a 'value')" do
      result = @application.parse_and_process(example.description)
      result.class.should == Gene::Lang::Variable
      result.name.should  == 'a'
      result.value.should == 'value'
    end

    it "# Alias
      (var a 1)
      (alias a b)
      (assert (b == 1))
    " do
      pending
      @application.parse_and_process(example.description)
    end

    it "# Define a variable and assign expression result as value
      (var a (1 + 2))
    " do
      result = @application.parse_and_process(example.description)
      result.class.should == Gene::Lang::Variable
      result.name.should  == 'a'
      result.value.should == 3
    end

    it "# Duplicate definition is not allowed
      (var a 1)
      (var a 2)
    " do
      pending
      lambda {
        @application.parse_and_process(example.description)
      }.should raise_error
    end

    it "# Define variable only if it's not defined in current scope
      (var a 1)
      (var ^!defined a 2)
      (assert (a == 1))
    " do
      pending
      @application.parse_and_process(example.description)
    end

    it "# Define and use variable
      (var a 1)
      (assert ((a + 2) == 3))
    " do
      @application.parse_and_process(example.description)
    end

    it "# Use multiple variables in one expression
      (var a 1)
      (var b 2)
      (assert ((a + b) == 3))
    " do
      @application.parse_and_process(example.description)
    end

    it "# Regular variable not accessible if scope is not inherited
      (var a 1)
      (fn f _
        ^!inherit_scope
        a
      )
      (f)
    " do
      lambda {
        @application.parse_and_process(example.description)
      }.should raise_error
    end

    it "# Define variable inside current namespace
      (nsvar a 1)
      (fn f _
        ^!inherit_scope
        a
      )
      (assert ((f) == 1))
    " do
      @application.parse_and_process(example.description)
    end
  end

  describe "do" do
    it "# returns result of last expression
      (assert
        ((do (var i 1)(i + 2)) == 3)
      )
    " do
      @application.parse_and_process(example.description)
    end
  end

  describe "if
    # TODO:
    # (if cond ...)
    # (if_not cond ...)  # Do not allow 'else_if' or 'else' together with 'if_not'
    # (if cond ... else ...)
    # (if cond ... else_if cond ...)
    # (if cond ... else_if cond ... else ...)
    # (if cond ... else_if_not cond ...)  # This is not good!
    # better formatted to something like
    # (if cond
    #   ...
    # else_if cond
    #   ...
    # else
    #   ...
    # )
  " do
    it "# condition evaluates to true
      (assert ((if true 1 2) == 2))
    " do
      @application.parse_and_process(example.description)
    end

    it "# allow optional 'then'
      (assert ((if true then 1 2) == 2))
    " do
      @application.parse_and_process(example.description)
    end

    it "# 'then' should follow condition immediately
      (assert ((if true 1 then 2) == 2))
    " do
      lambda {
        @application.parse_and_process(example.description)
      }.should raise_error
    end

    it "# 0 evaluates to true
      (assert ((if 0 then 1 else 2) == 1))
    " do
      @application.parse_and_process(example.description)
    end

    it "# null evaluates to false
      (assert ((if null then 1 else 2) == 2))
    " do
      @application.parse_and_process(example.description)
    end

    it "# undefined evaluates to false
      (assert ((if undefined then 1 else 2) == 2))
    " do
      @application.parse_and_process(example.description)
    end

    it "# condition evaluates to true
      (assert ((if true 1 [1 2]) == [1 2]))
    " do
      @application.parse_and_process(example.description)
    end

    it "# condition evaluates to true
      (assert
        (
          (if true
            (var a 1)
            (a + 2)
          else
            fail
          ) == 3
        )
      )
    " do
      @application.parse_and_process(example.description)
    end

    it "# condition evaluates to false
      (assert
        (
          (if false
            fail
          else
            (var a 1)
            (a + 2)
          ) == 3
        )
      )
    " do
      @application.parse_and_process(example.description)
    end

    it "# if...else_if
      (assert
        (
          (if false
            fail
          else_if false
            fail
          else_if true
            (var a 1)
            (a + 2)
          ) == 3
        )
      )
    " do
      @application.parse_and_process(example.description)
    end

    it "# if...else_if
      (assert
        (
          (if false
            fail
          else_if false then
            fail
          else_if true then
            (var a 1)
            (a + 2)
          ) == 3
        )
      )
    " do
      @application.parse_and_process(example.description)
    end

    it "# then in bad position
      (if false
        fail
      else_if true
        1
        then
        2
      )
    " do
      lambda {
        @application.parse_and_process(example.description)
      }.should raise_error
    end

    it "# if...else_if...else
      (assert
        (
          (if false
            fail
          else_if false
            fail
          else
            (var a 1)
            (a + 2)
          ) == 3
        )
      )
    " do
      @application.parse_and_process(example.description)
    end

    it "# condition evaluates to false
      (assert ((if false 1 else 2) == 2))
    " do
      @application.parse_and_process(example.description)
    end

    it "# then in bad position
      (if false
        1
      else then
        2
      )
    " do
      lambda {
        @application.parse_and_process(example.description)
      }.should raise_error
    end

    it "# condition evaluates to false
      (assert ((if false 1 else [1 2]) == [1 2]))
    " do
      @application.parse_and_process(example.description)
    end
  end

  describe "if_not" do
    it "(assert ((if_not true 1 2) == undefined))" do
      @application.parse_and_process(example.description)
    end

    it "(assert ((if_not false 1 2) == 2))" do
      @application.parse_and_process(example.description)
    end
  end

  describe "for
    # For statement has structure of (for init cond update statements...)
    # It can be used to create other type of loops, iterators etc
  " do
    it "# Basic usecase
      (var result 0)
      (for (var i 0)(i < 5)(i += 1)
        (result += i)
      )
      (assert (result == 10))
    " do
      @application.parse_and_process(example.description)
    end

    it "# break from the for-loop
      (var result 0)
      (for (var i 0)(i < 100)(i += 1)
        (if (i >= 5) break)
        (result += i)
      )
      (assert (result == 10))
    " do
      @application.parse_and_process(example.description)
    end

    it "# return from for-loop ?!
      (var result 0)
      (for (var i 0)(i < 100)(i += 1)
        (if (i >= 5) return)
        (result += i)
      )
      (assert (result == 10))
    " do
      @application.parse_and_process(example.description)
    end

    it "# for-loop inside function
      (var result 0)
      (fn f _
        (for (var i 0)(i < 100)(i += 1)
          (if (i >= 5) return)
          (result += i)
        )
        # should not reach here
        (result = 0)
      )
      (f)
      (assert (result == 10))
    " do
      @application.parse_and_process(example.description)
    end
  end

  describe "loop - creates simplist loop" do
    it "# Basic usecase
      (var i 0)
      (loop
        (i += 1)
        (if (i >= 5) break)
      )
      (assert (i == 5))
    " do
      @application.parse_and_process(example.description)
    end

    it "# return value passed to `break`
      (var i 0)
      (assert
        ((loop
          (i += 1)
          (if (i >= 5) (break 100))
        ) == 100)
      )
    " do
      @application.parse_and_process(example.description)
    end

    it "# Use `loop` to build `for` as a regular function
      (fn for_test [init cond update stmts...]
        ^!inherit_scope ^!eval_arguments
        # Do not inherit scope from where it's defined in: equivalent to ^!inherit_scope
        # Args are not evaluated before passed in: equivalent to ^!eval_arguments
        #
        # After evaluation, ReturnValue are returned as is, BreakValue are unwrapped and returned
        ($invoke $caller_context 'process_statements' init)
        (loop
          # check condition and break if false
          (var result ($invoke $caller_context 'process_statements' cond))
          (if (($invoke ($invoke result 'class') 'name') == 'Gene::Lang::BreakValue')
            (return ($invoke result 'value'))
          )
          (if_not result
            return
          )

          ($invoke $caller_context 'process_statements' stmts)
          ($invoke $caller_context 'process_statements' update)
        )
      )
      (var result 0)
      (for_test (var i 0) (i <= 4) (i += 1)
        (result += i)
      )
      (assert (result == 10))
    " do
      @application.parse_and_process(example.description)
    end

    it "# Use `for` to build `loop` as a regular function
      (fn loop_test args...
        ^!inherit_scope ^!eval_arguments
        # Do not inherit scope from where it's defined in: equivalent to ^!inherit_scope
        # Args are not evaluated before passed in: equivalent to ^!eval_arguments
        #
        # After evaluation, ReturnValue are returned as is, BreakValue are unwrapped and returned
        (for _ _ _
          (var result ($invoke $caller_context 'process_statements' args))
          (if (($invoke ($invoke result 'class') 'name') == 'Gene::Lang::BreakValue')
            (return ($invoke result 'value'))
          )
        )
      )
      (var i 0)
      (assert
        ((loop_test
          (i += 1)
          (if (i >= 5) (break 100))
        ) == 100)
      )
    " do
      @application.parse_and_process(example.description)
    end
  end

  describe "noop - no operation, do nothing and return undefined" do
    it "(assert (noop == undefined))" do
      @application.parse_and_process(example.description)
    end
  end

  describe "_ is a placeholder, equivalent to undefined in most but not all places" do
    it "# Putting _ at the place of arguments will not create an argument named `_`
      (fn f _ _)
      (assert ((f 1) == _))
    " do
      @application.parse_and_process(example.description)
    end

    it "# _ can be used in for-loop as placeholder, when it's used in place of the condition, it's treated as truth value
      (var sum 0)
      (var i 0)
      (for _ _ _
        (if (i > 4) break)
        (sum += i)
        (i += 1)
      )
      (assert (sum == 10))
    " do
      @application.parse_and_process(example.description)
    end
  end

  describe "Scoping" do
    it "
      (var a)
      (class A
        (method doSomething _
          a
        )
      )
      ((new A) .doSomething)
    " do
      lambda {
        @application.parse_and_process(example.description)
      }.should raise_error
    end
  end

  describe "Namespace / module system" do
    it "# Namespace and members can be referenced from same scope
      (ns a
        (class C)
      )
      (assert ((a/C .name) == 'C'))
    " do
      @application.parse_and_process(example.description)
    end

    it "# Namespace and members can be referenced from nested scope
      (ns a
        (class C)
      )
      (class B
        (method test _
          (a/C .name)
        )
      )
      (assert (((new B) .test) == 'C'))
    " do
      @application.parse_and_process(example.description)
    end
  end

  describe "Decorators" do
    it "# should work on top level
      (var members [])
      (fn add_to_members f
        ($invoke members 'push' (f .name))
      )
      +add_to_members
      (fn test)
      (assert (members == ['test']))
    " do
      @application.parse_and_process(example.description)
    end

    it "# can be chained
      (var members [])
      (fn add_to_members f
        ($invoke members 'push' (f .name))
        f
      )
      +add_to_members
      +add_to_members
      (fn test)
      (assert (members == ['test' 'test']))
    " do
      @application.parse_and_process(example.description)
    end

    it "# should work inside ()
      (ns a
        (var members [])
        (fn add_to_members f
          ($invoke members 'push' (f .name))
        )
        +add_to_members
        (fn test)
      )
      (assert (a/members == ['test']))
    " do
      @application.parse_and_process(example.description)
    end

    it "# should work inside []
      (fn increment x
        (x + 1)
      )
      (var a [+increment 1])
      (assert (a == [2]))
    " do
      @application.parse_and_process(example.description)
    end

    it "# decorator can be invoked with arguments
      (var members [])
      (fn add_to_members [array]
        (fnx target
          ($invoke array 'push' (target .name))
          target
        )
      )
      (+add_to_members members)
      (fn test)
      (assert (members == ['test']))
    " do
      @application.parse_and_process(example.description)
    end
  end

  describe "with - create a new context with a given self" do
    it "# should work
      (var o (new Object))
      (with o
        (assert ((.class) == Object))
      )
    " do
      @application.parse_and_process(example.description)
    end

    it "# inside function
      (var o (new Object))
      (fn f _
        (with o (return (.class)))
        _
      )
      (assert ((f) == Object))
    " do
      @application.parse_and_process(example.description)
    end
  end

  describe "scope - create a new context with a new scope" do
    it "# should work
      (var a 1)
      (scope
        (var a 2)
        (assert (a == 2))
      )
      (assert (a == 1))
    " do
      @application.parse_and_process(example.description)
    end

    it "# inherit_scope = false
      (fn f _
        (var a 1)
        (scope ^!inherit_scope
          (a + 1)
        )
      )
      (f)
    " do
      lambda {
        @application.parse_and_process(example.description)
      }.should raise_error
    end
  end

  describe "Create / modify / access native Gene object" do
    it "(assert (((:a 1) .type) == :a))" do
      @application.parse_and_process(example.description)
    end

    it "(assert (((:a 1) .data) == [1]))" do
      @application.parse_and_process(example.description)
    end

    it "(assert (((:a 1) .first) == 1))" do
      @application.parse_and_process(example.description)
    end

    it "(assert (((:a ^key 'value') .get 'key') == 'value'))" do
      @application.parse_and_process(example.description)
    end
  end

  describe "Pattern match / destructure" do
    describe "Gene Object" do
      it "
        (match obj (:a))
        (assert (obj == (:a)))
      " do
        @application.parse_and_process(example.description)
      end

      it "
        (match obj 1)
        (assert (obj == 1))
      " do
        @application.parse_and_process(example.description)
      end

      it "
        (match (type) (:a))
        (assert (type == :a))
      " do
        @application.parse_and_process(example.description)
      end

      it "
        (match (type) (:: ((a) 1)))
        (assert ((type .type) == :a))
      " do
        @application.parse_and_process(example.description)
      end

      it "
        (match (_ first second) (_ 1 2))
        (assert (first  == 1))
        (assert (second == 2))
      " do
        @application.parse_and_process(example.description)
      end

      it "
        (match (_ first second) (_ 1))
        (assert (first  == 1))
        (assert (second == undefined))
      " do
        @application.parse_and_process(example.description)
      end

      it "
        (match (_ first second...) (_ 1 2 3))
        (assert (first  == 1))
        (assert (second == [2 3]))
      " do
        @application.parse_and_process(example.description)
      end

      it "
        (match (_ ... last) (_ 1 2 3))
        (assert (last == 3))
      " do
        @application.parse_and_process(example.description)
      end

      it "
        (match [first second] (_ 1 2))
        (assert (first  == 1))
        (assert (second == 2))
      " do
        @application.parse_and_process(example.description)
      end

      it "
        (match [first second...] (_ 1 2 3))
        (assert (first  == 1))
        (assert (second == [2 3]))
      " do
        @application.parse_and_process(example.description)
      end

      it "
        (match [... last] (_ 1 2 3))
        (assert (last == 3))
      " do
        @application.parse_and_process(example.description)
      end

      it "
        (match (_ ^^a ^^b) (_ ^a 1 ^b 2))
        (assert (a == 1))
        (assert (b == 2))
      " do
        @application.parse_and_process(example.description)
      end

      it "
        (match {^^a ^^b} (_ ^a 1 ^b 2))
        (assert (a == 1))
        (assert (b == 2))
      " do
        @application.parse_and_process(example.description)
      end

      it "
        (match (_ (_ first second)) (_ (_ 1 2)))
        (assert (first  == 1))
        (assert (second == 2))
      " do
        @application.parse_and_process(example.description)
      end

      it "
        (match (_ (_ first second)))
        (assert (first  == undefined))
        (assert (second == undefined))
      " do
        @application.parse_and_process(example.description)
      end

      it "
        (match [[first second]] (_ (_ 1 2)))
        (assert (first == 1))
        (assert (second == 2))
      " do
        @application.parse_and_process(example.description)
      end

      it "
        (match (_ ^a attr_a ^b (attr_b_type)) (_ ^a (:a) ^b (:b)))
        (assert (attr_a == (:a)))
        (assert (attr_b_type == :b))
      " do
        @application.parse_and_process(example.description)
      end

      it "
        (match {^a attr_a ^b (attr_b_type)} (_ ^a (:a) ^b (:b)))
        (assert (attr_a == (:a)))
        (assert (attr_b_type == :b))
      " do
        @application.parse_and_process(example.description)
      end
    end

    describe "Array" do
      it "
        (match (type) [])
        (assert (type == :Array))
      " do
        @application.parse_and_process(example.description)
      end

      it "
        (match [first second] [1 2])
        (assert (first == 1))
        (assert (second == 2))
      " do
        @application.parse_and_process(example.description)
      end
    end

    describe "Hash" do
      it "
        (match (type) {})
        (assert (type == :Hash))
      " do
        @application.parse_and_process(example.description)
      end

      it "
        (match {^^a ^^b} {^a 1 ^b 2})
        (assert (a == 1))
        (assert (b == 2))
      " do
        @application.parse_and_process(example.description)
      end
    end

    describe "String" do
      it "
        (match (type) '')
        (assert (type == :String))
      " do
        @application.parse_and_process(example.description)
      end
    end
  end

  describe "Exception" do
    it "
      (throw 'some error')
      1 # should not reach here
    " do
      lambda {
        @application.parse_and_process(example.description)
      }.should raise_error('some error')
    end

    it "
      [
        (throw 'some error')
        1 # should not reach here
      ]
    " do
      lambda {
        @application.parse_and_process(example.description)
      }.should raise_error('some error')
    end

    it "
      (fn f _
        (throw 'some error')
      )
      (f)
      (println 'Should not reach here')
    " do
      lambda {
        @application.parse_and_process(example.description)
      }.should raise_error('some error')
    end

    it "
      (var a (throw 'some error'))
      (println 'Should not reach here')
    " do
      pending
      lambda {
        @application.parse_and_process(example.description)
      }.should raise_error('some error')
    end

    it "
      (fn f1 f
        (f)
      )
      (fn f2 _
        (throw 'some error')
        (println 'f2: Should not reach here')
      )
      (f1 f2)
      (println 'Should not reach here')
    " do
      lambda {
        @application.parse_and_process(example.description)
      }.should raise_error('some error')
    end

    it "# catch (will inherit scope etc)
      (catch
        ^Exception (fnx e (result = 'Exception'))
        ^default   (fnx e (result = 'default'))
        (var result)
        (throw 'some error')
      )
      (assert (result == 'Exception'))
    " do
      @application.parse_and_process(example.description)
    end

    it "# catch default
      (catch
        ^default (fnx e (result = 'default'))
        (var result)
        (throw 'some error')
      )
      (assert (result == 'default'))
    " do
      @application.parse_and_process(example.description)
    end

    it "# catch default - won't catch Error
      (catch
        ^default (fnx e (result = 'default'))
        (var result)
        (throw Error 'some error')
      )
    " do
      lambda {
        @application.parse_and_process(example.description)
      }.should raise_error('some error')
    end

    it "# ensure
      (var a)
      (catch
        ^default (fnxx)
        ^ensure  (fnxx (a = 'ensure'))
        (throw 'some error')
      )
      (assert (a == 'ensure'))
    " do
      @application.parse_and_process(example.description)
    end

    it "# do...catch
      (var result)
      (do
        ^catch {
          ^Exception (fnx e (result = 'Exception'))
        }
        (throw 'some error')
      )
      (assert (result == 'Exception'))
    " do
      pending
      @application.parse_and_process(example.description)
    end

    it "# do...catch default
      (var result)
      (do
        ^catch (fnx e (result = (e .message)))
        (throw 'some error')
      )
      (assert (result == 'some error'))
    " do
      pending
      @application.parse_and_process(example.description)
    end

    it "# fn...catch: the callback should run in the context of function
      (fn f
        ^catch {
          ^Exception (fnx e (result = 'Exception'))
        }
        (var result)
        (throw 'some error')
      )
      (assert (result == 'Exception'))
    " do
      pending
      @application.parse_and_process(example.description)
    end
  end

  describe "Assert" do
    it "(assert true)" do
      @application.parse_and_process(example.description)
    end

    it "(assert false)" do
      lambda {
        @application.parse_and_process(example.description)
      }.should raise_error('Assertion failure: false')
    end

    it "(assert false 'test message')" do
      lambda {
        @application.parse_and_process(example.description)
      }.should raise_error('Assertion failure: test message: false')
    end
  end

  describe "Arguments" do
    it "# should work
      (fn f [a b]
        (a += 1)
        (b *= 10)
        $arguments
      )
      (assert (((f 1 2).data) == [2 20]))
    " do
      @application.parse_and_process(example.description)
    end
  end

  describe "Easy build and access" do
    it "
      (assert ([(expand [1 2])] == [1 2]))
    " do
      @application.parse_and_process(example.description)
    end

    it "
      (assert ({^x (expand {^a 1 ^b 2})} == {^a 1 ^b 2}))
    " do
      @application.parse_and_process(example.description)
    end

    it "
      (assert ((:o ^x (expand {^a 1 ^b 2}) (expand [100 200])) == (:o ^a 1 ^b 2 100 200)))
    " do
      pending
      @application.parse_and_process(example.description)
    end
  end

  describe "String concatenation" do
    it "
      (assert (('{a: ' 1 ', b: ' 2 '}') == '{a: 1, b: 2}'))
    " do
      @application.parse_and_process(example.description)
    end

    it "
      (assert (('' [1 2]) == '[1 2]'))
    " do
      @application.parse_and_process(example.description)
    end

    it "
      (assert (('' (expand [1 2])) == '12'))
    " do
      @application.parse_and_process(example.description)
    end
  end

  describe "Templates" do
    it "
      +assert ((:: (a 100)) == (:a 100))
    " do
      @application.parse_and_process(example.description)
    end

    it "
      (var a 100)
      +assert ((:: (a %a)) == (:a 100))
    " do
      @application.parse_and_process(example.description)
    end

    it "
      (var a 100)
      +assert ((:a %a) == (:a 100))
    " do
      @application.parse_and_process(example.description)
    end

    it "
      (var a 100)
      +assert ((:: (a %a)) == (:a 100))
    " do
      @application.parse_and_process(example.description)
    end

    it "
      +assert ((:a (%= true)) == (:a true))
    " do
      @application.parse_and_process(example.description)
    end

    it "
      +assert ((:a (%= (100 < 200))) == (:a true))
    " do
      @application.parse_and_process(example.description)
    end

    it "
      (var a 100)
      +assert ((:: (a [%a])) == (:a [100]))
    " do
      @application.parse_and_process(example.description)
    end

    it "
      (var a 100)
      +assert ((:: {^value %a}) == {^value 100})
    " do
      @application.parse_and_process(example.description)
    end

    it "
      (var a 100)
      +assert ((:: (a ^prop %a)) == (:a ^prop 100))
    " do
      @application.parse_and_process(example.description)
    end

    it "
      (var a 100)
      +assert ((:: (a (b ^prop %a))) == (:a (b ^prop 100)))
    " do
      @application.parse_and_process(example.description)
    end

    it "
      +assert ((:: (%= (var a 100) a)) == 100)
    " do
      @application.parse_and_process(example.description)
    end

    it "
      +assert ((:: (%= (1 < 2))) == true)
    " do
      @application.parse_and_process(example.description)
    end

    it "
      (var a [1 2])
      +assert ((:: (a (%expand a))) == (:a 1 2))
    " do
      @application.parse_and_process(example.description)
    end

    it "
      (fn f a
        (:: (a (%= (a + 1))))
      )
      +assert (((f 1) .get 0) == 2)
      +assert (((f 2) .get 0) == 3)
    " do
      @application.parse_and_process(example.description)
    end

    it "
      (var a 100)
      (fn f [b c] (b + c))
      +assert ((:: (%f a 200)) == 300)
    " do
      @application.parse_and_process(example.description)
    end

    it "
      (fn f [b c]
        ^!eval_arguments
        (b + c)
      )
      (var a 100)
      +assert ((f ^^#render_args %a 200) == 300)
      +assert ((f ^^#render_args 200 %a) == 300)
    " do
      @application.parse_and_process(example.description)
    end

    it "
      (fn f [b c]
        ^!eval_arguments
        (b + c)
      )
      +assert ((f ^^#render_args (%expand [100]) 200) == 300)
    " do
      @application.parse_and_process(example.description)
    end

    it "
      (fn f [b c d]
        ^!eval_arguments
        [b c d]
      )
      (var a 100)
      (fn d x (x * 100))
      (var result
        (f ^^#render_args
          %a
          (:b %c)
          (%d 1)
        )
       )
      +assert (((result .get 1) .type) == :b)
      +assert (((result .get 1) .get 0) == :%c)
      +assert ((result .get 2) == 100)
    " do
      @application.parse_and_process(example.description)
    end

    it "
      (fn f a
        ^!eval_arguments
        a
      )
      +assert (((f ^^#render_args ((%= :a))) .type) == :a)
    " do
      @application.parse_and_process(example.description)
    end

    it "
    " do
      pending "Need a way to escape : and % (maybe prefix with \\ and check escaped)"
      @application.parse_and_process(example.description)
    end
  end

  describe "Eval" do
    it "
      +assert ((eval 1) == 1)
    " do
      @application.parse_and_process(example.description)
    end

    it "
      +assert ((eval 1 2) == 2)
    " do
      @application.parse_and_process(example.description)
    end

    it "
      (var a 1)
      +assert ((eval :a) == 1)
    " do
      @application.parse_and_process(example.description)
    end

    it "
      (var a 1)
      (var b :a)
      +assert ((eval (eval :b)) == 1)
    " do
      @application.parse_and_process(example.description)
    end
  end

  describe "Range" do
    it "
      +assert ($invoke (1 .. 2) 'include?' 1)
    " do
      @application.parse_and_process(example.description)
    end
  end
end

