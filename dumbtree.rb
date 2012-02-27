module DumbTree
  class TransparentRedirect
    def self.create_customer_hash(user)
      hash = { :customer => { :email => user.email } }
      if (Rails.env.development? || Rails.env.test?)
        hash.merge!(:redirect_url  => "http://localhost:3000/receive")
      else
        hash.merge!(:redirect_url  => ENV['APP_ADDRESS'] + "/receive")
      end
      tr_data = Braintree::TransparentRedirect.create_customer_data(hash)
    end

    def self.update_billing_hash(user)
      hash = { :payment_method_token => user.payment_details.token }
      if (Rails.env.development? || Rails.env.test?)
        hash.merge!(:redirect_url  => "http://localhost:3000/renew")
      else
        hash.merge!(:redirect_url  => ENV['APP_ADDRESS'] + "/renew")
      end
      tr_data = Braintree::TransparentRedirect.update_credit_card_data hash
    end

    def self.confirm(query_string)
      bt_confirmation = Braintree::TransparentRedirect.confirm(query_string)
      new bt_confirmation
    end

    def initialize(bt_confirmation)
      @bt_confirmation = bt_confirmation
    end

    def customer
      @bt_confirmation.customer
    end

    def newest_credit_card
      customer.credit_cards.sort_by {|cc| cc.updated_at}.last
    end

    def plan
      Plan.new(custom_fields[:plan])
    end

    def token
      newest_credit_card.token
    end

    def has_credit_card?
      success? && !customer.credit_cards.empty?
    end
    
    def method_missing(*args, &block)
      @bt_confirmation.send *args, &block
    end 
  end


  class Customer
    def self.find(customer_id)
      customer = Braintree::Customer.find customer_id
      new customer
    end

    def initialize(customer)
      @customer = customer
    end

    def credit_card
      @customer.credit_cards.sort_by {|cc| cc.updated_at}.last
    end

    def subscription
      @customer.credit_cards.first.subscriptions.last
    end

    def first_billing_date
      subscription.first_billing_date
    end

    def next_billing_date
      subscription.next_billing_date
    end

    def next_billing_period_amount
      subscription.next_billing_period_amount
    end

    def billing_period_start_date
      subscription.billing_period_start_date
    end

    def billing_period_end_date
      subscription.billing_period_end_date
    end

    def plan
      subscription.plan_id
    end

    def token
      credit_card.token
    end

    def card_type
      credit_card.card_type
    end

    def last_4
      credit_card.last_4
    end

    def cardholder_name
      credit_card.cardholder_name
    end

    def expired?
      Time.parse(credit_card.expiration_date.to_s).end_of_month < Time.now
    end

    def method_missing(*args, &block)
      @customer.send *args, &block
    end
  end

  class Subscription
    def self.create(options = {})
      subscription = Braintree::Subscription.create options
      new subscription
    end

    def self.cancel(subscription_id)
      subscription = Braintree::Subscription.cancel subscription_id
      new subscription
    end

    def initialize(subscription)
      @subscription = subscription
    end

    def method_missing(*args, &block)
      @subscription.send *args, &block
    end
  end
end