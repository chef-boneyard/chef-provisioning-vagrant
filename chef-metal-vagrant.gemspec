$:.unshift(File.dirname(__FILE__) + '/lib')
require 'chef_metal_vagrant/version'

Gem::Specification.new do |s|
  s.name = 'chef-metal-vagrant'
  s.version = ChefMetalVagrant::VERSION
  s.platform = Gem::Platform::RUBY
  s.extra_rdoc_files = ['README.md', 'LICENSE' ]
  s.summary = 'Provisioner for creating Vagrant instances in Chef Metal.'
  s.description = s.summary
  s.author = 'John Keiser'
  s.email = 'jkeiser@getchef.com'
  s.homepage = 'https://github.com/opscode/chef-metal-fog'

  s.add_dependency 'chef'
#  s.add_dependency 'chef-metal', '~> 0.5' # We are installed by default with chef-metal, so we don't circular dep back

  s.add_development_dependency 'rspec'
  s.add_development_dependency 'rake'

  s.bindir       = "bin"
  s.executables  = %w( )

  s.require_path = 'lib'
  s.files = %w(Rakefile LICENSE README.md) + Dir.glob("{distro,lib,tasks,spec}/**/*", File::FNM_DOTMATCH).reject {|f| File.directory?(f) }
end
