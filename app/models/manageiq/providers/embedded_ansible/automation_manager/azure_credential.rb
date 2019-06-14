class ManageIQ::Providers::EmbeddedAnsible::AutomationManager::AzureCredential < ManageIQ::Providers::EmbeddedAnsible::AutomationManager::CloudCredential
  COMMON_ATTRIBUTES = {
    :userid   => {
      :label     => N_('Username'),
      :help_text => N_('The username to use to connect to the Microsoft Azure account')
    },
    :password => {
      :type      => :password,
      :label     => N_('Password'),
      :help_text => N_('The password to use to connect to the Microsoft Azure account')
    }
  }.freeze

  EXTRA_ATTRIBUTES = {
    :subscription => {
      :type       => :string,
      :label      => N_('Subscription ID'),
      :help_text  => N_('The Subscription UUID for the Microsoft Azure account'),
      :max_length => 1024,
      :required   => true
    },
    :tenant       => {
      :type       => :string,
      :label      => N_('Tenant ID'),
      :help_text  => N_('The Tenant ID for the Microsoft Azure account'),
      :max_length => 1024
    },
    :secret       => {
      :type       => :password,
      :label      => N_('Client Secret'),
      :help_text  => N_('The Client Secret for the Microsoft Azure account'),
      :max_length => 1024,
    },
    :client       => {
      :type       => :string,
      :label      => N_('Client ID'),
      :help_text  => N_('The Client ID for the Microsoft Azure account'),
      :max_length => 128
    },
  }.freeze

  API_ATTRIBUTES = COMMON_ATTRIBUTES.merge(EXTRA_ATTRIBUTES).freeze

  API_OPTIONS = {
    :type       => 'cloud',
    :label      => N_('Azure'),
    :attributes => API_ATTRIBUTES
  }.freeze

  alias_attribute :secret, :auth_key

  def self.display_name(number = 1)
    n_('Credential (Microsoft Azure)', 'Credentials (Microsoft Azure)', number)
  end

  def self.params_to_attributes(params)
    attrs = params.reverse_merge(:options => {})

    attrs[:options][:client]       = attrs.delete(:client)
    attrs[:options][:tenant]       = attrs.delete(:tenant)
    attrs[:options][:subscription] = attrs.delete(:subscription)

    attrs
  end

  def self.notification_excludes
    super + [:secret]
  end
  private_class_method :notification_excludes

  def client
    options[:client]
  end

  def tenant
    options[:tenant]
  end

  def subscription
    options[:subscription]
  end
end
