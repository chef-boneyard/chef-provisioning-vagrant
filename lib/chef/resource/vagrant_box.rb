require 'chef/resource/lwrp_base'
require 'chef_metal_vagrant'

class Chef::Resource::VagrantBox < Chef::Resource::LWRPBase
  self.resource_name = 'vagrant_box'

  actions :create, :delete, :nothing
  default_action :create

  attribute :name, :kind_of => String, :name_attribute => true
  attribute :url, :kind_of => String
  attribute :driver_options, :kind_of => Hash

  def after_created
    super
    ChefMetalVagrant.with_vagrant_box run_context, self
  end

  # We are not interested in Chef's cloning behavior here.
  def load_prior_resource
    Chef::Log.debug("Overloading #{resource_name}.load_prior_resource with NOOP")
  end
end
