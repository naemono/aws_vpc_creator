require 'netaddr'
require 'aws-sdk'
require 'json'
require_relative './configuration'
require_relative './vpc_creator/client'
require_relative './vpc_creator/security_groups'
require_relative './errors'

module XO
  module AWS
    module Tools
      module VpcCreator
        class << self

          @client, @configuration = nil

          def initialize
          end # initialize

          def client(options={})
            @client ? @client : @client = Client.new(options)
          end # client

          def reset_client
            @client.reset if @client
            @client = nil
          end # reset_client

          # The configuration object.
          def configuration
            @configuration ||= Configuration.new
          end # configuration

          def configure
            yield(configuration) if block_given?
          end # configure

        end # class
      end # module
    end # module
  end # module
end # module
