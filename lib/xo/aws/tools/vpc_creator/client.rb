module XO
  module AWS
    module Tools
      module VpcCreator
        include Errors
        class Client

          attr_reader(*Configuration::VALID_OPTIONS)

          def initialize(options={})
            @errors = []
            @logger = Logger.new('vpc-creator.log')
            o = XO::AWS::Tools::VpcCreator::Configuration.options.merge(options)
            Configuration::VALID_OPTIONS.each do |key|
              # calls Client.key = for each Configuration option
              value = XO::AWS::Tools::VpcCreator.configuration.send(key)
              send("#{key}=", value) if !value.nil?
            end
            fail XO::AWS::Tools::VpcCreator::ValidationError,
              @errors.join(', ') unless valid_config?
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

          def valid_config?
          [:cidr, :name, :num_availability_zones].each do |c|
            if instance_variable_get("@#{c}").nil?
              @errors.push("#{c} is required")
            end
          end
          @errors.size > 0 ? false : true
        end # valid_config?

          def check_response(response)
            @logger.info("Checking response: #{response.data}")
            if response.successful?
              return {success: true, errors: []}.merge({response: response.data})
            else
              return {success: false, errors: response.errors}.merge({response: response.data})
            end
          end # check_response

          def check_tag_object(obj, tags)
            errors = []
            errors.push('Missing object') if (obj.nil?)
            errors.push('Missing tags') if (tags.nil?)
            errors.push('Tags must be a Hash') if (!tags.is_a?(Hash))
            errors.push('Tags must contains keys key and value') if
              (!(tags.key?(:key) && tags.key?(:value)))
            return errors
          end # check_tag_object

          def tag_object(obj, tags, options={})
            @logger.info("Tagging object: #{obj}, with these tags: #{tags}")
            errors = check_tag_object(obj, tags)
            raise XO::AWS::Tools::VpcCreator::ValidationError, errors.join(',') if
              (errors.length > 0)
            params = {
              resources: [obj.to_s],
              tags: [ tags ]
            }.merge(options)
            response = @ec2_client.create_tags(params)
            return true
          rescue Aws::EC2::Errors::DryRunOperation => e
            return true
          rescue => e
            puts "Unexpected error while tagging object: #{e.message}, #{e.backtrace}"
            return false
          end # tag_object

          def create_vpc(options={})
            params = {cidr_block: @cidr.to_s, instance_tenancy: 'default'}.merge(options)
            @logger.info("Creating a vpc with these options: #{params}")
            response = @ec2_client.create_vpc(params)
            @vpc_id = response.data.vpc[:vpc_id] if response.successful?
            res = check_response(response)
            name = @name || 'Vpc Creation Tool Created'
            puts "About to tag object with name: #{name} and vpc_id: #{vpc_id}"
            tag_object(@vpc_id, {key: 'Name', value: name})
            return res
          rescue Aws::EC2::Errors::DryRunOperation => e
            @vpc_id ||= '1234567890'
            return {success: true, errors: [], response: 'dry run successful'}
          end # create_vpc

          def delete_vpc(options={})
            raise XO::AWS::Tools::VpcCreator::VpcNotReadyError if !vpc_ready?
            params = {vpc_id: @vpc_id.to_s}.merge(options)
            @logger.info("Deleting a vpc with these options: #{params}")
            response = @ec2_client.delete_vpc(params)
            return check_response(response)
          rescue Aws::EC2::Errors::DryRunOperation => e
            @vpc_id ||= '1234567890'
            return {success: true, errors: [], response: 'dry run successful'}
          end # create_vpc

          def vpc_ready?(options={})
            raise XO::AWS::Tools::VpcCreator::ValidationError,
              'vpc_id must be defined' if (@vpc_id.nil?)
            params = {
              vpc_ids: [@vpc_id]
            }.merge!(options)
            @logger.info("Checking to see if vpc is ready with these options: #{params}")
            response = @ec2_client.describe_vpcs(params)
            print "response: #{response}\n"
            if response.successful? && response.data.vpcs[0].state == 'available'
              return true
            else
              return false
            end
          rescue Aws::EC2::Errors::DryRunOperation => e
            return true
          end #vpc_ready?

          def check_subnet_errors(options={})
            valid_availability_zones = [ 'us-east-1a', 'us-east-1b',
              'us-east-1c', 'us-east-1d', 'us-east-1e', 'us-west-1a',
              'us-west-1b', 'us-west-1c' ].freeze
            valid_public = [true, false].freeze
            errors = []
            errors.push('Missing cidr_block') if (!options.include?(:cidr_block))
            errors.push('Missing public') if (!options.include?(:public))
            errors.push('Public must be true/false') if (!valid_public.include?(options[:public]))
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
            raise XO::AWS::Tools::VpcCreator::VpcNotReadyError \
              if !vpc_ready?(dry_run: options[:dry_run])
            errors = check_subnet_errors(options)
            raise XO::AWS::Tools::VpcCreator::ValidationError, errors.join(',') if
              (errors.length > 0)
            name = options[:public] ? options[:availability_zone] + '-public' :
              options[:availability_zone] + '-private'
            options.delete(:public)
            params = {cidr_block: options[:cidr_block], vpc_id: @vpc_id}.merge(options)
            @logger.info("Creating a subnet with these options: #{params}")
            response = @ec2_client.create_subnet(params)
            puts "create_subnet response: #{response.data.inspect}"
            res = check_response(response)
            tag_object(res[:response][0].subnet_id, {key: 'Name', value: name}) if
              res[:response][0].subnet_id
            return res
          rescue Aws::EC2::Errors::DryRunOperation => e
            @vpc_id ||= '1234567890'
            return {success: true, errors: [], response: 'dry run successful'}
          end #create_subnet

          def create_key_pair(name, options={})
            raise XO::AWS::Tools::VpcCreator::ValidationError, 'Key Name is required' if
              (name.nil?)
            params = {key_name: name}.merge(options)
            @logger.info("Creating a key pair with these options: #{params}")
            response = @ec2_client.create_key_pair(params)
            return check_response(response)
          rescue Aws::EC2::Errors::DryRunOperation => e
            @vpc_id ||= '1234567890'
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
            params = {
              group_name: name,
              description: description,
              vpc_id: @vpc_id
            }.merge(options)
            @logger.info("Creating a security group with these options: #{params}")
            response = @ec2_client.create_security_group(params)
            return check_response(response)
          rescue Aws::EC2::Errors::DryRunOperation => e
            @vpc_id ||= '1234567890'
            return {success: true, errors: [], response: 'dry run successful'}
          end #create_subnet

          def security_group(name)
            raise XO::AWS::Tools::VpcCreator::ValidationError,
              'Name is required' if (name.nil?)
            params = {
              group_names: [],
              filters: [ {name: 'group-name', values: [name]} ]
            }
            response = @ec2_client.describe_security_groups(params)
            if response.successful? && response.data.security_groups.length > 0
              id = response.data.security_groups[0].group_id
              return id
            else
              return nil
            end
          end # security_group

          def security_group_exist?(name)
            id = security_group(name)
            if !id.nil?
              return true
            else
              return false
            end
          end # security_group_exist?

          def check_authorize_security_group(type, id, protocol, from, to, options)
            errors = []
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
            valid_protocols = ['tcp', 'udp', 'all', 'icmp'].freeze
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
            raise XO::AWS::Tools::VpcCreator::VpcNotReadyError \
              if !vpc_ready?(dry_run: options[:dry_run])
            errors = check_authorize_security_group(type, id, protocol, from, to, options)
            raise XO::AWS::Tools::VpcCreator::ValidationError, errors.join(',') if
              errors.length > 0
            params = {}
            protocol = '-1' if protocol.include?('all')

            if options.include? :cidr
              #params.merge!({cidr_ip: options[:cidr]})
              params.merge!({
                group_id: id,
                ip_permissions: [
                  {
                    ip_protocol: protocol,
                    from_port: from,
                    to_port: to,
                    ip_ranges: [
                      {
                        cidr_ip: options[:cidr]
                      }
                    ]
                  }
                ]
              })
              options.delete(:cidr)
            elsif options.include? :sec_group and type.include?('ingress')
              sec_group = security_group(options[:sec_group])
              params.merge!({
                group_id: sec_group,
                ip_permissions: [
                  {
                    ip_protocol: protocol,
                    from_port: from,
                    to_port: to,
                    user_id_group_pairs: [
                      {
                        group_id: id
                      }
                    ]
                  }
                ]
              })
              options.delete(:sec_group)
            elsif options.include? :sec_group and type.include?('egress')
              sec_group = security_group(options[:sec_group])
              params.merge!({
                group_id: id,
                ip_permissions: [
                  {
                    ip_protocol: protocol,
                    from_port: from,
                    to_port: to,
                    user_id_group_pairs: [
                      {
                        group_id: sec_group
                      }
                    ]
                  }
                ]
              })
              options.delete(:sec_group)
            end

            case type
            when 'ingress'
              method = 'authorize_security_group_ingress'
            when 'egress'
              method = 'authorize_security_group_egress'
            else
              raise XO::AWS::Tools::VpcCreator::ValidationError,
                "Type (ingress/egress) is not valid"
            end
            @logger.info("Adding rule to seg group using this method: #{method}"\
              " with these options: #{params}")
            response = @ec2_client.send(method, params)
            return check_response(response)
          rescue Aws::EC2::Errors::DryRunOperation => e
            @vpc_id ||= '1234567890'
            return {success: true, errors: [], response: 'dry run successful'}
          end # authorize_security_group

          def process_rule(rule)
            target = rule['targetSecGroupName']
            type = rule['type']
            protocol = rule['protocol']
            f_port = rule['fromPort']
            t_port = rule['toPort']
            raise XO::AWS::Tools::VpcCreator::ValidationError,
              "Invalid Rule: #{rule}" if (target.nil? ||
              type.nil? || protocol.nil? || f_port.nil? || t_port.nil?)
            return target, type, protocol, f_port, t_port
          end # process_rule

          def process_target(rule)
            ttype = rule['target']['type']
            tdata = rule['target']['data']
            raise XO::AWS::Tools::VpcCreator::ValidationError,
              "Invalid Rule: #{rule}" if (ttype.nil? || tdata.nil?)
            return ttype, tdata
          end # process_target

          def process_rules(file, options={})
            secgroup = XO::AWS::Tools::VpcCreator::SecurityGroups
            secgroup.read_file(file)
            secgroup.process_rules
            @rules = secgroup.rules
            if !@rules.nil?
              while (@rules.length > 0)
                rule = @rules.shift
                (target, type, protocol, f_port, t_port) = process_rule(rule)
                (target_type, target_data) = process_target(rule)
                if (target_type.include?('securityGroup') &&
                  !security_group_exist?(target_data))
                  create_security_group(target_data, target_data, options)
                end
                if (!security_group_exist?(target))
                  create_security_group(target, target, options)
                end
                options_hash = {}
                case target_type
                when 'cidr'
                  options_hash.merge!({ cidr: target_data })
                when 'securityGroup'
                  options_hash.merge!({ sec_group: target_data })
                end
                sec_group_id = security_group(target)
                begin
                  authorize_security_group(type,sec_group_id, protocol, f_port, t_port,
                    options_hash.merge(options))
                rescue Aws::EC2::Errors::InvalidPermissionDuplicate
                  @logger.info('duplicate rule, continuing.')
                  next
                end
              end
            end
            return true

          rescue => e
            puts "Uncaught exception in process_rules: #{e.inspect}\n#{e.message}\n#{e.backtrace}"
            return false
          end # process_rules

          def generate_child_subnets
            for i in @cidr.bits..32
              temp = @cidr.allocate_rfc3531(i)
              return temp if (temp.length >= @num_availability_zones)
            end
            return nil
          end # generate_child_subnets

          def check_create_vpc_subnets
            errors = []
            errors.push("The number of availability zones must be defined") if
              (@num_availability_zones.nil? || @num_availability_zones <= 0)
            return errors
          end # check_create_vpc_subnets

          def create_vpc_subnets(options={})
            raise XO::AWS::Tools::VpcCreator::VpcNotReadyError \
              if !vpc_ready?(dry_run: options[:dry_run])
            errors = check_create_vpc_subnets
            raise XO::AWS::Tools::VpcCreator::ValidationError, errors.join(',') if
              errors.length > 0
            subnets = generate_child_subnets
            raise XO::AWS::Tools::VpcCreator::ValidationError,
              'Subnets generated was not valid' if (subnets.nil?)
            valid_availability_zones = {
              'us-east-1' => [
                'us-east-1a', 'us-east-1b',
                  'us-east-1c', 'us-east-1d', 'us-east-1e'
              ],
              'us-west-1' => [
                'us-west-1a','us-west-1b', 'us-west-1c'
              ]
            }
            az = @ec2_client.config.sigv4_region
            current_az = valid_availability_zones[az][0]
            raise XO::AWS::Tools::VpcCreator::ValidationError,
              'Couldn\'t find availability zone from region' if current_az.nil?
            subnets.each_with_index do |subnet, i|
              if i % 2 == 0
                options.merge!({cidr_block: subnet.to_s,
                               public: true,
                               availability_zone: current_az})
              else
                options.merge!({cidr_block: subnet.to_s,
                               public: false,
                               availability_zone: current_az})
                current_az =
                  valid_availability_zones[az][valid_availability_zones[az]
                  .index(current_az)+1]
              end
              response = create_subnet(options)
              if (!(response.key?(:success) && response[:success]))
                return false
              end
            end
            return true
          rescue Aws::EC2::Errors::DryRunOperation => e
            return true
          end # create_vpc_subnets

        end # Client
      end # VpcCreator
    end # Tools
  end # AWS
end # XO
