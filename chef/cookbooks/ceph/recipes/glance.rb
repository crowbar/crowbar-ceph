include_recipe "ceph::keyring"

package "python-ceph"

# TODO cluster name
cluster = 'ceph'

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
