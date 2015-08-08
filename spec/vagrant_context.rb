RSpec.shared_context "run with driver" do |driver_args|
  require 'cheffish/rspec/chef_run_support'
  extend Cheffish::RSpec::ChefRunSupport

  include_context "with a chef repo"

  driver_object = Chef::Provisioning.driver_for_url(driver_args[:driver_string])

  let(:provisioning_driver) { driver_object }

  def self.with_chef_server(&block)
    when_the_chef_12_server "is running", server_scope: :context, port: 8900..9000, &block
  end
end
