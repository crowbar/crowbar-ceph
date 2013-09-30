include_recipe "ceph::default"
include_recipe "ceph::conf"

# TODO cluster name
cluster = 'ceph'

admin_secret = node["ceph"]["admin-secret"]

execute "create admin keyring" do
  command "ceph-authtool --create-keyring /etc/ceph/keyring --name=client.admin --add-key='#{admin_secret}'"
end

ruby_block "save cinder key in node attributes" do
  block do
    client_key = %x[
      ceph \
        auth get-or-create-key client.cinder mon 'allow r' \
        osd 'allow class-read object_prefix rbd_children, allow rwx pool=volumes, allow rwx pool=images'
    ]
    raise 'adding or getting client.cinder key failed' unless $?.exitstatus == 0
    node.normal['cinder-secret'] = client_key
    node.save
  end
  not_if { node['ceph']['cinder-secret'] }
end

cinder_secret = node["ceph"]["cinder_secret"]

execute "format as keyring" do
  command "ceph-authtool '/etc/ceph/client.cinder.keyring' --create-keyring --name=client.cinder.keyring --add-key='#{cinder_secret}'"
  creates "/etc/ceph/client.cinder.keyring"
end

execute "create new pool" do
  command "ceph osd pool create volumes 64"
end
