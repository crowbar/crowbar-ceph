include_recipe "ceph::default"
include_recipe "ceph::conf"

packages = []

case node[:platform]
when "suse"
  packages = %w{
      python-ceph
      kvm-rbd-plugin
  }
end

packages.each do |pkg|
  package pkg do
    action :install
  end
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

cinder_controller = search(:node, "roles:cinder-controller")
if cinder_controller.length > 0
  cinder_pools = []
  cinder_controller[0][:cinder][:volumes].each do |volume|
    next unless (volume['backend_driver'] == "rbd") && volume['rbd']['use_crowbar']
    cinder_pools << volume[:rbd][:pool]
  end

  nova_uuid = node["ceph"]["config"]["fsid"]
  nova_user = 'nova'

  secret_file_path = "/etc/ceph/ceph-secret.xml"

  file secret_file_path do
    owner "root"
    group "root"
    mode "0640"
    content "<secret ephemeral='no' private='no'> <uuid>#{nova_uuid}</uuid><usage type='ceph'> <name>client.#{nova_user} secret</name> </usage> </secret>"
  end #file secret_file_path

  ruby_block "save nova key in node attributes" do
    block do
    
      allow_pools = cinder_pools.map{|p| "allow rwx pool=#{p}"}.join(", ")

      client_key = %x[
        ceph \
          auth get-or-create-key client.'#{nova_user}' mon 'allow r' \
         osd 'allow class-read object_prefix rbd_children, #{allow_pools}'
      ].tr("\n","")
      raise 'adding or getting nova client key failed' unless $?.exitstatus == 0

      %x[ ceph-authtool /etc/ceph/#{cluster}.client.'#{nova_user}'.keyring --create-keyring \
            --name=client.'#{nova_user}' --add-key='#{client_key}' ]
      raise 'creating nova keyring failed' unless $?.exitstatus == 0

      node['ceph']['nova-user'] = nova_user
      node['ceph']['nova-uuid'] = nova_uuid
      node.normal['ceph']['nova-secret'] = client_key
      node.save

      if system("virsh hostname &> /dev/null")
        %x[ virsh secret-define --file '#{secret_file_path}' ]
        raise 'generating secret file failed' unless $?.exitstatus == 0

        %x[ virsh secret-set-value --secret '#{nova_uuid}' --base64 '#{client_key}' ]
        raise 'importing secret file failed' unless $?.exitstatus == 0
      end

    end
  end

end

file "/etc/ceph/ceph.client.#{nova_user}.keyring" do
  owner "root"
  group node[:nova][:group]
  mode 0640
  action :touch
end
