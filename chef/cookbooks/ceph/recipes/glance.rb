include_recipe "ceph::default"
include_recipe "ceph::conf"

# TODO cluster name
cluster = 'ceph'

package "python-ceph" do
  action :install
end

admin_secret = node["ceph"]["admin-secret"]

execute "create admin keyring" do
  command "ceph-authtool --create-keyring /etc/ceph/keyring --name=client.admin --add-key='#{admin_secret}'"
end

ruby_block "save glance key in node attributes" do
  block do
    client_key = %x[
      ceph \
        auth get-or-create-key client.glance mon 'allow r' \
        osd 'allow class-read object_prefix rbd_children, allow rwx pool=images'
    ].tr("\n","")
    raise 'adding or getting client.glance key failed' unless $?.exitstatus == 0
    node.normal['ceph']['glance-secret'] = client_key
    node.save
  end
  not_if { node['ceph']['glance-secret'] }
end

glance_secret = node["ceph"]["glance-secret"]

file "/etc/ceph/ceph.client.glance.keyring" do
  owner "root"
  group "openstack-glance"
  mode 0640
  action :create
end

execute "format as keyring" do
  command "ceph-authtool /etc/ceph/ceph.client.glance.keyring --create-keyring --name=client.glance --add-key='#{glance_secret}'"
end

execute "create new pool" do
  command "ceph osd pool create images 64"
end
