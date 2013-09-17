raise "fsid must be set in config" if node["ceph"]["config"]['fsid'].nil?

mon_nodes = get_mon_nodes()
mon_addresses = get_mon_addresses()

mon_init = []
mon_nodes.each do |monitor|
    mon_init << monitor.name.split('.')[0]
end

is_rgw = false
if node['roles'].include? 'ceph-radosgw'
  is_rgw = true
end

directory "/etc/ceph" do
  owner "root"
  group "root"
  mode "0755"
  action :create
end

template '/etc/ceph/ceph.conf' do
  source 'ceph.conf.erb'
  variables(
    :mon_initial => mon_init,
    :mon_addresses => mon_addresses,
    :is_rgw => is_rgw
  )
  mode '0644'
end
