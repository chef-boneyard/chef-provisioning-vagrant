require 'chef_metal'
require 'chef/resource/vagrant_cluster'
require 'chef/provider/vagrant_cluster'
require 'chef/resource/vagrant_box'
require 'chef/provider/vagrant_box'
require 'chef_metal_vagrant/vagrant_provisioner'

module ChefMetalVagrant
  def self.with_vagrant_box(run_context, box_name, vagrant_options = {}, &block)
    if box_name.is_a?(Chef::Resource::VagrantBox)
      new_options = { 'vagrant_options' => { 'vm.box' => box_name.name } }
      new_options['vagrant_options']['vm.box_url'] = box_name.url if box_name.url
    else
      new_options = { 'vagrant_options' => { 'vm.box' => box_name } }
    end

    run_context.chef_metal.add_provisioner_options(new_options, &block)
  end
end

class Chef
  module DSL
    module Recipe
      def with_vagrant_cluster(cluster_path, &block)
        with_provisioner(ChefMetalVagrant::VagrantProvisioner.new(cluster_path), &block)
      end

      def with_vagrant_box(box_name, vagrant_options = {}, &block)
        ChefMetalVagrant.with_vagrant_box(run_context, box_name, vagrant_options, &block)
      end
    end
  end
end
