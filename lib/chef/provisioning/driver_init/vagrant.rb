require 'chef/provisioning/vagrant_driver/driver'

ChefMetal.register_driver_class("vagrant", Chef::Provisioning::VagrantDriver::Driver)
