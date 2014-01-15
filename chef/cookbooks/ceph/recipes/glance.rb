include_recipe "ceph::default"
include_recipe "ceph::conf"

package "python-ceph" do
  action :install
end

# TODO cluster name
cluster = 'ceph'

if !File.exists?("/etc/ceph/keyring")

  admin_secret = node["ceph"]["admin-secret"]

  execute "create admin keyring" do
    command "ceph-authtool --create-keyring /etc/ceph/keyring --name=client.admin --add-key='#{admin_secret}'"
  end

end

glance_user = node[:glance][:rbd][:store_user]
glance_pool = node[:glance][:rbd][:store_pool]

ruby_block "save #{glance_user} key in node attributes" do
  block do
    client_key = %x[
      ceph \
        auth get-or-create-key client.#{glance_user} mon 'allow r' \
        osd 'allow class-read object_prefix rbd_children, allow rwx pool=#{glance_pool}'
    ].tr("\n","")
    raise 'adding or getting glance client key failed' unless $?.exitstatus == 0
    %x[ ceph-authtool /etc/ceph/ceph.client.#{glance_user}.keyring --create-keyring \
          --name=client.#{glance_user} --add-key='#{client_key}' ]
    raise 'creating glance keyring failed' unless $?.exitstatus == 0
    node.normal['ceph']['glance-secret'] = client_key
    node.save
  end
end

file "/etc/ceph/ceph.client.#{glance_user}.keyring" do
  owner "root"
  group node[:glance][:group]
  mode 0640
  action :touch
end

execute "create new pool #{glance_pool}" do
  command "ceph osd pool create #{glance_pool} 64"
end
