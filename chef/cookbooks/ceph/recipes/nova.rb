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

ruby_block "save nova key in node attributes" do
  block do

    cinder_controller = search(:node, "roles:cinder-controller")
    if cinder_controller.length > 0
      cinder_user = cinder_controller[0][:cinder][:volume][:rbd][:user]
      cinder_pool = cinder_controller[0][:cinder][:volume][:rbd][:pool]
      cinder_uuid = cinder_controller[0][:cinder][:volume][:rbd][:uuid]
      nova_user = 'nova'

      client_key = %x[
        ceph \
          auth get-or-create-key client.'#{nova_user}' mon 'allow r' \
          osd 'allow class-read object_prefix rbd_children, allow rwx pool='#{cinder_pool}''
      ].tr("\n","")
      raise 'adding or getting nova client key failed' unless $?.exitstatus == 0

      %x[ ceph-authtool /etc/ceph/#{cluster}.client.'#{nova_user}'.keyring --create-keyring \
            --name=client.'#{nova_user}' --add-key='#{client_key}' ]
      raise 'creating nova keyring failed' unless $?.exitstatus == 0

    end
    
    FileUtils.chown('root','openstack-nova',"etc/ceph/#{cluster}.client.#{nova_user}.keyring")
    FileUtils.chmod(0640,"/etc/ceph/#{cluster}.client.#{nova_user}.keyring")
      
    node['ceph']['client-status'] = "deployed"
    node.save

    secret_file_path = "/etc/ceph/ceph-secret.xml"

    %x[ virsh secret-define --file '#{secret_file_path}' ]
    raise 'generating secret file failed' unless $?.exitstatus == 0

    %x[ virsh secret-set-value --secret '#{cinder_uuid}' --base64 '#{client_key}' ]
    raise 'importing secret file failed' unless $?.exitstatus == 0

  end
  not_if { node['ceph']['client-status'] }
end
