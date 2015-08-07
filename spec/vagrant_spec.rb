describe "Chef::Provisioning::Vagrant" do
  extend VagrantSupport

  when_the_chef_12_server "exists", server_scope: :context, port: 8900..9000 do
    with_vagrant "integration tests" do
      context "machine resource" do
        let(:let_var) { "a let variable in the enclosing context"}

        it "doesn't run any tests" do
          expect_converge {
            log "should be able to use let_var as '#{let_var}' with no error."
          }.not_to raise_error
        end
      end
    end
  end
end
