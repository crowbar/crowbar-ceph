include_recipe "ceph::default"
include_recipe "ceph::conf"

node['ceph']['radosgw']['packages'].each do |pck|
  package pck
end

hostname = node['hostname']

file "/var/log/ceph/radosgw.log" do
  owner node[:apache][:user]
  group node[:apache][:group]
end

directory "/var/run/ceph-radosgw" do
  owner node[:apache][:user]
  group node[:apache][:group]
  mode "0755"
  action :create
end

include_recipe "ceph::radosgw_apache2"

ceph_client 'radosgw' do
  caps('mon' => 'allow rw', 'osd' => 'allow rwx')
  group node[:apache][:group]
end

directory "/var/lib/ceph/radosgw/ceph-radosgw.#{hostname}" do
  recursive true
end

file "/var/lib/ceph/radosgw/ceph-radosgw.#{hostname}/done" do
  action :create
end

service 'radosgw' do
  service_name node['ceph']['radosgw']['service_name']
  supports :restart => true
  action [:enable, :start]
  subscribes :restart, "template[/etc/ceph/ceph.conf]"
end

# check if keystone is deployed (not a requirement for ceph)
if node[:ceph][:keystone_instance]
  include_recipe "ceph::radosgw_keystone"
end
