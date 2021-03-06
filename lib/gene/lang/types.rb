module Gene::Lang
  # All objects other than literals have this structure
  # type: a short Symbol to help identify type of the object
  # properties: Hash
  #   ...
  # data: literal or array or anything else
  #
  # type is stored in properties with key '#type'
  # data is stored in properties with key '#data'
  # class is stored in properties with key '#class'
  class Object
    attr_accessor :properties

    def initialize klass = Object
      @properties = {}
      @klass      = klass
    end

    def class
      @klass
    end

    def class= klass
      @klass = klass
    end

    def type
      get('#type') or self.class
    end

    def type= type
      set('#type', type)
    end

    def get name
      if name.is_a? String
        @properties[name]
      else
        data[name]
      end
    end
    alias [] get

    def set name, value
      @properties[name] = value
    end
    alias []= set

    # Return #data - should always be an array or undefined
    def data
      @properties['#data']
    end

    def data= data
      set '#data', data
    end

    def as klass
      obj = Object.new klass
      obj.properties = @properties
      obj
    end

    def == other
      self.class      == other.class      and
      self.properties == other.properties
    end

    # This is part of FFI.
    # It enables methods defined in Gene to be directly invoked from Ruby.
    # Not supported: keyword arguments
    def method_missing method_name, *args
      hierarchy = Gene::Lang::Jit::HierarchySearch.new(self.class.ancestors)
      method = hierarchy.get_method(method_name.to_s)
      VirtualMachine.new.process_function method, args, self: self
    end

    def to_s
      parts = []
      type =
        if self.type
          self.type.to_s
        elsif self.class
          self.class.to_s
        else
          "Object"
        end
      parts << type.sub(/^Gene::Lang::/, '')

      @properties.each do |name, value|
        next if name.to_s =~ /^\$/
        next if %W(#type #class #data).include? name.to_s
        next if properties_to_hide.include? name.to_s

        if value == true
          parts << "^^#{name}"
        elsif value == false
          parts << "^!#{name}"
        elsif value.is_a? Object
          parts << "^#{name}" << value.to_s_short
        elsif value.class.name == "Array"
          parts << "^#{name}"
          if value.empty?
            parts << "[]"
          else
            parts << "[...]"
          end
        elsif value.class.name == "Hash"
          parts << "^#{name}"
          if value.empty?
            parts << "{}"
          else
            parts << "{...}"
          end
        else
          parts << "^#{name}" << value.inspect
        end
      end

      if @properties.include? "#data"
        parts += @properties["#data"].map(&:to_s)
      end

      "(#{parts.join(' ')})"
    end
    alias inspect to_s

    def to_s_short
      type = self.class ? self.class.name : Object.name
      type = type.sub(/^Gene::Lang::/, '')
      "(#{type}...)"
    end

    def properties_to_hide
      []
    end

    def self.attr_reader *names
      names.each do |name|
        name = name.to_s
        define_method(name) do
          @properties[name.to_s]
        end
      end
    end

    def self.attr_accessor *names
      names.each do |name|
        name = name.to_s
        define_method(name) do
          @properties[name]
        end
        define_method("#{name}=") do |value|
          @properties[name] = value
        end
      end
    end

    def self.handle_method options
      context      = options[:context]
      object_class = context.get_member('Object')
      method_name  = options[:method]
      method       = object_class.method(method_name)
      if method
        method.call options
      else
        _self      = options[:self]
        args       = options[:arguments]
        if args.is_a? Gene::Lang::Object
          _self.send method_name, *args.data
        else
          _self.send method_name, *args
        end
      end
    end

    def self.from_gene_base base_object
      obj = new
      obj.properties = base_object.properties.clone
      obj.set '#type', base_object.type
      obj.data = base_object.data.clone
      obj
    end

    def self.from_array_and_properties data, properties = {}
      obj = new
      obj.data = data || []
      properties.each do |key, value|
        if not %w(#type #data).include? key
          obj.set key, value
        end
      end
      obj
    end
  end

  class ExceptionWrapper < Exception
    attr :wrapped_exception

    def initialize exception
      @wrapped_exception = exception
    end

    def to_s
      @wrapped_exception.get('message')
    end
  end

  class Application < Object
    attr_accessor :global_namespace

    def initialize
      super(Application)
      # set 'global_namespace', Gene::Lang::Namespace.new('global', nil)
      set 'global_namespace', Gene::Lang::Scope.new(nil, false)
    end

    def create_root_context
      context = Context.new
      context.application = self
      context.global_namespace = global_namespace
      # Create an anonymous namespace
      # context.self = context.namespace = Gene::Lang::Namespace.new(nil, global_namespace)
      context.self = context
      context.scope = Gene::Lang::Scope.new(nil, false)
      context
    end

    def parse_and_process code, options = {}
      context = create_root_context
      context.define '__DIR__',  options[:dir]
      context.define '__FILE__', options[:file]
      interpreter = Gene::Lang::Interpreter.new context
      interpreter.parse_and_process code
    end

    def load file
      dir = File.dirname(file)
      parse_and_process File.read(file), dir: dir, file: file
    end

    def load_core_libs
      load File.dirname(__FILE__) + '/core.gene'
    end
  end

  class Context
    attr_accessor :global_namespace, :namespace, :scope, :self

    def extend options
      new_context             = Context.new
      new_context.application = @application
      new_context.global_namespace = @application.global_namespace
      new_context.namespace   = options[:namespace] || namespace
      new_context.scope       = options[:scope]     || scope
      new_context.self        = options[:self]
      new_context
    end

    def interpreter
      @interpreter ||= Gene::Lang::Interpreter.new self
    end

    def application
      @application
    end

    def application= application
      @application = application
    end

    def get_member name
      if scope && scope.defined?(name)
        scope.get_member name
      elsif namespace && namespace.defined?(name)
        namespace.get_member name
      elsif global_namespace.defined?(name)
        global_namespace.get_member name
      else
        raise "#{name} is not defined."
      end
    end

    def define name, value, options = {}
      # if self.self.is_a? Namespace
      #   self.self.def_member name, value
      # else
        self.scope.set_member name, value, options
      # end
    end

    def set_member name, value
      # if self.self.is_a? Namespace
      #   self.self.set_member name, value
      # elsif self.scope.defined? name
      #   self.scope.let name, value
      # else
      #   self.namespace.set_member name, value
      # end
      self.scope.let name, value
    end

    def set_global name, value
      application.global_namespace.def_member name, value
    end

    def process data
      interpreter.process data
    end

    def process_statements statements
      result = Gene::UNDEFINED
      return result if statements.nil?

      if statements.class.name == "Array"
        statements.each do |stmt|
          result = process stmt
          if (result.is_a?(Gene::Lang::ReturnValue) or
              result.is_a?(Gene::Lang::BreakValue))
            break
          end
        end
      else
        result = process statements
      end

      result
    end
  end

  # Module is like Class, except it doesn't include init and parent class
  # TODO: support aspects - before, after, when - works like  before -> when -> method -> when -> after
  # TODO: support meta programming - method_added, method_removed, method_missing
  # TODO: support meta programming - module_created, module_included
  # TODO: Support prepend like how Ruby does
  class Module < Object
    attr_accessor :name, :methods, :prop_descriptors, :modules
    attr_accessor :scope

    def initialize name
      super(Class)
      set 'name', name
      set 'methods', {}
      set 'prop_descriptors', {}
      set 'modules', []
    end

    def properties_to_hide
      %w()
    end

    def method name
      methods[name]
    end

    # include myself
    def ancestors
      return @ancestors if @ancestors

      @ancestors = [self]
      modules.each do |mod|
        @ancestors += mod.ancestors
      end
      @ancestors
    end

    # BEGIN: Implement Namespace-like interface
    def defined? name
      scope.defined? name
    end

    def get_member name
      scope.get_member name
    end

    def def_member name, value
      scope.def_member name, value
    end

    def set_member name, value, options
      scope.set_member name, value, options
    end

    def members
      scope.variables
    end
    # END

    def handle_method options
      method_name = options[:method]
      m = method(method_name)
      if m
        m.call options
      else
        hierarchy = options[:hierarchy]
        next_class_or_module = hierarchy.next
        if next_class_or_module
          next_class_or_module.handle_method options
        else
          #TODO: throw error or invoke method_missing
          raise "Undefined method #{method} for #{options[:self]}"
        end
      end
    end
  end

  # TODO: change to single inheritance and include modules like Ruby
  # TODO: support meta programming - class_created, class_extended
  class Class < Module
    attr_accessor :parent_class

    def initialize name
      super(name)
      self.class = Class
    end

    def parent_class
      return nil if self == Gene::Lang::Object

      get('parent_class') || Gene::Lang::Object
    end

    # include myself
    def ancestors
      return @ancestors if @ancestors

      @ancestors = [self]
      modules.each do |mod|
        @ancestors += mod.ancestors
      end
      if parent_class
        @ancestors += parent_class.ancestors
      end
      @ancestors
    end
  end

  # An algorithm to lazily calculate a class/module's ancestors hierarchy
  # Create a new array to store the hierarchy
  # Push the class itself to the hierarchy
  # Save the class's parent class and modules in a temporary stack
  # When trying to access next item in the hierarchy
  # Check whether the stack is empty
  # If not, pop up the last item, add to the hierarchy
  # And push the parent class + modules to the end of the stack
  # If the stack is empty, add Object to the hierarchy and mark the hierarchy as complete
  #
  # When do we invalidate the hierarchy?
  # Each class/module store a number that represents number of modifications
  # When hierarchy is calculated, the number is cached
  # Increment modifications when the class/module is extended, included, unincluded
  # If the cached number is smaller than the current modification number, it should be re-calculated

  class HierarchySearch < Object
    attr_accessor :hierarchy, :index

    def initialize(hierarchy)
      super(HierarchySearch)
      set 'hierarchy', hierarchy
      set 'index', -1
    end

    def next
      self.index += 1
      hierarchy[self.index]
    end

    def current
      hierarchy[self.index]
    end
  end

  class Function < Object
    attr_reader :name
    attr_accessor :parent_scope, :args_matcher, :statements
    attr_accessor :inherit_scope, :eval_arguments

    # TODO: when eval_arguments is true, call render on the arguments against caller context
    # Otherwise it won't be possible to pass any dynamic data to the function
    # E.g. (fn f a ^!eval_arguments a)
    # (var a 1) (f a)  => returns a
    # (var a 1) (f %a) => returns 1

    def initialize name
      super(Function)
      set 'name', name
      self.inherit_scope  = true # Default inherit_scope to true
      self.eval_arguments = true # Default eval_arguments to true
    end

    def call options = {}
      scope = Scope.new parent_scope, inherit_scope
      context = options[:context]

      scope.set_member '$method', options[:method] if options[:method]
      scope.set_member '$hierarchy', options[:hierarchy] if options[:hierarchy]

      scope.set_member '$function', self
      scope.set_member '$caller_context', context
      scope.set_member '$arguments', options[:arguments]
      scope.arguments = Gene::Lang::ArgumentsScope.new options[:arguments], self.args_matcher

      new_context = context.extend scope: scope, self: options[:self]
      result = new_context.process_statements statements
      if result.is_a? ReturnValue
        result = result.value
      end
      result
    end

    def bind target
      BoundFunction.new self, target
    end
  end

  class BoundFunction < Object
    attr_reader :function, :self

    def initialize function, _self
      super(BoundFunction)
      set 'function', function
      set 'self', _self
    end

    def inherit_scope
      function.inherit_scope
    end

    def eval_arguments
      function.eval_arguments
    end

    def call options = {}
      options[:self] = self.self
      function.call options
    end
  end

  class Property < Object
    attr_reader :name, :type, :getter, :setter

    def initialize name
      super(Property)
      set 'name', name
    end
  end

  class PropertyName < Object
    attr_reader :name

    def initialize name
      super(PropertyName)
      set 'name', name
    end
  end

  class Scope < Object
    attr_accessor :parent, :variables, :arguments, :inherit_variables, :ns_members, :exported_members

    def initialize parent, inherit_variables
      super(Scope)
      set 'parent', parent
      set 'inherit_variables', inherit_variables
      set 'variables', {}
      set 'ns_members', []
      set 'exported_members', []
    end

    def defined? name
      if self.variables.keys.include?(name) or (self.arguments and self.arguments.defined?(name))
        return true
      end
      if parent
        if inherit_variables
          parent.defined?(name)
        else
          parent.defined_in_ns?(name)
        end
      end
    end

    def get_member name
      name = name.to_s

      if self.variables.keys.include? name
        self.variables[name]
      elsif self.arguments and self.arguments.defined?(name)
        self.arguments.get_member(name)
      elsif self.parent
        if inherit_variables
          self.parent.get_member name
        else
          self.parent.get_ns_member name
        end
      else
        Gene::UNDEFINED
      end
    end

    def set_member name, value, options = {}
      self.variables[name] = value
      if options[:namespace] and not ns_members.include?(name)
        ns_members << name
      end
      if options[:export]
        if not ns_members.include?(name)
          ns_members << name
        end
        if not exported_members.include?(name)
          exported_members << name
        end
      end
    end
    alias def_member set_member

    def let name, value
      raise "#{name} is not defined." unless self.defined? name

      if self.variables.keys.include? name
        self.variables[name] = value
      elsif self.arguments and self.arguments.defined?(name)
        self.arguments.set_member name, value
      elsif self.parent and self.parent.defined?(name)
        self.parent.let name, value
      else
        self.variables[name] = value
      end
    end

    def defined_in_ns? name
      ns_members.include?(name) or
      (parent and parent.defined_in_ns?(name))
    end

    def get_ns_member name
      name = name.to_s

      if ns_members.include?(name) and self.variables.keys.include? name
        self.variables[name]
      else
        self.parent.get_ns_member name
      end
    end
  end

  class Namespace < Object
    attr_reader :name, :scope

    def initialize name, scope
      super(Namespace)
      set 'name', name
      set 'scope', scope
    end

    def defined? name
      scope.defined? name
    end

    def get_member name
      scope.get_member name
    end

    def def_member name, value
      scope.def_member name, value
    end

    def set_member name, value, options
      scope.set_member name, value, options
    end

    def members
      scope.variables
    end
  end

  # class Namespace < Object
  #   attr_reader :name, :parent, :members, :public_members

  #   def initialize name, parent
  #     super(Namespace)
  #     set 'name', name
  #     set 'parent', parent
  #     set 'members', {}
  #     set 'public_members', []
  #   end

  #   def defined? name
  #     members.include?(name) || (parent && parent.defined?(name))
  #   end

  #   def get_member name
  #     if members.include? name
  #       members[name]
  #     elsif parent
  #       parent.members[name]
  #     end
  #   end

  #   def def_member name, value
  #     members[name] = value
  #     set_access_level name, 'public'
  #   end

  #   def set_member name, value
  #     if members.include? name
  #       members[name] = value
  #     elsif parent
  #       parent.set_member name, value
  #     else
  #       raise "Unknown member '#{name}'"
  #     end
  #   end

  #   def set_access_level name, access_level
  #     if access_level.to_s == 'public'
  #       public_members.push name unless public_members.include? name
  #     elsif access_level.to_s == 'private'
  #       public_members.delete name
  #     end
  #   end

  #   def get_access_level name
  #     public_members.include?(name) ? 'public' : 'private'
  #   end
  # end

  class ArgumentsScope < Object
    attr_accessor :arguments, :matcher

    def initialize arguments, matcher
      super(ArgumentsScope)
      set 'arguments', arguments
      set 'matcher',   matcher
    end

    def defined? name
      matcher and matcher.defined?(name)
    end

    def get_member name
      m = matcher.get_matcher name
      return unless m

      if m.is_a? DataMatcher
        if m.expandable
          arguments.data[m.index .. m.end_index]
        else
          arguments.data[m.index]
        end
      else
        arguments.get m.name
      end
    end

    def set_member name, value
      m = matcher.get_matcher name
      return unless m

      if m.is_a? DataMatcher
        if m.expandable
          arguments.data[m.index .. m.end_index] = value
        else
          arguments.data[m.index] = value
        end
      else
        arguments.set name, value
      end
    end
  end

  class Matcher < Object
    attr_accessor :data_matchers, :prop_matchers

    def self.from_array array
      result = new
      result.from_array array
      result
    end

    def initialize
      super(Matcher)
      set 'data_matchers', []
      set 'prop_matchers', {}
    end

    def defined? name
      prop_matchers[name] or data_matchers.find {|matcher| matcher.name == name }
    end

    def all_matchers
      return @all_matchers if @all_matchers

      @all_matchers = prop_matchers.clone
      data_matchers.each do |matcher|
        @all_matchers[matcher.name] = matcher
      end
      @all_matchers
    end

    def get_matcher name
      all_matchers[name]
    end

    # TODO: support `^arg...`
    # TODO: throw error if optional arguments and expandable arguments are both present.
    def from_array array
      array = [array] unless array.is_a? ::Array

      data_matcher = nil

      index = 0
      while index < array.length
        item = array[index].to_s
        index += 1

        if item == '='
          if data_matcher
            data_matcher.default_value = array[index]
            index += 1
            data_matcher = nil
          else
            raise 'Syntax error: argument name is expected before `=`'
          end

        elsif item =~ /^\^\^(.*)$/
          name = $1
          raise "Name conflict: #{name}" if self.defined? name
          prop_matchers[name] = Gene::Lang::PropMatcher.new name
          data_matcher = nil

        elsif item =~ /^\^(.*)$/
          name = $1
          raise "Name conflict: #{name}" if self.defined? name
          prop_matcher = Gene::Lang::PropMatcher.new name
          prop_matcher.default_value = array[index]
          index += 1
          prop_matchers[name] = prop_matcher
          data_matcher = nil

        else
          if item =~ /^(.*)(\.\.\.)$/
            name       = $1
            expandable = true
          else
            name       = item
            expandable = false
          end
          raise "Name conflict: #{name}" if self.defined? name
          data_matcher = Gene::Lang::DataMatcher.new name
          data_matcher.expandable = expandable
          data_matchers << data_matcher
        end
      end

      calc_indexes
    end

    private

    def calc_indexes
      matchers_size = data_matchers.size
      return if matchers_size == 0

      found_expandable = false

      data_matchers.each_with_index do |matcher, i|
        if matcher.expandable
          found_expandable  = true
          matcher.index     = i
          matcher.end_index = i - matchers_size
        elsif found_expandable
          matcher.index = i - matchers_size
        else
          matcher.index = i
        end
      end
    end
  end

  # [name]
  # [name = 'Default value']
  # [rest...]: default to []
  class DataMatcher < Object
    attr_reader :name
    attr_accessor :index, :end_index, :expandable, :default_value

    def initialize name
      super(DataMatcher)
      set 'name', name
      set 'default_value', Gene::UNDEFINED
    end
  end

  # [^^attr]
  # [^attr 'Default value']
  # [^^attrs...]: default to {}
  class PropMatcher < Object
    attr_reader :name
    attr_accessor :expandable, :default_value

    def initialize name
      super(PropMatcher)
      set 'name', name
      set 'default_value', Gene::UNDEFINED
    end
  end

  class Assignment < Object
    attr_reader :variable, :expression

    def initialize variable, expression = nil
      super(Assignment)
      set 'variable', variable
      set 'expression', expression
    end
  end

  class Variable < Object
    attr_reader :name
    attr_accessor :value

    def initialize name, value = nil
      super(Variable)
      set 'name', name
      set 'value', value
    end
  end

  class ReturnValue < Object
    attr_reader :value

    def initialize value = Gene::UNDEFINED
      super(ReturnValue)
      set 'value', value
    end
  end

  class BreakValue < Object
    attr_reader :value

    def initialize value = Gene::UNDEFINED
      super(BreakValue)
      set 'value', value
    end
  end

  class Expandable < Object
    attr_reader :value

    def initialize value = Gene::UNDEFINED
      super(Expandable)
      set 'value', value
    end
  end

  class Array < ::Array
    def to_s
      "[" + map(&:to_s).join(" ") + "]"
    end
  end

  class Hash < ::Hash
  end

end
