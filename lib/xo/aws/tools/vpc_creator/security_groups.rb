module XO
  module AWS
    module Tools
      module VpcCreator
        # Use shift/push to simulate queue
        module SecurityGroups

          @raw_rules = nil
          @rules = []

          def self.rules
            return @rules
          end

          def self.raw_rules
            return @raw_rules
          end

          def self.reset
            @raw_rules = nil
            @rules = []
          end

          def self.read_file(filename)
            raise XO::AWS::Tools::VpcCreator::NoSuchFileError, "#{filename} doesn't exist" if (!File.exist?(filename))
            f = nil
            begin
              f = File.read('secGroups.json')
            rescue => e
              raise XO::AWS::Tools::VpcCreator::UnknownFilesystemError, "Unknown filesystem error #{e.message}"
            end

            begin
              @raw_rules = JSON.parse(f)
            rescue JSON::ParserError => e
              raise InvalidJSONError, "Invalid JSON file"
            rescue => e
              raise XO::AWS::Tools::VpcCreator::UnknownError, "Unkown JSON read error: #{e.message}"
            end
          end # read_file

          def self.process_rules

            @rules = []

            #raise InvalidJSONError, "Invalid JSON file, Mapping section is missing" if @raw_rules['mapping'].nil?
            raise InvalidJSONError, "Invalid JSON file, rules section is missing" if @raw_rules['rules'].nil?

            @raw_rules['rules'].each do |rule|
              # Do some additional processing/verification
              @rules.push(rule)
            end
          end # process_rules

        end # read_file

      end
    end
  end
end
