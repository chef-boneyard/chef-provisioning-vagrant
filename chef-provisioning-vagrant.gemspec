$:.unshift(File.dirname(__FILE__) + '/lib')
require 'chef/provisioning/vagrant_driver/version'

Gem::Specification.new do |s|
  s.name = 'chef-provisioning-vagrant'
  s.version = Chef::Provisioning::VagrantDriver::VERSION
  s.platform = Gem::Platform::RUBY
  s.extra_rdoc_files = ['README.md', 'LICENSE' ]
  s.summary = 'Driver for creating Vagrant instances in Chef Provisioning.'
  s.description = s.summary
  s.author = 'John Keiser'
  s.email = 'jkeiser@getchef.com'
  s.homepage = 'https://github.com/chef/chef-provisioning-vagrant'

  s.add_dependency 'chef-provisioning'

  s.add_development_dependency 'chef'
  s.add_development_dependency 'rspec'
  s.add_development_dependency 'rake'
  s.add_development_dependency 'github_changelog_generator', '1.11.3'

  s.bindir       = "bin"
  s.executables  = %w( )

  s.require_path = 'lib'
  s.files = %w(Gemfile Rakefile LICENSE README.md) + Dir.glob("*.gemspec") +
      Dir.glob("{distro,lib,tasks,spec}/**/*", File::FNM_DOTMATCH).reject {|f| File.directory?(f) }
end
