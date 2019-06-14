class ManageIQ::Providers::EmbeddedAnsible::AutomationManager::VaultCredential < ManageIQ::Providers::EmbeddedAnsible::AutomationManager::Credential
  COMMON_ATTRIBUTES = {}.freeze

  EXTRA_ATTRIBUTES = {
    :vault_password => {
      :type       => :password,
      :label      => N_('Vault password'),
      :help_text  => N_('Vault password'),
      :max_length => 1024
    }
  }.freeze

  API_ATTRIBUTES = COMMON_ATTRIBUTES.merge(EXTRA_ATTRIBUTES).freeze

  API_OPTIONS = {
    :label      => N_('Vault'),
    :type       => 'vault',
    :attributes => API_ATTRIBUTES
  }.freeze

  alias_attribute :vault_password, :password

  def self.display_name(number = 1)
    n_('Credential (Vault)', 'Credentials (Vault)', number)
  end

  def self.params_to_attributes(params)
    params
  end

  def self.notification_excludes
    super + [:vault_password]
  end
  private_class_method :notification_excludes
end
