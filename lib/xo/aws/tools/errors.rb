module XO
  module AWS
    module Tools
      module VpcCreator
        module Errors
          class NoSuchProfileError < StandardError ; end
          class ValidationError < StandardError; end
        end
      end
    end
  end
end
