# do not include "ceph::keyring" recipe, 
# when node role is "ceph-mon"
if node.roles.include?("ceph-mon")
  include_recipe "ceph::default"
  include_recipe "ceph::conf"
else
  include_recipe "ceph::keyring"
end

node['ceph']['radosgw']['packages'].each do |pkg|
  package pkg
end

hostname = node['hostname']

directory '/var/log/radosgw' do
  owner node['apache']['user']
  group node['apache']['group']
  mode '0755'
  action :create
end

file '/var/log/radosgw/radosgw.log' do
  owner node['apache']['user']
  group node['apache']['group']
end

directory '/var/run/ceph-radosgw' do
  owner node['apache']['user']
  group node['apache']['group']
  mode '0755'
  action :create
end

include_recipe "ceph::radosgw_apache2"

crowbar_pacemaker_sync_mark "wait-ceph_client_generate"

ceph_client 'radosgw' do
  caps('mon' => 'allow rw', 'osd' => 'allow rwx')
  owner 'root'
  group node['apache']['group']
  mode 0640
end

crowbar_pacemaker_sync_mark "create-ceph_client_generate"

directory "/var/lib/ceph/radosgw/ceph-radosgw.#{hostname}" do
  recursive true
  only_if { node['platform'] == "ubuntu" }
end

# needed by https://github.com/ceph/ceph/blob/master/src/upstart/radosgw-all-starter.conf
file "/var/lib/ceph/radosgw/ceph-radosgw.#{hostname}/done" do
  action :create
  only_if { node['platform'] == "ubuntu" }
end

# check if keystone is deployed (not a requirement for ceph)
unless node[:ceph][:keystone_instance].nil? || node[:ceph][:keystone_instance].empty?
  include_recipe "ceph::radosgw_keystone"
end

service 'radosgw' do
  service_name node['ceph']['radosgw']['service_name']
  supports :restart => true
  action [:enable, :start]
  subscribes :restart, "template[/etc/ceph/ceph.conf]"
end

if node[:ceph][:ha][:radosgw][:enabled]
  log "HA support for ceph-radosgw is enabled"
  include_recipe "ceph::radosgw_ha"
end
