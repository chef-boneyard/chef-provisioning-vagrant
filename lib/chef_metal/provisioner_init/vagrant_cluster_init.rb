require 'chef_metal_vagrant/vagrant_provisioner'

ChefMetal.add_registered_provisioner_class("vagrant_cluster",
  ChefMetalVagrant::VagrantProvisioner)
