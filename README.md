# chef-provisioning-vagrant

This is the Vagrant driver for chef-provisioning.

# Resources

## vagrant_box

Specifying this resource will verify that the correct vagrant box is downloaded to the box directory (default of ```~/.chefdk/vms``` when using the chefdk) for the correct vagrant provider. The vagrant provider defaults to virtualbox.

This example will ```vagrant box add``` the box if it is not currently on your system.
```
vagrant_box 'opscode-centos-6.4' do
  url 'http://opscode-vm-bento.s3.amazonaws.com/vagrant/vmware/opscode_centos-6.4_chef-provisionerless.box'
  vagrant_provider 'vmware_desktop'
end
```
This example will use the vmware_desktop/fusion based box that already exists on your system, and will fail if the box does not exist. **Note: since bento boxes appear as 'vmware_desktop', 'vmware_fusion' will not work here**
```
vagrant_box 'custom_box' do
  vagrant_provider 'vmware_desktop'
end
```
This example will use the default virtualbox based box that already exists on your system, and will fail if the box does not exist.
```
vagrant_box 'custom_box'
```
# Machine Options

An example of machine options would be as follows:
```
options = {
  vagrant_options: {
    'vm.box' => 'opscode-centos-6.4',
  },
}

machine 'marley' do
  machine_options options
  converge true
end
```
You can also add a ```vagrant_provider``` attribute to override the default virtualbox provider:
```
options = {
  vagrant_provider: 'vmware_fusion'
  vagrant_options: {
    'vm.box' => 'opscode-centos-6.4',
  },
}

machine 'marley' do
  machine_options options
  converge true
end
```
**Note: even though the bento based boxes appear as 'vmware_desktop', 'vmware_fusion' is required here, as it is the name of the virtualbox provider**

# Known Issues
It would be really nice to do some magic to make the vmware_fusion vs vmware_desktop providers match in the machine_options and the vagrant_box resource, but some magic would happen there...
