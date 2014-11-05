# Changelog

## 0.8.1 (11/5/2014)

- Fixes to work with chef-provisioning gem

## 0.8 (11/5/2014)

- Work with Chef 12

## 0.7 (11/1/2014)

- rename to chef-provisioning-vagrant

## 0.6.1 (9/5/2014)

- minor fix to prevent issues with vagrant_box specified twice

## 0.6 (8/18/2014)

- Fix windows client (was not eating \r and doing Bad Things)

## 0.5 (6/18/2014)

- add dependency on chef-provisioning (now that chef-provisioning doesn't bring in chef-provisioning-vagrant by default)

## 0.4 (6/3/2014)

- @doubt72 Explicitly supported parallelization
- Adjust to chef-provisioning 0.11 Driver interface

## 0.3.1 (5/1/2014)

- chef-provisioning 0.10 bugfixes

## 0.3 (5/1/2014)

- React to chef-provisioning 0.10 storing with_provisioner in the run context

## 0.2 (4/11/2014)

- Support chef_server_timeout
