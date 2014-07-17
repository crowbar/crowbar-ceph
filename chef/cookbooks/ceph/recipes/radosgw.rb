include_recipe "ceph::default"
include_recipe "ceph::conf"

node['ceph']['radosgw']['packages'].each do |pck|
  package pck
end

hostname = node['hostname']

file "/var/log/ceph/radosgw.log" do
  owner node[:apache][:user]
  group node[:apache][:group]
end

# FIXME the check for done file should not be needed: let chef run everything all the time
if !::File.exist?("/var/lib/ceph/radosgw/ceph-radosgw.#{hostname}/done")

  include_recipe "ceph::radosgw_apache2"

  ceph_client 'radosgw' do
    caps('mon' => 'allow rw', 'osd' => 'allow rwx')
    group node[:apache][:group]
  end

  # currently, after ceph_client above, caps are visible in 'ceph auth list', but not in 'ceph-authtool -l /etc/ceph/ceph.client.radosgw.#{hostname}.keyring'
  # FIXME check if this is really a problem and the extra call of ceph-authtool is needed
  execute "add key capabilities" do
    command "ceph-authtool -n client.radosgw.#{hostname} /etc/ceph/ceph.client.radosgw.#{hostname}.keyring --cap osd 'allow rwx' --cap mon 'allow rw'"
  end

  directory "/var/lib/ceph/radosgw/ceph-radosgw.#{hostname}" do
    recursive true
  end

  file "/var/lib/ceph/radosgw/ceph-radosgw.#{hostname}/done" do
    action :create
  end

  service 'radosgw' do
    service_name node['ceph']['radosgw']['service_name']
    supports :restart => true
    action [:enable, :start]
    subscribes :restart, "template[/etc/ceph/ceph.conf]"
  end
else
  Log.info('Rados Gateway already deployed')
end

# check if keystone is deployed (not a requirement for ceph)
if node[:ceph][:keystone_instance]
  include_recipe "ceph::radosgw_keystone"
end
