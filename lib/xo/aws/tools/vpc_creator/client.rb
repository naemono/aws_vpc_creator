module XO
  module AWS
    module Tools
      module VpcCreator
        include Errors
        class Client

          attr_reader(*Configuration::VALID_OPTIONS)

          def initialize(options={})
            o = XO::AWS::Tools::VpcCreator::Configuration.options.merge(options)
            Configuration::VALID_OPTIONS.each do |key|
              # calls Client.key = for each Configuration option
              send("#{key}=", XO::AWS::Tools::VpcCreator.configuration.send(key))
            end
          end # initialize

          def cidr=(cidr)
            begin
              @cidr = NetAddr::CIDR.create(cidr)
            rescue NetAddr::ValidationError => e
              fail XO::AWS::Tools::VpcCreator::ValidationError, "Cidr validation error #{e.message}"
            end
          end

          def name=(name)
            @name = name
          end # name=

          def num_availability_zones=(num)
            @num_availability_zones = num.to_i
          end # num_availability_zones=

          def ec2_client=(client)
            @ec2_client = client
          end # ec2_client

          def vpc_id=(id)
            @vpc_id = id
          end # vpcid=

          def check_response(response)
            if response.successful?
              return {success: true, errors: []}.merge({response: response})
            else
              return {success: false, errors: response.errors}.merge({response: response})
            end
          end # check_response

          def create_vpc(options={})
            params = {cidr_block: @cidr.to_s, instance_tenancy: 'default'}.merge(options)
            response = @ec2_client.create_vpc(params)
            @vpc_id = response.data.vpc[:vpc_id] if response.successful?
            return check_response(response)
          rescue Aws::EC2::Errors::DryRunOperation => e
            @vpc_id = '1234567890'
            return {success: true, errors: [], response: 'dry run successful'}
          end # create_vpc

          def check_subnet_errors(options={})
            valid_availability_zones = [ 'us-east-1a', 'us-east-1b',
              'us-east-1c', 'us-east-1d', 'us-east-1e', 'us-west-1a',
              'us-west-1b', 'us-west-1c' ].freeze
            errors = []
            errors.push('Missing cidr_block') if (!options.include?(:cidr_block))
            errors.push('Provided cidr_block is outside of ' +
              'existing vpc cidr_block') if (options.include?(:cidr_block) &&
              @cidr.cmp(options[:cidr_block]) != 1)
            errors.push('Vpc_id cannot be nil') if
              (@vpc_id.nil?)
            errors.push('Invalid availability_zone') if
              (!options.include? :availability_zone ||
              !valid_availability_zones.include?(options[:availability_zone]))
              return errors
          end #check_subnet_errors

          def create_subnet(options={})
            errors = check_subnet_errors(options)
            raise XO::AWS::Tools::VpcCreator::ValidationError, errors.join(',') if
              (errors.length > 0)
            params = {cidr_block: options[:cidr_block], vpc_id: @vpc_id}.merge(options)
            response = @ec2_client.create_subnet(params)
            return check_response(response)
          rescue Aws::EC2::Errors::DryRunOperation => e
            @vpc_id = '1234567890'
            return {success: true, errors: [], response: 'dry run successful'}
          end #create_subnet

          def create_key_pair(name, options={})
            raise XO::AWS::Tools::VpcCreator::ValidationError, 'Key Name is required' if
              (name.nil?)
            params = {key_name: name}.merge(options)
            response = @ec2_client.create_key_pair(params)
            return check_response(response)
          rescue Aws::EC2::Errors::DryRunOperation => e
            @vpc_id = '1234567890'
            return {success: true, errors: [], response: 'dry run successful'}
          end #create_subnet

          def check_security_group(name, description)
            errors = []
            errors.push('Group Name is required') if (name.nil?)
            errors.push('Group Descdription is required') if (description.nil?)
            return errors
          end #check_subnet_errors

          def create_security_group(name, description, options={})
            errors = check_security_group(name, description)
            raise XO::AWS::Tools::VpcCreator::ValidationError, errors.join(',') if
              errors.length > 0
            params = {group_name: name, description: description}.merge(options)
            response = @ec2_client.create_security_group(params)
            return check_response(response)
          rescue Aws::EC2::Errors::DryRunOperation => e
            @vpc_id = '1234567890'
            return {success: true, errors: [], response: 'dry run successful'}
          end #create_subnet

          def security_group(name)
            raise XO::AWS::Tools::VpcCreator::ValidationError,
              'Name is required' if (name.nil?)
            params = {group_names: [name]}
            response = @ec2_client.describe_security_groups(params)
            if response.successful? && response.data.security_groups.length > 0
              id = response.data.security_groups[0].group_id
              return { success: true, errors: [], response: { group_id: id }}
            else
              return {success: false, errors: ['not found']}
            end
          end

          def check_authorize_security_group(type, id, protocol, from, to, options)
            if options.include? :cidr
              begin
                NetAddr::CIDR.create(options[:cidr])
              rescue NetAddr::ValidationError => e
                errors.push('CIDR is not valid')
              end
            elsif options.include? :sec_group

            else
              errors.push('Either Sec_Group or CIDR is required')
            end

            valid_types = ['ingress', 'egress'].freeze
            valid_protocols = ['tcp', 'udp'].freeze
            errors = []
            errors.push('Type (ingress/egress) is required') if (type.nil?)
            errors.push('Type (ingress/egress) not valid') if (!type.nil? &&
              !valid_types.include?(type))
            errors.push('Security Group id is required') if (id.nil?)
            errors.push('Protocol (tcp/udp) is required') if (protocol.nil?)
            errors.push('Protocol (tcp/udp) not valid') if (!protocol.nil? &&
              !valid_protocols.include?(protocol))
            errors.push('From port is required') if (from.nil?)
            errors.push('To port is required') if (to.nil?)
            return errors
          end

          # needs options[:cidr] or options[:sec_group]
          def authorize_security_group(type, id, protocol, from, to, options={})
            errors = check_authorize_security_group(type, id, protocol, from, to, options)
            raise XO::AWS::Tools::VpcCreator::ValidationError, errors.join(',') if
              errors.length > 0

            params = {}

            if options.include? :cidr
              options.delete(:cidr)
              params.merge!({cidr_ip: options[:cidr]})
            elsif options.include? :sec_group and type.include? 'egress'
              options.delete(:sec_group)
              params.merge!({source_security_group_name: options[:sec_group]})
            end

            params.merge!(
              { dry_run: true, group_id: id, ip_protocol: protocol,
                from_port: from, to_port: to
              })

            case type
            when 'ingress'
              method = 'authorize_security_group_ingress'
            when 'egress'
              method = 'authorize_security_group_egress'
            else
              raise XO::AWS::Tools::VpcCreator::ValidationError,
                "Type (ingress/egress) is not valid"
            end
            response = @ec2_client.send(method, params)
            return check_response(response)
          rescue Aws::EC2::Errors::DryRunOperation => e
            @vpc_id = '1234567890'
            return {success: true, errors: [], response: 'dry run successful'}
          end

        end # Client
      end # VpcCreator
    end # Tools
  end # AWS
end # XO
