require 'spec_helper'

class Model < ActiveRecord::Base
  extend Enumify::Model

  enum :status, [:available, :canceled, :completed]
end

class OtherModel < ActiveRecord::Base
  extend Enumify::Model

  belongs_to :model

  enum :status, [:active, :expired, :not_expired]
end

class ModelAllowingNil < ActiveRecord::Base
  self.table_name = 'models'

  extend Enumify::Model

  belongs_to :model

  enum :status, [:active, :expired, :not_expired], :allow_nil => true
end

class ModelWithMethodPrefix < ActiveRecord::Base
  self.table_name = 'locales'

  extend Enumify::Model

  enum :locale, [:en, :es, :fr], :method_prefix => 'loc'
end


describe :Enumify do

  before(:each) do
    Model.delete_all
    OtherModel.delete_all
    ModelWithMethodPrefix.delete_all

    @obj = Model.create!(:status => :available)
    @canceled_obj = Model.create!(:status => :canceled)
    @completed_obj = Model.create!(:status => :completed)

    @active_obj = OtherModel.create!(:status => :active, :model => @obj)
    @expired_obj = OtherModel.create!(:status => :expired, :model => @canceled_obj)
    @not_expired_obj = OtherModel.create!(:status => :not_expired, :model => @canceled_obj)

    @en_obj = ModelWithMethodPrefix.create!(:locale => :en)
    @es_obj = ModelWithMethodPrefix.create!(:locale => :es)
    @fr_obj = ModelWithMethodPrefix.create!(:locale => :fr)
    @obj_with_prefix = ModelWithMethodPrefix.create!(:locale => :fr)
  end

  describe "allow nil" do

    before(:each) do
      @obj_not_allowing_nil = Model.create
      @obj_allowing_nil = ModelAllowingNil.create
    end

    describe "model allowing enum value to be nil" do
      subject { @obj_allowing_nil }
      it "should be valid" do
        subject.should be_valid
      end

      it 'should not raise error when setting value to nil' do
        expect {
          subject.status = nil
        }.to_not raise_error

        subject.status.should be_nil
      end
    end

    describe "model not allowing enum value to be nil" do
      subject { @obj_not_allowing_nil }
      it "should be invalid" do
        subject.should be_invalid
      end

      it 'should not raise error when setting value to nil' do
        expect {
          subject.status = nil
        }.to_not raise_error
        subject.should be_invalid
      end
    end

  end

  describe "short hand methods" do
    describe "question mark (?)" do
      it "should return true if value of enum equals a value" do
        @obj.available?.should be_true
      end

      it "should return false if value of enum is different " do
        @obj.canceled?.should be_false
      end

    end

    describe "exclemation mark (!)" do
      it "should change the value of the enum to the methods value" do
        @obj.canceled!
        @obj.status.should == :canceled
      end

      context 'trying to set the value to the same value' do
        before { @obj.available! }
        it 'should not save the object again' do
          @obj.should_not_receive(:save)
          @obj.available!
        end
      end

    end

    it "should have two shorthand methods for each possible value" do
      Model::STATUSES.each do |val|
        @obj.respond_to?("#{val}?").should be_true
        @obj.respond_to?("#{val}!").should be_true
      end
    end

    describe "with prefix" do
      it "should use prefix" do
        ModelWithMethodPrefix::LOCALES.each do |val|
          @obj_with_prefix.respond_to?("loc_#{val}?").should be_true
          @obj_with_prefix.respond_to?("loc_#{val}!").should be_true
        end
      end

      it "should not respond to unprefixed methods" do
        ModelWithMethodPrefix::LOCALES.each do |val|
          @obj_with_prefix.respond_to?("#{val}?").should be_false
          @obj_with_prefix.respond_to?("#{val}!").should be_false
        end
      end
    end
  end

  describe "getting value" do
    it "should always return the enums value as a symbol" do
      @obj.status.should == :available
      @obj.status = "canceled"
      @obj.status.should == :canceled
    end

    describe "with prefix" do
      it "should not use prefix" do
        @obj_with_prefix.locale.should == :fr
        @obj_with_prefix.locale = :en
        @obj_with_prefix.locale.should == :en
      end
    end

  end

  describe "setting value" do
    it "should except values as symbol" do
      @obj.status = :canceled
      @obj.canceled?.should be_true
    end

    it "should except values as string" do
      @obj.status = "canceled"
      @obj.canceled?.should be_true
    end

    describe "with prefix" do
      it "should not use prefix" do
        @obj_with_prefix.locale = :en
        @obj_with_prefix.loc_en?.should be_true
      end
    end
  end

  describe "validations" do
    it "should not except a value outside the given list" do
      @obj = Model.new(:status => :available)
      @obj.status = :foobar
      @obj.should_not be_valid
    end

    it "should except value in the list" do
      @obj = Model.new(:status => :available)
      @obj.status = :canceled
      @obj.should be_valid
    end
  end

  describe "callbacks" do
    it "should receive a callback on change of value" do
      @obj.should_receive(:status_changed).with(:available,:canceled)
      @obj.canceled!
    end

    it "should not receive a callback on initial value" do
      @obj = Model.new
      @obj.should_not_receive(:status_changed).with(nil, :canceled)
      @obj.canceled!
      end

    it "should not receive a callback on value change to same" do
      @obj.should_not_receive(:status_changed).with(:available, :available)
      @obj.available!
    end

  end

  describe "scopes" do
    it "should return objects with given value" do
      Model.available.should == [@obj]
      Model.canceled.should == [@canceled_obj]
    end

    it "should return objects with given value when joined with models who have the same enum field" do
      OtherModel.joins(:model).active.should == [@active_obj]
    end

    describe "with prefix" do
      it "should use prefix and return objects with given value" do
        ModelWithMethodPrefix.loc_en.should == [@en_obj]
        ModelWithMethodPrefix.loc_es.should == [@es_obj]
      end
    end

    describe "negation scopes" do

      it "should return objects that do not have the given value" do
        Model.not_available.should include(@canceled_obj, @completed_obj)
      end

      it "should return objects that do not have the given value when joined with models who have the same enum field" do
        OtherModel.joins(:model).not_active.should include(@expired_obj, @not_expired_obj)
      end

      it "should not override positive scopes" do
        # We want here to verify that the not_expired scope return only the models with
        # status == "not_expired" and not all the models with status != "expired",
        # since negation scopes should not override the "positive" scopes.
        OtherModel.not_expired.should == [@not_expired_obj]
      end

    end

  end


  it "class should have a CONST that holds all the available options of the enum" do
    Model::STATUSES.should == [:available, :canceled, :completed]
  end

end
