module Gene
  module Handlers
    class ComplexStringHandler
      COMPLEX_STRING1 = Gene::Types::Symbol.new('#""')
      COMPLEX_STRING2 = Gene::Types::Symbol.new("#''")

      def initialize
        @logger = Logem::Logger.new(self)
      end

      def call context, data
        return Gene::NOT_HANDLED unless
          data.is_a? Gene::Types::Base and
          (data.type == COMPLEX_STRING1 or data.type == COMPLEX_STRING2)

        @logger.debug('call', data)

        Gene::Types::ComplexString.new *data.data
      end
    end
  end
end
