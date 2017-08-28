require "chef/provider/lwrp_base"
require "chef/mixin/shell_out"

class Chef::Provider::VagrantBox < Chef::Provider::LWRPBase
  provides :vagrant_box
  use_inline_resources

  include Chef::Mixin::ShellOut

  def whyrun_supported?
    true
  end

  action :create do
    if !box_exists?(new_resource)
      if new_resource.url
        converge_by "run 'vagrant box add #{new_resource.name} #{new_resource.url} --provider #{new_resource.vagrant_provider}'" do
          shell_out("vagrant box add #{new_resource.name} #{new_resource.url} --provider #{new_resource.vagrant_provider}").error!
        end
      else
        raise "Box #{new_resource.name} does not exist"
      end
    end
  end

  action :delete do
    if box_exists?(new_resource.name)
      converge_by "run 'vagrant box remove #{new_resource.name} #{list_boxes[new_resource.name]} --provider #{new_resource.vagrant_provider}'" do
        shell_out("vagrant box remove #{new_resource.name} #{list_boxes[new_resource.name]} --provider #{new_resource.vagrant_provider}").error!
      end
    end
  end

  # Since all box names must be unique for a particular vagrant provider, this hash now
  # keys off the provider name, as opposed to the box name. The version is not currently
  # used, but is collected as metadata for future consumption
  def list_boxes
    @list_boxes ||= shell_out("vagrant box list").stdout.lines.inject({}) do |result, line|
      line =~ /^(\S+)\s+\((.+),(.+)\)\s*$/
      if result.has_key?($2)
        result[$2][$1] = $3
      else
        result[$2] = { $1 => $3 }
      end
      result
    end
  end

  # In some rather strained logic, we hook into the vagrant provider, then
  # the box name to make sure we have the correct box already installed.
  def box_exists?(new_resource)
    boxes = list_boxes
    provider = new_resource.vagrant_provider
    boxes.has_key?(provider) && boxes[provider].has_key?(new_resource.name)
  end

  def load_current_resource
  end
end
