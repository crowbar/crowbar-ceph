# do not include "ceph::keyring" recipe,
# when node role is "ceph-mon"
if node.roles.include?("ceph-mon")
  include_recipe "ceph::default"
  include_recipe "ceph::conf"
else
  include_recipe "ceph::keyring"
end

node["ceph"]["radosgw"]["packages"].each do |pkg|
  package pkg
end

hostname = node["hostname"]

include_recipe "ceph::radosgw_civetweb"

crowbar_pacemaker_sync_mark "wait-ceph_client_generate"

ceph_client "rgw" do
  caps("mon" => "allow rw", "osd" => "allow rwx")
  owner "root"
  group node["ceph"]["radosgw"]["group"]
  mode 0640
end

crowbar_pacemaker_sync_mark "create-ceph_client_generate"

directory "/var/lib/ceph/radosgw/ceph-radosgw.#{hostname}" do
  recursive true
  only_if { node["platform"] == "ubuntu" }
end

# needed by https://github.com/ceph/ceph/blob/master/src/upstart/radosgw-all-starter.conf
file "/var/lib/ceph/radosgw/ceph-radosgw.#{hostname}/done" do
  action :create
  only_if { node["platform"] == "ubuntu" }
end

# check if keystone is deployed (not a requirement for ceph)
unless node[:ceph][:keystone_instance].nil? || node[:ceph][:keystone_instance].empty?
  include_recipe "ceph::radosgw_keystone"
end

service "radosgw" do
  service_name node["ceph"]["radosgw"]["service_name"]
  supports restart: true
  action [:enable, :start]
  subscribes :restart, "template[/etc/ceph/ceph.conf]"
end

# In the systemd case, need extra targets enabled
service "ceph-radosgw.target" do
  action :enable
  only_if { File.exist?("/usr/lib/systemd/system/ceph-radosgw.target") }
end
service "ceph.target" do
  action :enable
  only_if { File.exist?("/usr/lib/systemd/system/ceph.target") }
end

if node[:ceph][:ha][:radosgw][:enabled]
  log "HA support for ceph-radosgw is enabled"
  include_recipe "ceph::radosgw_ha"
end
