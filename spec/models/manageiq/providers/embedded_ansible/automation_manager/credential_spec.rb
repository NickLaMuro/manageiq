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
      it ".create_in_provider creates a record" do
        expect(credential_class).to receive(:create!).with(params_to_attributes).and_call_original
        expect(Notification).to     receive(:create!).never

        record = credential_class.create_in_provider(manager.id, params)

        expect(record).to be_a(credential_class)
        expected_values.each do |attr, val|
          expect(record.send(attr)).to eq(val)
        end
      end

      it ".create_in_provider_queue just calls raw_create_in_provider" do
        expect(credential_class).to receive(:raw_create_in_provider).with(nil, params).and_call_original

        record = credential_class.create_in_provider_queue(manager.id, params)

        expect(record).to be_a(credential_class)
        expected_values.each do |attr, val|
          expect(record.send(attr)).to eq(val)
        end
      end

      it ".create_in_provider_queue will fail with incompatible manager" do
        wrong_manager = FactoryBot.create(:configuration_manager_foreman)
        expect { credential_class.create_in_provider_queue(wrong_manager.id, params) }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "UPDATE" do
      let(:update_params) { {:name => "Updated Credential" } }
      let(:ansible_cred)  { credential_class.raw_create_in_provider(nil, params.merge(:manager => manager)) }

      it "#update_in_provider to succeed" do
        expect(Notification).to receive(:create!).never

        result = ansible_cred.update_in_provider(update_params)

        expect(result).to be_a(credential_class)
        expect(result.name).to eq("Updated Credential")
      end

      it "#update_in_provider_queue just calls raw_update_in_provider" do
        expect(ansible_cred).to receive(:raw_update_in_provider).with(update_params).and_call_original

        result = ansible_cred.update_in_provider_queue(update_params)

        expect(result).to be_truthy
        expect(ansible_cred.reload.name).to eq("Updated Credential")
      end
    end

    context "DELETE" do
      let(:ansible_cred) { credential_class.raw_create_in_provider(nil, params.merge(:manager => manager)) }

      it "#delete_in_provider will delete the record" do
        expect(Notification).to receive(:create!).never

        result = ansible_cred.delete_in_provider

        expect(result).to be_truthy
        expect { credential_class.find(ansible_cred.id) }.to raise_error ActiveRecord::RecordNotFound
      end

      it "#delete_in_provider_queue just calls raw_delete_in_provider" do
        expect(ansible_cred).to receive(:delete_in_provider_queue).and_call_original

        result = ansible_cred.delete_in_provider_queue

        expect(result).to be_truthy
        expect { credential_class.find(ansible_cred.id) }.to raise_error ActiveRecord::RecordNotFound
      end
    end
  end

  context "MachineCredential" do
    it_behaves_like 'an embedded_ansible credential' do
      let(:credential_class) { embedded_ansible::MachineCredential }

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
          :name              => "Machine Credential",
          :userid            => "userid",
          :password          => "secret1",
          :auth_key          => "secret2",
          :become_password   => "secret3",
          :become_username   => "admin",
          :auth_key_password => "secret4",
          :options           => {
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
          :auth_key_password           => "secret4",
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
      let(:credential_class) { embedded_ansible::NetworkCredential }

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
          :name              => "Network Credential",
          :userid            => "userid",
          :password          => "secret1",
          :auth_key          => "secret2",
          :become_password   => "secret3",
          :auth_key_password => "secret4",
          :options           => {
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
      let(:credential_class) { embedded_ansible::ScmCredential }

      let(:params) do
        {
          :name               => "Scm Credential",
          :userid             => "userid",
          :password           => "secret1",
          :ssh_key_data       => "secret2",
          :ssh_key_unlock     => "secret3"
        }
      end
      let(:params_to_attributes) do
        {
          :name              => "Scm Credential",
          :userid            => "userid",
          :password          => "secret1",
          :auth_key          => "secret2",
          :auth_key_password => "secret3",
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
      let(:credential_class)     { embedded_ansible::VaultCredential }
      let(:params_to_attributes) { params.except(:vault_password).merge(:password => "secret1") }

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
      let(:credential_class)     { embedded_ansible::AmazonCredential }
      let(:params_to_attributes) { params.except(:security_token).merge(:auth_key => "secret2") }

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
end
