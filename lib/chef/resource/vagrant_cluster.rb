require 'chef/resource/lwrp_base'
require 'chef/provisioning/vagrant_driver'

class Chef::Resource::VagrantCluster < Chef::Resource::LWRPBase
  self.resource_name = 'vagrant_cluster'

  actions :create, :delete, :nothing
  default_action :create

  attribute :path, :kind_of => String, :name_attribute => true

  def after_created
    super
    run_context.chef_metal.with_driver "vagrant:#{path}"
  end

  # We are not interested in Chef's cloning behavior here.
  def load_prior_resource
    Chef::Log.debug("Overloading #{resource_name}.load_prior_resource with NOOP")
  end
end
