require 'chef_metal_vagrant/vagrant_driver'

ChefMetal.register_driver_class("vagrant", ChefMetalVagrant::VagrantDriver)
