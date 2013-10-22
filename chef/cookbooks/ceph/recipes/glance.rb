include_recipe "ceph::default"
include_recipe "ceph::conf"

package "python-ceph" do
  action :install
end

# TODO cluster name
cluster = 'ceph'

group "ceph" do
  action :create
end

group "ceph" do
  members "openstack-glance"
  action :modify
  append true
end

if !File.exists?("/etc/ceph/keyring")

  file "/etc/ceph/keyring" do
    owner "root"
    group "ceph"
    mode 0640
    action :create
  end

  admin_secret = node["ceph"]["admin-secret"]

  execute "create admin keyring" do
    command "ceph-authtool --create-keyring /etc/ceph/keyring --name=client.admin --add-key='#{admin_secret}'"
  end
end

ruby_block "save #{node[:glance][:rbd][:store_user]} key in node attributes" do
  block do
    client_key = %x[
      ceph \
        auth get-or-create-key client.#{node[:glance][:rbd][:store_user]} mon 'allow r' \
        osd 'allow class-read object_prefix rbd_children, allow rwx pool=#{node[:glance][:rbd][:store_pool]}'
    ].tr("\n","")
    raise 'adding or getting glance client key failed' unless $?.exitstatus == 0
    %x[ ceph-authtool /etc/ceph/ceph.client.#{node[:glance][:rbd][:store_user]}.keyring --create-keyring \
          --name=client.#{node[:glance][:rbd][:store_user]} --add-key='#{client_key}' ]
    raise 'creating glance keyring failed' unless $?.exitstatus == 0
    node.normal['ceph']['glance-secret'] = client_key
    node.save
  end
  not_if { node['ceph']['glance-secret'] }
end

file "/etc/ceph/ceph.client.#{node[:glance][:rbd][:store_user]}.keyring" do
  owner "root"
  group "openstack-glance"
  mode 0640
  action :touch
end

execute "create new pool #{node['glance']['rbd']['store_pool']}" do
  command "ceph osd pool create #{node['glance']['rbd']['store_pool']} 64"
end
