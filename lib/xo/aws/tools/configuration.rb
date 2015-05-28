require_relative './errors'

module XO
  module AWS
    module Tools
      module VpcCreator
        include Errors
        class Configuration

          VALID_OPTIONS = [:cidr, :name, :num_availability_zones, :ec2_client, :vpc_id].freeze

          class << self
            VALID_OPTIONS.each do |v|
              attr_accessor v
            end
          end

          attr_accessor(*VALID_OPTIONS)

          def initialize
            test_aws_credentials
          end # initialize

          def self.options
            o = {}
            VALID_OPTIONS.each do |v|
              o.merge!({v => send(v)})
            end
            return o
          end # self.options

          def test_aws_credentials
              begin
                creds = \
                  Aws::SharedCredentials.new(profile_name: 'vpc-creator')
                if creds.access_key_id.nil? || creds.secret_access_key.nil?
                  fail XO::AWS::Tools::VpcCreator::NoSuchProfileError
                end
                @ec2_client = Aws::EC2::Client.new(region: 'us-east-1', credentials: creds)
                #log_output('AWS Credentials found via configuration file ' \
                #  + "profile: #{@access_key_id}", 'info')
                @access_key_id = creds.access_key_id
                @secret_access_key = creds.secret_access_key
              rescue XO::AWS::Tools::VpcCreator::NoSuchProfileError
                #log_output('AWS Credentials not found via profile either, ' \
                #  + 'will try configuration file', 'info')
                if @access_key_id.nil? || @secret_access_key.nil?
                  # We can't find S3 credentials, this is bad!
                  @errors.push 'The AWS access key and/or secret access key ' \
                               + 'appear to be missing, and are required in an ' \
                               + 'AWS Instance Profile named vpc-creator.'
                else
                  #log_output('AWS Credentials found via application configuration ' \
                  #  + "file: #{@access_key_id}", 'info')
                  creds = Aws::Credentials.new(@access_key_id, \
                                               @secret_access_key)
                  @s3 = Aws::EC2::Client.new(region: 'us-east-1', \
                                            credentials: creds)
                end
              end
          end # test_aws_credentials

        end # Config
      end # VpcCreator
    end
  end
end
