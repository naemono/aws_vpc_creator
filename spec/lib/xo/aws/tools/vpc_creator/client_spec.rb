require 'spec_helper'
require 'netaddr'
require_relative '../../../../../../lib/xo'

describe "VpcCreator-Client" do
  before(:all) do
    XO::AWS::Tools::VpcCreator.configure do |c|
      c.cidr = '172.27.0.0/18'
      c.name = 'test-vpc-creator'
      c.num_availability_zones = 3
    end
  end

  describe '#initialize' do
    let(:client) { XO::AWS::Tools::VpcCreator.client }

    it 'has valid instance variables' do

      expect(client.cidr).to eq '172.27.0.0/18'
      expect(client.name).to eq 'test-vpc-creator'
      expect(client.num_availability_zones).to eq 3
      expect(client.ec2_client).not_to be nil
    end
  end

  describe 'create_vpc' do
    let(:client) { XO::AWS::Tools::VpcCreator.client }
    let(:response) { client.create_vpc({:dry_run => true}) }

    it 'should return success' do
      expect(response).to include(:success => true)
    end

    it 'should have a valid vpc_id' do
      expect(client.vpc_id).to eq '1234567890'
    end

  end

  describe 'delete_vpc' do
  end

  describe 'vpc_ready?' do
    let(:client) { XO::AWS::Tools::VpcCreator.client }
    before(:each) {
      @options_hash =
        {
          dry_run: true
        }
    }

    it 'should fail without vpc_id' do
      client.vpc_id = nil
      expect{ client.vpc_ready? }.to raise_error
    end

    it 'should be ready' do
      vpc_response = client.ec2_client.describe_vpcs({})
      if vpc_response.successful?
        id = vpc_response.data.vpcs[0].vpc_id
        client.vpc_id = id
        response = client.vpc_ready?(@options_hash)
        expect(response).to eq true
      end
    end
  end

  describe 'create_subnet' do
    let(:client) { XO::AWS::Tools::VpcCreator.client }
    before(:each) {
      @options_hash =
        {
          availability_zone: 'us-east-1a',
          cidr_block: '172.16.0.0/12',
          public: true,
          dry_run: true
        }
    }

    it 'should fail without cidr_block' do
      client.vpc_id = '1234567890'
      expect{ client.create_subnet(@options_hash.delete(:cidr_block)) }.to \
        raise_error
    end

    it 'should fail without vpc_id' do
      client.vpc_id = nil
      expect{ client.create_subnet@options_hash.delete(:vpc_id) }.to \
        raise_error
    end

    it 'should fail without public' do
      client.vpc_id = '1234567890'
      expect{ client.create_subnet@options_hash.delete(:public) }.to \
        raise_error
    end

    it 'should fail without availability_zone' do
      client.vpc_id = '1234567890'
      expect{ client.create_subnet(
        @options_hash.delete(:availability_zone)) }.to raise_error
    end

  end

  describe 'create_key_pair' do
    let(:client) { XO::AWS::Tools::VpcCreator.client }
    before(:each) {
      @options_hash =
      {
        dry_run: true
      }
      @random_key_name = 'test-key-' + rand(2**256).to_s(36)[0..7]
    }

    it 'should fail without a name' do
      expect{ client.create_key_pair(nil, @options_hash)}.to raise_error
    end

    it 'should succeed' do
      response = client.create_key_pair(@random_key_name, @options_hash)
      expect(response).to include(:success => true)
    end
  end

  describe 'create_security_group' do
    let(:client) { XO::AWS::Tools::VpcCreator.client }
    before(:each) {
      @options_hash =
      {
        dry_run: true
      }
      @random_group_name = 'test-key-' + rand(2**256).to_s(36)[0..7]
    }

    it 'should fail without a name' do
      expect{ client.create_security_group(nil, 'test', @options_hash)}.to raise_error
    end

    it 'should fail without a description' do
      expect{ client.create_security_group('test', nil, @options_hash)}.to raise_error
    end

    it 'should succeed' do
      response = client.create_security_group(@random_group_name,
        'test security group', @options_hash)
      expect(response).to include(:success => true)
    end
  end

  describe 'authorize_security_group' do
    let(:client) { XO::AWS::Tools::VpcCreator.client }
    before(:each) {
      @options_hash =
      {
        dry_run: true,
        cidr: '0.0.0.0/0'
      }
      @ty = 'ingress'
      @id = ''
      @pr = 'tcp'
      @f = 22
      @t = 22
    }

    it 'should fail without a type' do
      expect{ client.authorize_security_group(nil,@id,@pr,@f,@t,@options_hash)}.to raise_error
    end

    it 'should fail with an invalid type' do
      expect{ client.authorize_security_group('invalid',@id,@pr,@f,@t,@options_hash)}.to raise_error
    end

    it 'should fail without a protocol' do
      expect{ client.authorize_security_group(@ty,@id,nil,@f,@t,@options_hash)}.to raise_error
    end

    it 'should fail with an invalid protocol' do
      expect{ client.authorize_security_group(@ty,@id,'invalid',@f,@t,@options_hash)}.to raise_error
    end

    it 'should fail without a group id' do
      expect{ client.authorize_security_group(@ty,nil,@pr,@f,@t,@options_hash)}.to raise_error
    end

    it 'should fail without a from port' do
      expect{ client.authorize_security_group(@ty,@id,@pr,nil,@t,@options_hash)}.to raise_error
    end

    it 'should fail without a to port' do
      expect{ client.authorize_security_group(@ty,@id,@pr,@f,nil,@options_hash)}.to raise_error
    end

    it 'should fail without a cidr' do
      expect{ client.authorize_security_group(@ty,@id,@pr,@f,@t,@options_hash.delete(:cidr))}.to raise_error
    end

    it 'should fail with an invalid cidr' do
      @options_hash[:cidr] = 'invalid'
      expect{ client.authorize_security_group(@ty,@id,@pr,@f,@t,@options_hash)}.to raise_error
    end

    it 'should succeed' do
      group_response = client.ec2_client.describe_security_groups(
        {group_names: ['default']})
      if group_response.successful?
        id = group_response.data.security_groups[0].group_id
        response = client.authorize_security_group(@ty,id,@pr,@f,@t,
          @options_hash)
        expect(response).to include(:success => true)
      end
    end
  end

  describe 'security_group' do
    let(:client) { XO::AWS::Tools::VpcCreator.client }

    it 'should fail without a group name' do
      expect{ client.security_group(nil) }.to raise_error
    end

    it 'should succeed' do
      expect(client.security_group('default')).to be_a(String)
    end
  end

  describe 'process_rules' do
    let(:client) { XO::AWS::Tools::VpcCreator.client }

    before(:each) {
      @options_hash =
      {
        dry_run: true
      }
    }

    it 'should fail' do
    end

    it 'should succeed' do
      group_response = client.ec2_client.describe_security_groups(
        {group_names: ['default']})
      if group_response.successful?
        id = group_response.data.security_groups[0].group_id
        response = client.process_rules('spec/assets/secGroups.json',
          @options_hash)
        expect(response).to be true
      end
    end
  end

  describe 'tag_object' do
    let(:client) { XO::AWS::Tools::VpcCreator.client }

    before(:each) {
      @options_hash =
      {
        dry_run: true
      }
      @tags = {
        key: 'Name',
        value: 'test-object'
      }
    }

    it 'should fail when object is missing' do
      expect(client.tag_object(nil, @tags, @options_hash)).to eq false
    end

    it 'should fail when tags is missing' do
      expect(client.tag_object('12345', nil, @options_hash)).to eq false
    end

    it 'should fail when tags is not a hash' do
      expect(client.tag_object('12345', [], @options_hash)).to eq false
    end

    it 'should fail when tags is not a hash' do
      expect(client.tag_object('12345', {key: 'test', fail: 'fail'},
        @options_hash)).to eq false
    end

    it 'should succeed' do
      group_response = client.ec2_client.describe_security_groups(
        {group_names: ['default']})
      if group_response.successful?
        id = group_response.data.security_groups[0].group_id
        response = client.tag_object(id,@tags,@options_hash)
        expect(response).to eq true
      end
    end
  end

  describe 'create_vpc_subnets' do
    let(:client) { XO::AWS::Tools::VpcCreator.client }

    before(:each) {
      @options_hash =
      {
        dry_run: true
      }
    }

    it 'should fail if num_availability_zones is not defined' do
      client.num_availability_zones = nil
      expect{ client.create_vpc_subnets(options_hash) }.to raise_error
    end

    it 'should return success' do
      client.num_availability_zones = 3
      vpc_response = client.ec2_client.describe_vpcs({})
      if vpc_response.successful?
        id = vpc_response.data.vpcs[0].vpc_id
        client.vpc_id = id
        response = client.create_vpc_subnets(@options_hash)
        expect(response).to eq true
      end
    end

  end

  describe 'generate_child_subnets' do
    let(:client) { XO::AWS::Tools::VpcCreator.client }

    it 'should return an array > 0' do
      response = client.generate_child_subnets
      expect(response).to be_a(Array)
      expect(response.length).to be > 0
    end

    it 'should not raise an error and be a valid subnet' do
      response = client.generate_child_subnets
      expect{ NetAddr::CIDR.create(response[0]) }.not_to raise_error
    end

    it 'should return an array length >= num_availability_zones' do
      response = client.generate_child_subnets
      expect(response.length).to be > client.num_availability_zones
    end

  end

end
