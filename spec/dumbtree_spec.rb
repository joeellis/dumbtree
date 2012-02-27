module Braintree
  module TransparentRedirect
  end
end

describe DumbTree::TransparentRedirect do
  let(:query_string) { stub }
  let(:bt_confirmation) { stub(:success? => true) }
  let(:custom_fields) { {:email => "joe@example.com", :plan => "yearly"} }

  context "when handling transactions for Braintree" do
    before(:each) { Braintree::TransparentRedirect.stub(:confirm).with(query_string).and_return(bt_confirmation) }

    subject { confirmation = DumbTree::TransparentRedirect.confirm(query_string) }

    it "can delegate to the Braintree confirmation result" do
      bt_confirmation.stub :whatever_method => "hey"
      subject.whatever_method.should == "hey"
    end

    it "can delegate to the latest credit card" do
      jan_1, jan_2, jan_3 = [1,2,3].map {|day| Date.new(2011, 1, day) }
      bt_confirmation.stub_chain :customer, :credit_cards => 
        [
          stub(:updated_at => jan_1),
          stub(:updated_at => jan_3),
          stub(:updated_at => jan_2)
        ]
      subject.newest_credit_card.updated_at.should == jan_3
    end

    it "can figure out a plan from the confirmation result" do
      bt_confirmation.stub_chain :customer, :custom_fields => custom_fields
      Plan.should_receive(:new).with("yearly")
      subject.plan
    end

    it "can parse custom fields" do
      bt_confirmation.stub_chain :customer, :custom_fields => custom_fields
      subject.custom_fields.should == custom_fields
    end

    it "can get the credit card's token" do
      bt_confirmation.stub_chain :customer, :credit_cards => [stub(:token => "abcdefg", :updated_at => Time.now)]
      subject.token.should == "abcdefg"
    end

    it "can know if it has a credit card" do
      bt_confirmation.stub_chain :customer, :credit_cards => []
      subject.should_not have_credit_card
    end

    it "cannot have a credit card if not confirmed " do
      bt_confirmation.stub :success? => false
      subject.should_not have_credit_card
    end
  end

  context "when generating data for forms" do
    it "can generate a tr_data hash for creating a Braintree customer" do
      plan = Plan.new "Whatever"
      user = stub :email => "joe@example.com"
      hash = { :customer => { :email => user.email, :custom_fields => { :plan => plan.name } }, :redirect_url => "http://localhost:5000/receive" }
      Braintree::TransparentRedirect.should_receive(:create_customer_data).with(hash)
      DumbTree::TransparentRedirect.create_customer_hash user, plan
    end
  end
end

describe DumbTree::Customer do
  let(:customer_id) { stub }
  let(:customer) { stub }

  context "when handling customers from  Braintree" do
    before { Braintree::Customer.stub(:find).with(customer_id).and_return(customer) }

    subject { customer = DumbTree::Customer.find(customer_id) }

    it "can get a customer's cc info" do
      jan_1, jan_2, jan_3 = [1,2,3].map {|day| Date.new(2011, 1, day) }
      customer.stub :credit_cards => 
        [
          stub(:updated_at => jan_1),
          stub(:updated_at => jan_3),
          stub(:updated_at => jan_2)
        ]
      subject.credit_card.updated_at.should == jan_3
    end

    it "can get a customer's subscription" do
      subscription = stub :plan_id => "plan_name"
      customer.stub :credit_cards => [ stub(:subscriptions => [ subscription ] ) ]
      subject.subscription.should == subscription
    end

    it "can get a customer's first billing date" do
      subscription = stub :first_billing_date => "2012-01-01"
      customer.stub :credit_cards => [ stub(:subscriptions => [ subscription ] ) ]
      subject.first_billing_date.should == "2012-01-01"
    end

    it "can get a customer's next billing date" do
      subscription = stub :next_billing_date => "2012-01-01"
      customer.stub :credit_cards => [ stub(:subscriptions => [ subscription ] ) ]
      subject.next_billing_date.should == "2012-01-01"
    end

    it "can get a customer's billing period start date" do
      subscription = stub :billing_period_start_date => "2012-01-01"
      customer.stub :credit_cards => [ stub(:subscriptions => [ subscription ] ) ]
      subject.billing_period_start_date.should == "2012-01-01"
    end

    it "can get a customer's billing period end date" do
      subscription = stub :billing_period_end_date => "2012-01-01"
      customer.stub :credit_cards => [ stub(:subscriptions => [ subscription ] ) ]
      subject.billing_period_end_date.should == "2012-01-01"
    end

    it "can get a customer's paid through date" do
      subscription = stub :next_billing_period_amount => "$5.00"
      customer.stub :credit_cards => [ stub(:subscriptions => [ subscription ] ) ]
      subject.next_billing_period_amount.should == "$5.00"
    end

    it "can get a customer's card type" do
      customer.stub :credit_cards => [ stub(:card_type => "MasterCard", :updated_at => Time.now) ]
      subject.card_type.should == "MasterCard"
    end

    it "can get the last 4 digits of customer's credit card" do
      customer.stub :credit_cards => [ stub(:last_4 => "1111", :updated_at => Time.now) ]
      subject.last_4.should == "1111"
    end

    it "can get the last 4 digits of customer's credit card" do
      customer.stub :credit_cards => [ stub(:cardholder_name => "John Smith", :updated_at => Time.now) ]
      subject.cardholder_name.should == "John Smith"
    end

    it "can get a customer's plan" do
      customer.stub :credit_cards => [ stub(:subscriptions => [ stub(:plan_id => "plan_name") ] ) ]
      subject.plan.should == "plan_name"
    end

    it "can get a customer's payment_token" do
      customer.stub :credit_cards => [ stub(:token => "abcdefg", :updated_at => Time.now) ]
      subject.token.should == "abcdefg"
    end

    it "can know if a customer's credit card is expired" do
      customer.stub :credit_cards => [ stub(:expiration_date => 1.month.ago, :updated_at => Time.now ) ]
      subject.expired?.should == true

      customer.stub :credit_cards => [ stub(:expiration_date => 1.month.from_now, :updated_at => Time.now ) ]
      subject.expired?.should == false
    end
  end 
end

describe DumbTree::Subscription do
  let(:payment_method_token) { stub }
  let(:plan) { "monthly" }
  let(:subscription) { stub(:success? => true) }
  let(:subscription_id) { stub }

  context "when handling subscriptions from Braintree" do
    context "when creating a subscription" do
      before { Braintree::Subscription.stub(:create).with(:payment_method_token => payment_method_token, :plan_id => plan).and_return(subscription) }

      it "can create a subscription for a customer" do
        subscription = DumbTree::Subscription.create :payment_method_token => payment_method_token, :plan_id => plan
        subscription.success?.should == true
      end
    end

    context "when canceling a subscription" do
      before { Braintree::Subscription.stub(:cancel).with(subscription_id).and_return(subscription) }

      it "can destroy a subscription for a customer" do
        subscription = DumbTree::Subscription.cancel subscription_id
        subscription.success?.should == true
      end
    end
  end 
end