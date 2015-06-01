require 'spec_helper'
require_relative '../../../../../../lib/xo'

describe 'SecurityGroups' do
  before(:all) do
    @secgroup = XO::AWS::Tools::VpcCreator::SecurityGroups
  end

  describe 'reset' do

    it 'should has raw_rules = nil' do
      @secgroup.reset
      expect(@secgroup.raw_rules).to eq nil
    end

    it 'should have a blank rules array' do
      @secgroup.reset
      expect(@secgroup.rules).to be_a(Array)
      expect(@secgroup.rules.length).to eq 0
    end
  end

  describe 'read_file' do
    it 'should not throw errors' do
      #'../../../../../assets/secGroups.json'
      expect{ @secgroup.read_file('spec/assets/secGroups.json') }\
        .not_to raise_error
    end

    it 'should have non-nil rules instance variable' do
      @secgroup.read_file('spec/assets/secGroups.json')
      expect(@secgroup.rules).not_to be nil
      expect(@secgroup.rules).to be_a(Array)
    end
  end

  describe 'process_rules' do
    it 'should not throw errors' do
      expect{ @secgroup.read_file('spec/assets/secGroups.json') }\
        .not_to raise_error
      expect{ @secgroup.process_rules }.not_to raise_error
    end

    it 'should have more than one rule' do
      expect{ @secgroup.read_file('spec/assets/secGroups.json') }\
        .not_to raise_error
      expect{ @secgroup.process_rules }.not_to raise_error
      expect( @secgroup.rules.length).to be > 0
    end
  end
end
