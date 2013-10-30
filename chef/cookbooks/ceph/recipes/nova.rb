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

if !File.exists?("/etc/ceph/keyring")

  admin_secret = node["ceph"]["admin-secret"]

  execute "create admin keyring" do
    command "ceph-authtool --create-keyring /etc/ceph/keyring --name=client.admin --add-key='#{admin_secret}'"
  end

end


cinder_controller = search(:node, "roles:cinder-controller")
if cinder_controller.length > 0
  cinder_user = cinder_controller[0][:cinder][:volume][:rbd][:user]
  cinder_pool = cinder_controller[0][:cinder][:volume][:rbd][:pool]
  cinder_uuid = cinder_controller[0][:cinder][:volume][:rbd][:secret_uuid]
  nova_user = node['nova']['ceph']['user']

  secret_file_path = "/etc/ceph/ceph-secret.xml"

  file secret_file_path do
    owner "root"
    group "root"
    mode "0640"
    content "<secret ephemeral='no' private='no'> <uuid>#{cinder_uuid}</uuid><usage type='ceph'> <name>client.#{nova_user} secret</name> </usage> </secret>"
  end #file secret_file_path

  ruby_block "save nova key in node attributes" do
    block do
    
      Chef::Log.info("BACADebug cinder_pool #{cinder_pool} nova_user #{nova_user}")
     
      client_key = %x[
        ceph \
          auth get-or-create-key client.'#{nova_user}' mon 'allow r' \
         osd 'allow class-read object_prefix rbd_children, allow rwx pool='#{cinder_pool}''
      ].tr("\n","")
      raise 'adding or getting nova client key failed' unless $?.exitstatus == 0

      %x[ ceph-authtool /etc/ceph/#{cluster}.client.'#{nova_user}'.keyring --create-keyring \
            --name=client.'#{nova_user}' --add-key='#{client_key}' ]
      raise 'creating nova keyring failed' unless $?.exitstatus == 0

      FileUtils.chown('root','openstack-nova',"etc/ceph/#{cluster}.client.#{nova_user}.keyring")
      FileUtils.chmod(0640,"/etc/ceph/#{cluster}.client.#{nova_user}.keyring")
      
      node['ceph']['nova-secret'] = client_key
      node.save

      if File.exists?("/usr/bin/virsh")
        %x[ virsh secret-define --file '#{secret_file_path}' ]
        raise 'generating secret file failed' unless $?.exitstatus == 0

        %x[ virsh secret-set-value --secret '#{cinder_uuid}' --base64 '#{client_key}' ]
        raise 'importing secret file failed' unless $?.exitstatus == 0
      end

    end
    not_if { node['ceph']['nova-secret'] }
  end

end
