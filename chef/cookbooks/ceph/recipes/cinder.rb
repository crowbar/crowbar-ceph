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

node[:cinder][:volumes].each_with_index do |volume, volid|
  next unless (volume['backend_driver'] == "rbd") && volume['rbd']['use_crowbar']

  backend_id = "backend-#{volume['backend_driver']}-#{volid}"

  cinder_user = volume[:rbd][:user]
  cinder_pool = volume[:rbd][:pool]

  ruby_block "save cinder key in node attributes (#{backend_id})" do
    block do

      glance_servers = search(:node, "roles:glance-server")
      if glance_servers.length > 0
        glance_pool = glance_servers[0][:glance][:rbd][:store_pool]

        client_key = %x[
          ceph \
            auth get-or-create-key client.'#{cinder_user}' mon 'allow r' \
            osd 'allow class-read object_prefix rbd_children, allow rwx pool='#{cinder_pool}', allow rwx pool='#{glance_pool}''
        ].tr("\n","")
        raise 'adding or getting cinder client key failed' unless $?.exitstatus == 0

      else

        client_key = %x[
          ceph \
            auth get-or-create-key client.'#{cinder_user}' mon 'allow r' \
            osd 'allow class-read object_prefix rbd_children, allow rwx pool='#{cinder_pool}''
        ].tr("\n","")
        raise 'adding or getting cinder client key failed' unless $?.exitstatus == 0

      end

      %x[ ceph-authtool /etc/ceph/ceph.client.'#{cinder_user}'.keyring --create-keyring \
            --name=client.'#{cinder_user}' --add-key='#{client_key}' ]
      raise 'creating cinder keyring failed' unless $?.exitstatus == 0

      node.normal['ceph']['cinder-secret'] = client_key
      node.save

    end
  end

  file "/etc/ceph/ceph.client.#{cinder_user}.keyring (#{backend_id})" do
    path "/etc/ceph/ceph.client.#{cinder_user}.keyring"
    owner "root"
    group node[:cinder][:group]
    mode 0640
    action :create
  end

  execute "create new pool #{cinder_pool} (#{backend_id})" do
    command "ceph osd pool create #{cinder_pool} 128"
  end
end
