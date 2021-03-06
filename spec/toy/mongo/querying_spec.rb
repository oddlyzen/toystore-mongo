require 'helper'

describe Toy::Mongo::Querying do
  uses_constants('User')

  before(:each) do
    User.identity_map_off
    User.attribute(:name, String)
    User.attribute(:bio, String)
  end

  describe "#query" do
    it "returns a plucky query instance" do
      User.query.should be_instance_of(Plucky::Query)
    end
  end

  Toy::Mongo::Querying::PluckyMethods.each do |name|
    it "delegates ##{name} to #query" do
      query = User.query
      query.should_receive(name)
      User.should_receive(:query).and_return(query)
      User.send(name)
    end
  end

  describe "#atomic_update" do
    before(:each) do
      @user = User.create(:name => 'John')
    end

    it "performs update" do
      @user.atomic_update('$set' => {'name' => 'Frank'})
      @user.reload
      @user.name.should == 'Frank'
    end

    it "defaults to store's :safe option" do
      @user.store.client.should_receive(:update).with(kind_of(Hash), kind_of(Hash), :safe => nil)
      @user.atomic_update('$set' => {'name' => 'Frank'})

      User.store(:mongo, STORE, :safe => false)
      @user.store.client.should_receive(:update).with(kind_of(Hash), kind_of(Hash), :safe => false)
      @user.atomic_update('$set' => {'name' => 'Frank'})

      User.store(:mongo, STORE, :safe => true)
      @user.store.client.should_receive(:update).with(kind_of(Hash), kind_of(Hash), :safe => true)
      @user.atomic_update('$set' => {'name' => 'Frank'})
    end

    context "with :safe option" do
      it "overrides store's :safe option" do
        User.store(:mongo, STORE, :safe => false)
        @user.store.client.should_receive(:update).with(kind_of(Hash), kind_of(Hash), :safe => true)
        @user.atomic_update({'$set' => {'name' => 'Frank'}}, :safe => true)

        User.store(:mongo, STORE, :safe => true)
        @user.store.client.should_receive(:update).with(kind_of(Hash), kind_of(Hash), :safe => false)
        @user.atomic_update({'$set' => {'name' => 'Frank'}}, :safe => false)
      end
    end

    context "with :criteria option" do
      uses_constants('Site')

      it "allows updating embedded documents using $ positional operator" do
        User.attribute(:sites, Array)
        site1 = Site.create
        site2 = Site.create
        @user.update_attributes(:sites => [{'id' => site1.id, 'ui' => 1}, {'id' => site2.id, 'ui' => 2}])

        @user.atomic_update(
          {'$set' => {'sites.$.ui' => 2}},
          {:criteria => {'sites.id' => site1.id}}
        )
        @user.reload
        @user.sites.map { |s| s['ui'] }.should == [2, 2]
      end
    end
  end

  describe "#persistable_changes" do
    before(:each) do
      User.attribute(:password, String, :virtual => true)
      User.attribute(:email, String, :abbr => :e)
      @user = User.create(:name => 'John', :password => 'secret', :email => 'nunemaker@gmail.com')
    end

    it "returns only changed attributes" do
      @user.name = 'Frank'
      @user.persistable_changes.should == {'name' => 'Frank'}
    end

    it "returns typecast values" do
      @user.name = 1234
      @user.persistable_changes.should == {'name' => '1234'}
    end

    it "ignores virtual attributes" do
      @user.password = 'ignore me'
      @user.persistable_changes.should be_empty
    end

    it "uses abbreviated key" do
      @user.email = 'john@orderedlist.com'
      @user.persistable_changes.should == {'e' => 'john@orderedlist.com'}
    end
  end

  describe "#atomic_update_attributes" do
    before(:each) do
      @user = User.create(:name => 'John', :bio => 'I make things simple.')
    end

    it "updates document" do
      @user.atomic_update_attributes(:name => 'Frank')
      @user.reload
      @user.name.should == 'Frank'
    end

    it "returns true if valid" do
      @user.atomic_update_attributes(:name => 'Frank').should be_true
    end

    it "returns false if invalid" do
      User.validates_presence_of(:name)
      @user.atomic_update_attributes(:name => '').should be_false
    end

    it "only persists changes" do
      @user.should_receive(:atomic_update).with('$set' => {'name' => 'Frank'})
      @user.atomic_update_attributes(:name => 'Frank')
    end
  end
end