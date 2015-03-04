include_recipe "ceph::keyring"

package "python-ceph"

# TODO cluster name
cluster = 'ceph'

ceph_clients = {}

node[:cinder][:volumes].each_with_index do |volume, volid|
  next unless (volume['backend_driver'] == "rbd") && volume['rbd']['use_crowbar']

  backend_id = "backend-#{volume['backend_driver']}-#{volid}"

  cinder_user = volume[:rbd][:user]
  cinder_pool = volume[:rbd][:pool]

  cinder_pools = (ceph_clients[cinder_user] || []) << cinder_pool
  ceph_clients[cinder_user] = cinder_pools

  ceph_pool cinder_pool do
    pool_name cinder_pool
    pg_num 128
  end
end

unless ceph_clients.empty?
  glance_servers = search(:node, "roles:glance-server")
  if glance_servers.length > 0
    glance_pool = glance_servers[0][:glance][:rbd][:store_pool]
  else
    glance_pool = nil
  end

  ceph_clients.each_pair do |cinder_user, cinder_pools|
    cinder_pools << glance_pool unless glance_pool.nil?

    allow_pools = cinder_pools.map{|p| "allow rwx pool=#{p}"}.join(", ")
    ceph_caps = { 'mon' => 'allow r', 'osd' => "allow class-read object_prefix rbd_children, #{allow_pools}" }

    ceph_client cinder_user do
      caps ceph_caps
      keyname "client.#{cinder_user}"
      filename "/etc/ceph/ceph.client.#{cinder_user}.keyring"
      owner "root"
      group node[:cinder][:group]
      mode 0640
    end
  end
end
