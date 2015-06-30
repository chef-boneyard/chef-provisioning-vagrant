require 'chef/provisioning'
require 'chef/resource/vagrant_cluster'
require 'chef/provider/vagrant_cluster'
require 'chef/resource/vagrant_box'
require 'chef/provider/vagrant_box'
require 'chef/provisioning/vagrant_driver/driver'

class Chef
  module Provisioning
    module VagrantDriver
      def self.with_vagrant_box(run_context, box_name, vagrant_options = {}, &block)
        if box_name.is_a?(Chef::Resource::VagrantBox)
          new_options = { :vagrant_options => { 'vm.box' => box_name.name } }
          new_options[:vagrant_options]['vm.box_url'] = box_name.url if box_name.url
          new_options[:vagrant_provider] = box_name.vagrant_provider
        else
          new_options = { :vagrant_options => { 'vm.box' => box_name } }
        end

        run_context.chef_provisioning.add_machine_options(new_options, &block)
      end
    end
  end

  module DSL
    module Recipe
      def with_vagrant_cluster(cluster_path, &block)
        with_driver("vagrant:#{cluster_path}", &block)
      end

      def with_vagrant_box(box_name, vagrant_options = {}, &block)
        Chef::Provisioning::VagrantDriver.with_vagrant_box(run_context, box_name, vagrant_options, &block)
      end
    end
  end
end
