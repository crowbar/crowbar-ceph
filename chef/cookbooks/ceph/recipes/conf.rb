raise "fsid must be set in config" if node["ceph"]["config"]['fsid'].nil?

mon_nodes = get_mon_nodes
mon_addresses = get_mon_addresses

mon_init = []
mon_nodes.each do |monitor|
    mon_init << monitor.name.split('.')[0]
end

def mask_to_bits(mask)
  octets = mask.split(".")
  count = 0
  octets.each do |octet|
    break if octet == "0"
    c = 1 if octet == "128"
    c = 2 if octet == "192"
    c = 3 if octet == "224"
    c = 4 if octet == "240"
    c = 5 if octet == "248"
    c = 6 if octet == "252"
    c = 7 if octet == "254"
    c = 8 if octet == "255"
    count = count + c
  end

  count
end

cluster_mask = mask_to_bits(Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "storage").netmask)
cluster_network = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "storage").subnet + "/#{cluster_mask}"

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
    :public_network => cluster_network,
    :cluster_network => cluster_network
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
