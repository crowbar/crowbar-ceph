raise "fsid must be set in config" if node["ceph"]["config"]['fsid'].nil?

mon_nodes = get_mon_nodes
osd_nodes = get_osd_nodes
mon_addresses = get_mon_addresses

mon_init = []
mon_nodes.each do |monitor|
    mon_init << monitor.name.split('.')[0]
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
    :osd_nodes_count => osd_nodes.length,
    :public_network => node["ceph"]["config"]["public-network"],
    :cluster_network => node["ceph"]["config"]["cluster-network"]
  )
  mode '0644'
end

directory "/var/run/ceph" do
  owner "root"
  group "root"
  mode "0755"
  action :create
end

directory "/var/log/ceph" do
  owner "root"
  group "root"
  mode "0755"
  action :create
end
