require 'chef/resource/lwrp_base'
require 'chef_metal_vagrant'

class Chef::Resource::VagrantCluster < Chef::Resource::LWRPBase
  self.resource_name = 'vagrant_cluster'

  actions :create, :delete, :nothing
  default_action :create

  attribute :path, :kind_of => String, :name_attribute => true

  def after_created
    super
    run_context.chef_metal.with_driver "vagrant:#{path}"
  end
end
