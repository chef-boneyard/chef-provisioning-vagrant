require 'chef/mixin/shell_out'
require 'chef_metal/driver'
require 'chef_metal/machine/windows_machine'
require 'chef_metal/machine/unix_machine'
require 'chef_metal/convergence_strategy/install_msi'
require 'chef_metal/convergence_strategy/install_cached'
require 'chef_metal/transport/winrm'
require 'chef_metal/transport/ssh'
require 'chef_metal_vagrant/version'
require 'chef/resource/vagrant_cluster'
require 'chef/provider/vagrant_cluster'

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
      scheme, cluster_path = driver_url.split(':', 2)
      cluster_path = File.expand_path(cluster_path || File.join(Chef::Config.config_dir, 'vms'))
      VagrantDriver.new("vagrant:#{cluster_path}", config)
    end

    # Acquire a machine, generally by provisioning it. Returns a Machine
    # object pointing at the machine, allowing useful actions like setup,
    # converge, execute, file and directory.
    def allocate_machine(action_handler, machine_spec, machine_options)
      ensure_vagrant_cluster(action_handler)
      vm_name = machine_spec.name
      vm_file_path = File.join(cluster_path, "#{machine_spec.name}.vm")
      vm_file_updated = create_vm_file(action_handler, vm_name, vm_file_path, machine_options)
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
        machine_spec.location['needs_reload'] = true if vm_file_updated
        if machine_options[:vagrant_options]
          %w(vm.guest winrm.host winrm.port winrm.username winrm.password).each do |key|
            machine_spec.location[key] = machine_options[:vagrant_options][key] if machine_options[:vagrant_options][key]
          end
        end
        machine_spec.location['chef_client_timeout'] = machine_options[:chef_client_timeout] if machine_options[:chef_client_timeout]
      end
    end

    def ready_machine(action_handler, machine_spec, machine_options)
      start_machine(action_handler, machine_spec, machine_options)
      machine_for(machine_spec, machine_options)
    end

    # Connect to machine without acquiring it
    def connect_to_machine(machine_spec, machine_options)
      machine_for(machine_spec, machine_options)
    end

    def destroy_machine(action_handler, machine_spec, machine_options)
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

        convergence_strategy_for(machine_spec, machine_options).
          cleanup_convergence(action_handler, machine_spec)

        vm_file_path = machine_spec.location['vm_file_path']
        ChefMetal.inline_resource(action_handler) do
          file vm_file_path do
            action :delete
          end
        end
      end
    end

    def stop_machine(action_handler, machine_spec, machine_options)
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

    def ready_machines(action_handler, specs_and_options, parallelizer)
      start_machines(action_handler, specs_and_options)
      machines = []
      specs_and_options.each_pair do |spec, options|
        machines.push(machine_for(spec, options))
      end
      machines
    end

    def destroy_machines(action_handler, specs_and_options, parallelizer)
      all_names = []
      all_status = []
      all_outputs = {}
      specs_and_options.each_key do |spec|
        if spec.location
          vm_name = spec.location['vm_name']
          current_status = vagrant_status(vm_name)
          if current_status != 'not created'
            all_names.push(vm_name)
            all_status.push(current_status)
          end
        end
      end
      if all_names.length > 0
        names = all_names.join(" ")
        statuses = all_status.join(", ")
        action_handler.perform_action "run vagrant destroy -f #{names} (status was '#{statuses}')" do
          result = shell_out("vagrant destroy -f #{names}", :cwd => cluster_path)
          if result.exitstatus != 0
            raise "vagrant destroy failed!\nSTDOUT:#{result.stdout}\nSTDERR:#{result.stderr}"
          end
        end
      end
      specs_and_options.each_pair do |spec, options|
        convergence_strategy_for(spec, options).
          cleanup_convergence(action_handler, spec)

        vm_file_path = spec.location['vm_file_path']
        ChefMetal.inline_resource(action_handler) do
          file vm_file_path do
            action :delete
          end
        end
      end
    end

    def stop_machines(action_handler, specs_and_options, parallelizer)
      all_names = []
      specs_and_options.each_key do |spec|
        if spec.location
          vm_name = spec.location['vm_name']
          current_status = vagrant_status(vm_name)
          if current_status == 'running'
            all_names.push(vm_name)
          end
        end
      end
      if all_names.length > 0
        names = all_names.join(" ")
        action_handler.perform_action "run vagrant halt #{names} (status was 'running')" do
          result = shell_out("vagrant halt #{names}", :cwd => cluster_path)
          if result.exitstatus != 0
            raise "vagrant halt failed!\nSTDOUT:#{result.stdout}\nSTDERR:#{result.stderr}"
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
      "vagrant:#{cluster_path}"
    end

    protected

    def ensure_vagrant_cluster(action_handler)
      _cluster_path = cluster_path
      ChefMetal.inline_resource(action_handler) do
        vagrant_cluster _cluster_path
      end
    end

    def create_vm_file(action_handler, vm_name, vm_file_path, machine_options)
      # Determine contents of vm file
      vm_file_content = "Vagrant.configure('2') do |outer_config|\n"
      vm_file_content << "  outer_config.vm.define #{vm_name.inspect} do |config|\n"
      merged_vagrant_options = { 'vm.hostname' => vm_name }
      merged_vagrant_options.merge!(machine_options[:vagrant_options]) if machine_options[:vagrant_options]
      merged_vagrant_options.each_pair do |key, value|
        vm_file_content << "    config.#{key} = #{value.inspect}\n"
      end
      vm_file_content << machine_options[:vagrant_config] if machine_options[:vagrant_config]
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
      vm_file_updated = machine_spec.location['needs_reload']
      machine_spec.location['needs_reload'] = false
      if current_status != 'running'
        # Run vagrant up if vm is not running
        action_handler.perform_action "run vagrant up #{vm_name} (status was '#{current_status}')" do
          result = shell_out("vagrant up #{vm_name}", :cwd => cluster_path,
            :timeout => up_timeout)
          if result.exitstatus != 0
            raise "vagrant up #{vm_name} failed!\nSTDOUT:#{result.stdout}\nSTDERR:#{result.stderr}"
          end
          parse_vagrant_up(result.stdout, machine_spec)
        end
      elsif vm_file_updated
        # Run vagrant reload if vm is running and vm file changed
        action_handler.perform_action "run vagrant reload #{vm_name}" do
          result = shell_out("vagrant reload #{vm_name}", :cwd => cluster_path,
            :timeout => up_timeout)
          if result.exitstatus != 0
            raise "vagrant reload #{vm_name} failed!\nSTDOUT:#{result.stdout}\nSTDERR:#{result.stderr}"
          end
          parse_vagrant_up(result.stdout, machine_spec)
        end
      end
    end

    def start_machines(action_handler, specs_and_options)
      up_names = []
      up_status = []
      up_specs = {}
      update_names = []
      update_specs = {}
      timeouts = []
      specs_and_options.each_pair do |spec, options|
        vm_name = spec.location['vm_name']

        vm_file_updated = spec.location['needs_reload']
        spec.location['needs_reload'] = false

        current_status = vagrant_status(vm_name)
        if current_status != 'running'
          up_names.push(vm_name)
          up_status.push(current_status)
          up_specs[vm_name] = spec
        elsif vm_file_updated
          update_names.push(vm_name)
          update_specs[vm_name] = spec
        end
        timeouts.push(options[:up_timeout])
      end
      # Use the highest timeout, if any exist
      up_timeout = timeouts.compact.max
      up_timeout ||= 10*60
      if up_names.length > 0
        # Run vagrant up if vm is not running
        names = up_names.join(" ")
        statuses = up_status.join(", ")
        action_handler.perform_action "run vagrant up --parallel #{names} (status was '#{statuses}')" do
          result = shell_out("vagrant up --parallel #{names}", :cwd => cluster_path,
            :timeout => up_timeout)
          if result.exitstatus != 0
            raise "vagrant up #{names} failed!\nSTDOUT:#{result.stdout}\nSTDERR:#{result.stderr}"
          end
          parse_multi_vagrant_up(result.stdout, up_specs)
        end
      end
      if update_names.length > 0
        names = update_names.join(" ")
        # Run vagrant reload if vm is running and vm file changed
        action_handler.perform_action "run vagrant reload #{names}" do
          result = shell_out("vagrant reload #{names}", :cwd => cluster_path,
            :timeout => up_timeout)
          if result.exitstatus != 0
            raise "vagrant reload #{names} failed!\nSTDOUT:#{result.stdout}\nSTDERR:#{result.stderr}"
          end
          parse_multi_vagrant_up(result.stdout, update_specs)
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

    def parse_multi_vagrant_up(output, all_machine_specs)
      # Grab forwarded port info
      in_forwarding_ports = {}
      all_machine_specs.each_pair do |key, spec|
        spec.location['forwarded_ports'] = {}
        in_forwarding_ports[key] = false
      end
      output.lines.each do |line|
        /^\[(.*?)\]/.match(line)
        node_name = $1
        if in_forwarding_ports[node_name]
          if line =~ /-- (\d+) => (\d+)/
            spec = all_machine_specs[node_name]
            spec.location['forwarded_ports'][$1] = $2
          else
            in_forwarding_ports[node_name] = false
          end
        elsif line =~ /Forwarding ports...$/
          in_forwarding_ports[node_name] = true
        end
      end
    end

    def machine_for(machine_spec, machine_options)
      if machine_spec.location['vm.guest'].to_s == 'windows'
        ChefMetal::Machine::WindowsMachine.new(machine_spec, transport_for(machine_spec),
          convergence_strategy_for(machine_spec, machine_options))
      else
        ChefMetal::Machine::UnixMachine.new(machine_spec, transport_for(machine_spec),
          convergence_strategy_for(machine_spec, machine_options))
      end
    end

    def convergence_strategy_for(machine_spec, machine_options)
      if machine_spec.location['vm.guest'].to_s == 'windows'
        @windows_convergence_strategy ||= begin
          ChefMetal::ConvergenceStrategy::InstallMsi.
                                              new(machine_options[:convergence_options])
        end
      else
        @unix_convergence_strategy ||= begin
          ChefMetal::ConvergenceStrategy::InstallCached.
                                           new(machine_options[:convergence_options])
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
      result = shell_out("vagrant ssh-config #{machine_spec.location['vm_name']}",
        :cwd => cluster_path)
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
