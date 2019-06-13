class ManageIQ::Providers::EmbeddedAnsible::AutomationManager::Credential < ManageIQ::Providers::EmbeddedAutomationManager::Authentication
  # Authentication is associated with EMS through resource_id/resource_type
  # Alias is to make the AutomationManager code more uniformly as those
  # CUD operations in the TowerApi concern

  alias_attribute :manager_id, :resource_id
  alias_attribute :manager, :resource

  COMMON_ATTRIBUTES = {}.freeze
  EXTRA_ATTRIBUTES = {}.freeze
  API_ATTRIBUTES = COMMON_ATTRIBUTES.merge(EXTRA_ATTRIBUTES).freeze

  FRIENDLY_NAME = "Ansible Automation Inside Credential".freeze

  include ManageIQ::Providers::EmbeddedAnsible::CrudCommon

  def self.provider_params(params)
    super.merge(:organization => ManageIQ::Providers::EmbeddedAnsible::AutomationManager.first.provider.default_organization)
  end

  def self.params_to_attributes(_params)
    raise NotImplementedError, "must be implemented in a subclass"
  end

  def self.raw_create_in_provider(_manager, params)
    create!(params_to_attributes(params))
  end

  # Since credentials don't require any external resources, and should just be
  # creating a single database record, stub the queue work requested by the UI,
  # and just call the `raw` methods directly.
  #
  # TODO:  Update UI to not require the queue for credential creation
  #
  def self.create_in_provider_queue(manager_id, params, _auth_user = nil)
    parent.find(manager_id) # validate manager
    raw_create_in_provider(nil, params)
  end

  def update_in_provider_queue(params, _auth_user = nil)
    raw_update_in_provider(params)
  end

  def delete_in_provider_queue(_auth_user = nil)
    raw_delete_in_provider
  end

  def raw_update_in_provider(params)
    update!(self.class.params_to_attributes(params.except(:task_id, :miq_task_id)))
  end

  def raw_delete_in_provider
    destroy!
  end

  def native_ref
    Integer(manager_ref)
  end
end
