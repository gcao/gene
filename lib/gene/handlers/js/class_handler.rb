module Gene
  module Handlers
    module Js
      class ClassHandler
        CLASS = Gene::Types::Symbol.new 'class'

        def initialize
          @logger = Logem::Logger.new(self)
        end

        def call context, data
          return Gene::NOT_HANDLED unless data.is_a? Gene::Types::Base and data.type == CLASS

          @logger.debug('call', data)

          data.shift

          class_name = data.shift.name

<<-JS
class #{class_name}(){
}; #{class_name};
JS
        end
      end
    end
  end
end

