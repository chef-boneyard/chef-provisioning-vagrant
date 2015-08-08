describe "Chef::Provisioning::Vagrant" do
  include_context "run with driver", :driver_string => "vagrant"

  with_chef_server do
    context "the test environment" do
      let(:let_var) { "a let variable in the enclosing context"}

      it "can use a Vagrant resource" do
        expect_converge {
          vagrant_box "should load the resource with no errors" do
            action :nothing
          end
        }.not_to raise_error
      end

      it "can use a let variable in a recipe" do
        expect_converge {
          log "should be able to use let_var as '#{let_var}' with no error."
        }.not_to raise_error
      end

      it "has access to the driver object" do
        expect(provisioning_driver.driver_url).to start_with("vagrant:")
      end

      it "has a running Chef-Zero server available" do
        expect_recipe {
          chef_data_bag "spec-#{Time.now.to_i}" do
            action :delete
          end
        }.to be_truthy
      end
    end
  end
end
