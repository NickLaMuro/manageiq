describe ManageIQ::Providers::EmbeddedAnsible::AutomationManager::Credential do
  let(:embedded_ansible) { ManageIQ::Providers::EmbeddedAnsible::AutomationManager }
  let(:manager) do
    FactoryBot.create(:provider_embedded_ansible, :default_organization => 1).managers.first
  end

  before do
    EvmSpecHelper.assign_embedded_ansible_role
  end

  context "#native_ref" do
    let(:simple_credential) { described_class.new(:manager_ref => '1', :resource => manager) }

    it "returns integer" do
      expect(simple_credential.manager_ref).to eq('1')
      expect(simple_credential.native_ref).to eq(1)
    end

    it "blows up for nil manager_ref" do
      simple_credential.manager_ref = nil
      expect(simple_credential.manager_ref).to be_nil
      expect { simple_credential.native_ref }.to raise_error(TypeError)
    end
  end

  shared_examples_for "an embedded_ansible credential" do
    let(:base_excludes) { [:password, :auth_key, :service_account] }

    context "CREATE" do
      let(:expected_notify) { notification_args("creation") }

      it ".create_in_provider creates a record and sends a notification" do
        expect(credential_class).to receive(:create!).with(params_to_attributes).and_call_original
        expect(Notification).to     receive(:create!).with(expected_notify)

        record = credential_class.create_in_provider(manager.id, params)

        expect(record).to be_a(credential_class)
        expected_values.each do |attr, val|
          expect(record.send(attr)).to eq(val)
        end
      end

      it ".create_in_provider_queue queues a create task" do
        task_id       = credential_class.create_in_provider_queue(manager.id, params)
        expected_name = "Creating #{described_class::FRIENDLY_NAME} (name=#{params[:name]})"
        expect(MiqTask.find(task_id)).to have_attributes(:name => expected_name)
        expect(MiqQueue.first).to have_attributes(
          :args        => [manager.id, params],
          :class_name  => credential_class.name,
          :method_name => "create_in_provider",
          :priority    => MiqQueue::HIGH_PRIORITY,
          :role        => "embedded_ansible",
          :zone        => manager.my_zone
        )
      end

      it ".create_in_provider_queue will fail with incompatible manager" do
        wrong_manager = FactoryBot.create(:configuration_manager_foreman)
        expect { credential_class.create_in_provider_queue(wrong_manager.id, params) }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "UPDATE" do
      let(:update_params)   { {:name => "Updated Credential" } }
      let(:ansible_cred)    { credential_class.raw_create_in_provider(nil, params.merge(:manager => manager)) }
      let(:expected_notify) { notification_args("update", update_params) }

      it "#update_in_provider to succeed and send notification" do
        expect(Notification).to receive(:create!).with(expected_notify)

        result = ansible_cred.update_in_provider update_params

        expect(result).to be_a(credential_class)
        expect(result.name).to eq("Updated Credential")
      end

      it "#update_in_provider_queue" do
        task_id   = ansible_cred.update_in_provider_queue(update_params)
        task_name = "Updating #{described_class::FRIENDLY_NAME} (name=#{ansible_cred.name})"

        update_params[:task_id] = task_id

        expect(MiqTask.find(task_id)).to have_attributes(:name => task_name)
        expect(MiqQueue.first).to have_attributes(
          :instance_id => ansible_cred.id,
          :args        => [update_params],
          :class_name  => credential_class.name,
          :method_name => "update_in_provider",
          :priority    => MiqQueue::HIGH_PRIORITY,
          :role        => "embedded_ansible",
          :zone        => manager.my_zone
        )
      end
    end

    context "DELETE" do
      let(:ansible_cred)    { credential_class.raw_create_in_provider(nil, params.merge(:manager => manager)) }
      let(:expected_notify) { notification_args("deletion", {}) }

      it "#delete_in_provider will delete the record and send notification" do
        expect(Notification).to receive(:create!).with(expected_notify)
        ansible_cred.delete_in_provider
      end

      it "#delete_in_provider_queue will queue a a delete task" do
        task_id   = ansible_cred.delete_in_provider_queue
        task_name = "Deleting #{described_class::FRIENDLY_NAME} (name=#{ansible_cred.name})"

        expect(MiqTask.find(task_id)).to have_attributes(:name => task_name)
        expect(MiqQueue.first).to have_attributes(
          :instance_id => ansible_cred.id,
          :args        => [],
          :class_name  => credential_class.name,
          :method_name => "delete_in_provider",
          :priority    => MiqQueue::HIGH_PRIORITY,
          :role        => "embedded_ansible",
          :zone        => manager.my_zone
        )
      end
    end

    def notification_args(action, record_params = params)
      op_arg = "(" + record_params.except(*notification_excludes)
                                  .map { |k, v| "#{k}=#{v}" }
                                  .join(', ') + ")"

      {
        :type    => :tower_op_success,
        :options => {
          :op_name => "#{described_class::FRIENDLY_NAME} #{action}",
          :op_arg  => op_arg,
          :tower   => "EMS(manager_id=#{manager.id})"
        }
      }
    end
  end

  context "MachineCredential" do
    it_behaves_like 'an embedded_ansible credential' do
      let(:credential_class)      { embedded_ansible::MachineCredential }
      let(:notification_excludes) { base_excludes + [:ssh_key_data, :ssh_key_unlock] }

      let(:params) do
        {
          :name            => "Machine Credential",
          :userid          => "userid",
          :password        => "secret1",
          :ssh_key_data    => "secret2",
          :become_method   => "sudo",
          :become_password => "secret3",
          :become_username => "admin",
          :ssh_key_unlock  => "secret4"
        }
      end
      let(:params_to_attributes) do
        {
          :name            => "Machine Credential",
          :userid          => "userid",
          :password        => "secret1",
          :ssh_key_data    => "secret2",
          :become_password => "secret3",
          :become_username => "admin",
          :ssh_key_unlock  => "secret4",
          :options         => {
            :become_method => "sudo"
          }
        }
      end
      let(:expected_values) do
        {
          :name                        => "Machine Credential",
          :userid                      => "userid",
          :password                    => "secret1",
          :ssh_key_data                => "secret2",
          :become_password             => "secret3",
          :become_username             => "admin",
          :become_method               => "sudo",
          :ssh_key_unlock              => "secret4",
          :password_encrypted          => ManageIQ::Password.try_encrypt("secret1"),
          :auth_key_encrypted          => ManageIQ::Password.try_encrypt("secret2"),
          :become_password_encrypted   => ManageIQ::Password.try_encrypt("secret3"),
          :auth_key_password_encrypted => ManageIQ::Password.try_encrypt("secret4"),
          :options                     => {
            :become_method => "sudo"
          }
        }
      end
    end
  end

  context "NetworkCredential" do
    it_behaves_like 'an embedded_ansible credential' do
      let(:credential_class)      { embedded_ansible::NetworkCredential }
      let(:notification_excludes) { base_excludes + [:ssh_key_data, :ssh_key_unlock, :authorize_password] }

      let(:params) do
        {
          :name               => "Network Credential",
          :userid             => "userid",
          :password           => "secret1",
          :authorize          => "true",
          :ssh_key_data       => "secret2",
          :authorize_password => "secret3",
          :ssh_key_unlock     => "secret4"
        }
      end
      let(:params_to_attributes) do
        {
          :name               => "Network Credential",
          :userid             => "userid",
          :password           => "secret1",
          :ssh_key_data       => "secret2",
          :authorize_password => "secret3",
          :ssh_key_unlock     => "secret4",
          :options            => {
            :authorize => "true",
          }
        }
      end
      let(:expected_values) do
        {
          :name                        => "Network Credential",
          :userid                      => "userid",
          :password                    => "secret1",
          :authorize                   => "true",
          :ssh_key_data                => "secret2",
          :authorize_password          => "secret3",
          :ssh_key_unlock              => "secret4",
          :password_encrypted          => ManageIQ::Password.try_encrypt("secret1"),
          :auth_key_encrypted          => ManageIQ::Password.try_encrypt("secret2"),
          :become_password_encrypted   => ManageIQ::Password.try_encrypt("secret3"),
          :auth_key_password_encrypted => ManageIQ::Password.try_encrypt("secret4"),
          :options                     => {
            :authorize => "true"
          }
        }
      end
    end
  end

  context "ScmCredential" do
    it_behaves_like 'an embedded_ansible credential' do
      let(:credential_class)      { embedded_ansible::ScmCredential }
      let(:notification_excludes) { base_excludes + [:ssh_key_data, :ssh_key_unlock] }
      let(:params_to_attributes)  { params }

      let(:params) do
        {
          :name               => "Scm Credential",
          :userid             => "userid",
          :password           => "secret1",
          :ssh_key_data       => "secret2",
          :ssh_key_unlock     => "secret3"
        }
      end
      let(:expected_values) do
        {
          :name                        => "Scm Credential",
          :userid                      => "userid",
          :password                    => "secret1",
          :ssh_key_data                => "secret2",
          :ssh_key_unlock              => "secret3",
          :password_encrypted          => ManageIQ::Password.try_encrypt("secret1"),
          :auth_key_encrypted          => ManageIQ::Password.try_encrypt("secret2"),
          :auth_key_password_encrypted => ManageIQ::Password.try_encrypt("secret3")
        }
      end
    end
  end

  context "VaultCredential" do
    it_behaves_like 'an embedded_ansible credential' do
      let(:credential_class)      { embedded_ansible::VaultCredential }
      let(:notification_excludes) { base_excludes + [:vault_password] }
      let(:params_to_attributes)  { params }

      let(:params) do
        {
          :name           => "Vault Credential",
          :vault_password => "secret1"
        }
      end
      let(:expected_values) do
        {
          :name               => "Vault Credential",
          :vault_password     => "secret1",
          :password_encrypted => ManageIQ::Password.try_encrypt("secret1")
        }
      end
    end
  end

  context "AmazonCredential" do
    it_behaves_like 'an embedded_ansible credential' do
      let(:credential_class)      { embedded_ansible::AmazonCredential }
      let(:notification_excludes) { base_excludes + [:security_token] }
      let(:params_to_attributes)  { params }

      let(:params) do
        {
          :name           => "Amazon Credential",
          :userid         => "userid",
          :password       => "secret1",
          :security_token => "secret2",
        }
      end
      let(:expected_values) do
        {
          :name               => "Amazon Credential",
          :userid             => "userid",
          :password           => "secret1",
          :security_token     => "secret2",
          :password_encrypted => ManageIQ::Password.try_encrypt("secret1"),
          :auth_key_encrypted => ManageIQ::Password.try_encrypt("secret2")
        }
      end
    end
  end

  context "AzureCredential" do
    it_behaves_like 'an embedded_ansible credential' do
      let(:credential_class)      { embedded_ansible::AzureCredential }
      let(:notification_excludes) { base_excludes + [:secret] }

      let(:params) do
        {
          :name         => "Azure Credential",
          :userid       => "userid",
          :password     => "secret1",
          :secret       => "secret2",
          :client       => "client",
          :tenant       => "tenant",
          :subscription => "subscription"
        }
      end
      let(:params_to_attributes) do
        {
          :name     => "Azure Credential",
          :userid   => "userid",
          :password => "secret1",
          :secret   => "secret2",
          :options  => {
            :client       => "client",
            :tenant       => "tenant",
            :subscription => "subscription"
          }
        }
      end
      let(:expected_values) do
        {
          :name               => "Azure Credential",
          :userid             => "userid",
          :password           => "secret1",
          :secret             => "secret2",
          :client             => "client",
          :tenant             => "tenant",
          :subscription       => "subscription",
          :password_encrypted => ManageIQ::Password.try_encrypt("secret1"),
          :auth_key_encrypted => ManageIQ::Password.try_encrypt("secret2"),
          :options            => {
            :client       => "client",
            :tenant       => "tenant",
            :subscription => "subscription"
          }
        }
      end
    end
  end

  context "GoogleCredential" do
    it_behaves_like 'an embedded_ansible credential' do
      let(:credential_class)      { embedded_ansible::GoogleCredential }
      let(:notification_excludes) { base_excludes + [:ssh_key_data] }

      let(:params) do
        {
          :name         => "Google Credential",
          :userid       => "userid",
          :ssh_key_data => "secret1",
          :project      => "project"
        }
      end
      let(:params_to_attributes) do
        {
          :name         => "Google Credential",
          :userid       => "userid",
          :ssh_key_data => "secret1",
          :options      => {
            :project => "project"
          }
        }
      end
      let(:expected_values) do
        {
          :name               => "Google Credential",
          :userid             => "userid",
          :ssh_key_data       => "secret1",
          :project            => "project",
          :auth_key_encrypted => ManageIQ::Password.try_encrypt("secret1"),
          :options            => {
            :project => "project"
          }
        }
      end
    end
  end

  context "OpenstackCredential" do
    it_behaves_like 'an embedded_ansible credential' do
      let(:credential_class)      { embedded_ansible::OpenstackCredential }
      let(:notification_excludes) { base_excludes }

      let(:params) do
        {
          :name     => "OpenstackCredential Credential",
          :userid   => "userid",
          :password => "secret1",
          :host     => "host",
          :domain   => "domain",
          :project  => "project"
        }
      end
      let(:params_to_attributes) do
        {
          :name     => "OpenstackCredential Credential",
          :userid   => "userid",
          :password => "secret1",
          :options  => {
            :host    => "host",
            :domain  => "domain",
            :project => "project"
          }
        }
      end
      let(:expected_values) do
        {
          :name               => "OpenstackCredential Credential",
          :userid             => "userid",
          :password           => "secret1",
          :host               => "host",
          :domain             => "domain",
          :project            => "project",
          :password_encrypted => ManageIQ::Password.try_encrypt("secret1"),
          :options            => {
            :host    => "host",
            :domain  => "domain",
            :project => "project"
          }
        }
      end
    end
  end

  context "RhvCredential" do
    it_behaves_like 'an embedded_ansible credential' do
      let(:credential_class)      { embedded_ansible::RhvCredential }
      let(:notification_excludes) { base_excludes }

      let(:params) do
        {
          :name     => "Rhv Credential",
          :userid   => "userid",
          :password => "secret1",
          :host     => "host"
        }
      end
      let(:params_to_attributes) do
        {
          :name     => "Rhv Credential",
          :userid   => "userid",
          :password => "secret1",
          :options  => {
            :host => "host"
          }
        }
      end
      let(:expected_values) do
        {
          :name               => "Rhv Credential",
          :userid             => "userid",
          :password           => "secret1",
          :host               => "host",
          :password_encrypted => ManageIQ::Password.try_encrypt("secret1"),
          :options            => {
            :host => "host"
          }
        }
      end
    end
  end
end
