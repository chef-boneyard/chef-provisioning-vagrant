require 'chef/mixin/shell_out'
require 'chef_metal/driver'
require 'chef_metal/machine/windows_machine'
require 'chef_metal/machine/unix_machine'
require 'chef_metal/convergence_strategy/install_msi'
require 'chef_metal/convergence_strategy/install_cached'
require 'chef_metal/transport/winrm'
require 'chef_metal/transport/ssh'

module ChefMetalVagrant
  # Provisions machines in vagrant.
  class VagrantDriver < ChefMetal::Driver

    include Chef::Mixin::ShellOut

    # Create a new vagrant driver.
    #
    # ## Parameters
    # cluster_path - path to the directory containing the vagrant files, which
    #                should have been created with the vagrant_cluster resource.
    def initialize(driver_url, config)
      super
      scheme, cluster_path = driver_url.split(':', 2)
      @cluster_path = cluster_path
    end

    attr_reader :cluster_path

    def self.from_url(driver_url, config)
      VagrantDriver.new(driver_url, config)
    end

    def allocate_machine(action_handler, machine_spec, machine_options)
      # Set up the driver output
      vm_name = machine_spec.name
      vm_file_path = File.join(cluster_path, "#{machine_spec.name}.vm")
      vm_file_updated = create_vm_file(action_handler, vm_name, vm_file_path)
      if vm_file_updated || !machine_spec.location
        old_location = machine_spec.location
        machine_spec.location = {
          'driver_url' => driver_url,
          'driver_version' => ChefMetalVagrant::VERSION,
          'vm_name' => vm_name,
          'vm_file_path' => vm_file_path,
          'allocated_at' => Time.now.utc.to_s,
          'host_node' => action_handler.host_node
        }
        if machine_options[:vagrant_options]
          %w(vm.guest winrm.host winrm.port winrm.username winrm.password).each do |key|
            machine_spec.location[key] = machine_options[:vagrant_options][key] if machine_options[:vagrant_options][key]
          end
        end
        machine_spec.location['chef_client_timeout'] = machine_options[:chef_client_timeout] if machine_options[:chef_client_timeout]
      end
    end

    # Acquire a machine, generally by provisioning it.  Returns a Machine
    # object pointing at the machine, allowing useful actions like setup,
    # converge, execute, file and directory.  The Machine object will have a
    # "node" property which must be saved to the server (if it is any
    # different from the original node object).
    #
    # ## Parameters
    # action_handler - the action_handler object that is calling this method; this
    #        is generally a action_handler, but could be anything that can support the
    #        ChefMetal::ActionHandler interface (i.e., in the case of the test
    #        kitchen metal driver for acquiring and destroying VMs; see the base
    #        class for what needs providing).
    # node - node object (deserialized json) representing this machine.  If
    #        the node has a driver_options hash in it, these will be used
    #        instead of options provided by the driver.  TODO compare and
    #        fail if different?
    #        node will have node['normal']['driver_options'] in it with any options.
    #        It is a hash with this format (all keys are strings):
    #
    #           -- driver_url: vagrant:<cluster_path>
    #           -- vagrant_options: hash of properties of the "config"
    #              object, i.e. "vm.box" => "ubuntu12" and "vm.box_url"
    #           -- vagrant_config: string containing other vagrant config.
    #              Should assume the variable "config" represents machine config.
    #              Will be written verbatim into the vm's Vagrantfile.
    #           -- transport_options: hash of options specifying the transport.
    #                :type => :ssh
    #                :type => :winrm
    #                If not specified, ssh is used unless vm.guest is :windows.  If that is
    #                the case, the windows options are used and the port forward for 5985
    #                is detected.
    #           -- up_timeout: maximum time, in seconds, to wait for vagrant
    #              to bring up the machine.  Defaults to 10 minutes.
    #           -- chef_client_timeout: maximum time, in seconds, to wait for chef-client
    #              to complete.  0 or nil for no timeout.  Defaults to 2 hours.
    #
    #        node['normal']['driver_output'] will be populated with information
    #        about the created machine.  For vagrant, it is a hash with this
    #        format:
    #
    #           -- driver_url: vagrant_cluster://<current_node>/<cluster_path>
    #           -- vm_name: name of vagrant vm created
    #           -- vm_file_path: path to machine-specific vagrant config file
    #              on disk
    #           -- forwarded_ports: hash with key as guest_port => host_port
    #
    def ready_machine(action_handler, machine_spec, machine_options)
      start_machine(action_handler, machine_spec, machine_options)
      machine_for(machine_spec)
    end

    # Connect to machine without acquiring it
    def connect_to_machine(machine_spec)
      machine_for(machine_spec)
    end

    def delete_machine(action_handler, machine_spec)
      if machine_spec.location
        vm_name = machine_spec.location['vm_name']
        current_status = vagrant_status(vm_name)
        if current_status != 'not created'
          action_handler.perform_action "run vagrant destroy -f #{vm_name} (status was '#{current_status}')" do
            result = shell_out("vagrant destroy -f #{vm_name}", :cwd => cluster_path)
            if result.exitstatus != 0
              raise "vagrant destroy failed!\nSTDOUT:#{result.stdout}\nSTDERR:#{result.stderr}"
            end
          end
        end

        convergence_strategy_for(machine_spec).cleanup_convergence(action_handler, machine_spec)

        vm_file_path = machine_spec.location['vm_file_path']
        ChefMetal.inline_resource(action_handler) do
          file vm_file_path do
            action :delete
          end
        end
      end
    end

    def stop_machine(action_handler, machine_spec)
      if machine_spec.location
        vm_name = machine_spec.location['vm_name']
        current_status = vagrant_status(vm_name)
        if current_status == 'running'
          action_handler.perform_action "run vagrant halt #{vm_name} (status was '#{current_status}')" do
            result = shell_out("vagrant halt #{vm_name}", :cwd => cluster_path)
            if result.exitstatus != 0
              raise "vagrant halt failed!\nSTDOUT:#{result.stdout}\nSTDERR:#{result.stderr}"
            end
          end
        end
      end
    end

    # Used by vagrant_cluster and machine to get the string used to configure vagrant
    def self.vagrant_config_string(vagrant_config, variable, line_prefix)
      hostname = name.gsub(/[^A-Za-z0-9\-]/, '-')

      result = ''
      vagrant_config.each_pair do |key, value|
        result += "#{line_prefix}#{variable}.#{key} = #{value.inspect}\n"
      end
      result
    end

    def driver_url
      "vagrant_cluster:#{cluster_path}"
    end

    protected

    def create_vm_file(action_handler, vm_name, vm_file_path)
      # Determine contents of vm file
      vm_file_content = "Vagrant.configure('2') do |outer_config|\n"
      vm_file_content << "  outer_config.vm.define #{vm_name.inspect} do |config|\n"
      merged_vagrant_options = { 'vm.hostname' => vm_name }
      merged_vagrant_options.merge!(driver_options[:vagrant_options]) if driver_options[:vagrant_options]
      merged_vagrant_options.each_pair do |key, value|
        vm_file_content << "    config.#{key} = #{value.inspect}\n"
      end
      vm_file_content << driver_options[:vagrant_config] if driver_options[:vagrant_config]
      vm_file_content << "  end\nend\n"

      # Set up vagrant file
      ChefMetal.inline_resource(action_handler) do
        file vm_file_path do
          content vm_file_content
          action :create
        end
      end
    end

    def start_machine(action_handler, machine_spec, machine_options)
      vm_name = machine_spec.location['vm_name']
      up_timeout = machine_options[:up_timeout] || 10*60

      current_status = vagrant_status(vm_name)
      if current_status != 'running'
        # Run vagrant up if vm is not running
        action_handler.perform_action "run vagrant up #{vm_name} (status was '#{current_status}')" do
          result = shell_out("vagrant up #{vm_name}", :cwd => cluster_path, :timeout => up_timeout)
          if result.exitstatus != 0
            raise "vagrant up #{vm_name} failed!\nSTDOUT:#{result.stdout}\nSTDERR:#{result.stderr}"
          end
          parse_vagrant_up(result.stdout, machine_spec)
        end
      elsif vm_file_updated
        # Run vagrant reload if vm is running and vm file changed
        action_handler.perform_action "run vagrant reload #{vm_name}" do
          result = shell_out("vagrant reload #{vm_name}", :cwd => cluster_path, :timeout => up_timeout)
          if result.exitstatus != 0
            raise "vagrant reload #{vm_name} failed!\nSTDOUT:#{result.stdout}\nSTDERR:#{result.stderr}"
          end
          parse_vagrant_up(result.stdout, machine_spec)
        end
      end
    end

    def parse_vagrant_up(output, machine_spec)
      # Grab forwarded port info
      machine_spec.location['forwarded_ports'] = {}
      in_forwarding_ports = false
      output.lines.each do |line|
        if in_forwarding_ports
          if line =~ /-- (\d+) => (\d+)/
            machine_spec.location['forwarded_ports'][$1] = $2
          else
            in_forwarding_ports = false
          end
        elsif line =~ /Forwarding ports...$/
          in_forwarding_ports = true
        end
      end
    end

    def machine_for(machine_spec)
      if machine_spec.location['vm.guest'].to_s == 'windows'
        ChefMetal::Machine::WindowsMachine.new(machine_spec, transport_for(machine_spec), convergence_strategy_for(machine_spec))
      else
        ChefMetal::Machine::UnixMachine.new(machine_spec, transport_for(machine_spec), convergence_strategy_for(machine_spec))
      end
    end

    def convergence_strategy_for(machine_spec)
      if machine_spec.location['vm.guest'].to_s == 'windows'
        @windows_convergence_strategy ||= begin
          options = {}
          options[:chef_client_timeout] = machine_spec.location['chef_client_timeout'] if machine_spec.location['chef_client_timeout']
          ChefMetal::ConvergenceStrategy::InstallMsi.new(options)
        end
      else
        @unix_convergence_strategy ||= begin
          options = {}
          options[:chef_client_timeout] = machine_spec.location['chef_client_timeout'] if machine_spec.location['chef_client_timeout']
          ChefMetal::ConvergenceStrategy::InstallCached.new(options)
        end
      end
    end

    def transport_for(machine_spec)
      if machine_spec.location['vm.guest'].to_s == 'windows'
        create_winrm_transport(machine_spec)
      else
        create_ssh_transport(machine_spec)
      end
    end

    def vagrant_status(name)
      status_output = shell_out("vagrant status #{name}", :cwd => cluster_path).stdout
      if status_output =~ /^#{name}\s+([^\n]+)\s+\(([^\n]+)\)$/m
        $1
      else
        'not created'
      end
    end

    def create_winrm_transport(machine_spec)
      forwarded_ports = machine_spec.location['forwarded_ports']

      # TODO IPv6 loopback?  What do we do for that?
      hostname = machine_spec.location['winrm.host'] || '127.0.0.1'
      port = machine_spec.location['winrm.port'] || 5985
      port = forwarded_ports[port] if forwarded_ports[port]
      endpoint = "http://#{hostname}:#{port}/wsman"
      type = :plaintext
      options = {
        :user => machine_spec.location['winrm.username'] || 'vagrant',
        :pass => machine_spec.location['winrm.password'] || 'vagrant',
        :disable_sspi => true
      }

      ChefMetal::Transport::WinRM.new(endpoint, type, options)
    end

    def create_ssh_transport(machine_spec)
      vagrant_ssh_config = vagrant_ssh_config_for(machine_spec)
      hostname = vagrant_ssh_config['HostName']
      username = vagrant_ssh_config['User']
      ssh_options = {
        :port => vagrant_ssh_config['Port'],
        :auth_methods => ['publickey'],
        :user_known_hosts_file => vagrant_ssh_config['UserKnownHostsFile'],
        :paranoid => yes_or_no(vagrant_ssh_config['StrictHostKeyChecking']),
        :keys => [ strip_quotes(vagrant_ssh_config['IdentityFile']) ],
        :keys_only => yes_or_no(vagrant_ssh_config['IdentitiesOnly'])
      }
      ssh_options[:auth_methods] = %w(password) if yes_or_no(vagrant_ssh_config['PasswordAuthentication'])
      options = {
        :prefix => 'sudo '
      }
      ChefMetal::Transport::SSH.new(hostname, username, ssh_options, options, config)
    end

    def vagrant_ssh_config_for(machine_spec)
      vagrant_ssh_config = {}
      result = shell_out("vagrant ssh-config #{machine_spec.location['vm_name']}", :cwd => cluster_path)
      result.stdout.lines.inject({}) do |result, line|
        line =~ /^\s*(\S+)\s+(.+)/
        vagrant_ssh_config[$1] = $2
      end
      vagrant_ssh_config
    end

    def yes_or_no(str)
      case str
      when 'yes'
        true
      else
        false
      end
    end

    def strip_quotes(str)
      if str[0] == '"' && str[-1] == '"' && str.size >= 2
        str[1..-2]
      else
        str
      end
    end
  end
end
