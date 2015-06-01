module XO
  module AWS
    module Tools
      module VpcCreator
        module Errors
          class NoSuchProfileError < StandardError ; end
          class ValidationError < StandardError; end
          class NoSuchFileError < StandardError; end
          class InvalidJSONError < StandardError; end
          class VpcNotReadyError < StandardError; end
          class UnknownError < StandardError; end
        end
      end
    end
  end
end
