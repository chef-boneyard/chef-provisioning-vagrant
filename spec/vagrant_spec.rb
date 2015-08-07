describe "Chef::Provisioning::Vagrant" do
  include_context "run with driver", :driver_string => "vagrant"

  when_the_chef_12_server "exists", server_scope: :context, port: 8900..9000 do
    context "machine resource" do
      let(:let_var) { "a let variable in the enclosing context"}

      it "uses a Vagrant resource and a let variable" do
        expect_converge {
          vagrant_box "should load the resource with no errors" do
            action :nothing
          end

          log "should be able to use let_var as '#{let_var}' with no error."
        }.not_to raise_error
      end
    end
  end
end
