abort "ABORT: module VagrantSupport is deprecated. Please use the RSpec shared context instead."

module VagrantSupport

  # your top-level context blocks will use this file like so:
  # require "vagrant_support"
  #
  # describe "Chef::Provisioning::Vagrant" do
  #   extend VagrantSupport
  #   include VagrantConfig   # optional, gives you a `chef_config` object.

  require 'cheffish/rspec/chef_run_support'

  # when you `extend VagrantSupport`, your RSpec-context-extending-`VagrantSupport` with then
  # further `extend ChefRunSupport` to acquire all of the latter's Lucky Charms.
  def self.extended(other)
    other.extend Cheffish::RSpec::ChefRunSupport
  end

  # this creates a `with_vagrant` block method that saves you the repetition of having to load the
  # driver code, and gives you a common place to put any other driver setup for your specs.
  #
  # subtle stuff here. it looks weird because you're taking a block and putting that inside a new block and
  # then giving *that* to a Cheffish method which will run it for you in the context of a local chef-zero.

  def with_vagrant(description, *tags, &block)

    # take the block you just passed in, and make a new Proc that will call it after loading the driver...
    context_block = proc do
      vagrant_driver = Chef::Provisioning.driver_for_url("vagrant")

      @@driver = vagrant_driver
      def self.driver
        @@driver
      end

      # when this Proc runs, this will run the block you just passed to `with_vagrant`...
      module_eval(&block)
    end

    # ...now pass that Proc to `Cheffish::RSpec::ChefRunSupport#when_the_repository`, which will:
    # 1. start up a chef-zero with `*tags` as the parameters, and
    # 2. run your `context_block` Proc (which contains your original `&block`) using that chef-zero.
    when_the_repository "exists and #{description}", *tags, &context_block
  end
end

