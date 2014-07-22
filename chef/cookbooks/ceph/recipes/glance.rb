include_recipe "ceph::default"
include_recipe "ceph::conf"

package "python-ceph" do
  action :install
end

# TODO cluster name
cluster = 'ceph'

keyring = "/etc/ceph/ceph.client.admin.keyring"
if !File.exists?(keyring)

  mons = get_mon_nodes("ceph_admin-secret:*")

  if mons.empty? then
    Chef::Log.fatal("No ceph-mon found")
    raise "No ceph-mon found"
  elsif mons[0]["ceph"]["admin-secret"].empty?
    Chef::Log.fatal("No authorization keys found")
    raise "No authorization keys found"
  else
    admin_key = mons[0]["ceph"]["admin-secret"]

    execute "create admin keyring" do
      command "ceph-authtool '#{keyring}' --create-keyring  --name=client.admin --add-key='#{admin_key}'"
    end
  end

end

glance_user = node[:glance][:rbd][:store_user]
glance_pool = node[:glance][:rbd][:store_pool]

ceph_caps = { 'mon' => 'allow r', 'osd' => "allow class-read object_prefix rbd_children, allow rwx pool=#{glance_pool}" }

ceph_client glance_user do
  caps ceph_caps
  keyname "client.#{glance_user}"
  filename "/etc/ceph/ceph.client.#{glance_user}.keyring"
  owner "root"
  group node[:glance][:group]
  mode 0640
end

execute "create new pool #{glance_pool}" do
  command "ceph osd pool create #{glance_pool} 64"
end
