describe "Chef::Provisioning::Vagrant" do
  extend VagrantSupport
  # include VagrantConfig   # uncomment to get `chef_config` or to mix in code.

  when_the_chef_12_server "exists", server_scope: :context, port: 8900..9000 do
    with_vagrant "integration tests" do
      context "machine resource" do
        it "doesn't run any tests" do
        end
      end
    end
  end
end
