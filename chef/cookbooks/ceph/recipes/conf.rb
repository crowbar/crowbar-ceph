raise "fsid must be set in config" if node["ceph"]["config"]["fsid"].nil?

mon_nodes = get_mon_nodes
osd_nodes = get_osd_nodes
mon_addr = get_mon_addresses

mon_init = []
mon_nodes.each do |monitor|
    mon_init << monitor.name.split(".")[0]
end

directory "/etc/ceph" do
  owner "root"
  group "root"
  mode "0755"
  action :create
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

is_rgw = node.roles.include?("ceph-radosgw")

keystone_settings = {}
if is_rgw && !(node[:ceph][:keystone_instance].nil? || node[:ceph][:keystone_instance].empty?)
  keystone_settings = KeystoneHelper.keystone_settings(node, @cookbook_name)
end

if node["ceph"]["config"]["replicas_number"] == 0
  rep_num = [osd_nodes.length, 3].min
else
  rep_num = node["ceph"]["config"]["replicas_number"]
end

if node["ceph"]["config"]["osds_in_total"] == 0
  num_osds = osd_nodes.length
else
  num_osds = node["ceph"]["config"]["osds_in_total"]
end

# calculate pg_num based on documentation
# http://ceph.com/docs/master/rados/operations/placement-groups/
case num_osds
when 1..4
  pg_num = 128
when 5..9
  pg_num = 512
when 10..49
  pg_num = 4096
else
  # Ensure you have a realistic number of placement groups. We recommend
  # approximately 100 per OSD. E.g., total number of OSDs multiplied by 100
  # divided by the number of replicas (i.e., osd pool default size).
  # The result should be rounded up to the nearest power of two.
  pg_num = 2 ** Math.log2(num_osds * 100 / rep_num).round
end

template "/etc/ceph/ceph.conf" do
  source "ceph.conf.erb"
  variables(
    mon_initial: mon_init,
    mon_addresses: mon_addr,
    pool_size: rep_num,
    pool_pg_num: pg_num,
    osd_nodes_count: osd_nodes.length,
    public_network: node["ceph"]["config"]["public-network"],
    cluster_network: node["ceph"]["config"]["cluster-network"],
    is_rgw: is_rgw,
    keystone_settings: keystone_settings
  )
  mode "0644"
end

# Need salt minion on osd and mon nodes to hook up to calamari.  Note: in one
# early test (where calamari role was assigned last) it seems one node didn't
# find the calamari server, presumably because everything deployed all at once
# and maybe the calamari role hadn't been assigned in time?  I haven't been
# able to reproduce this, but it seems safest to have the calamari role
# assigned first, just in case, hence the change to put ceph-calamari first in
# element_order and element_run_list_order.
calamari_host = search(:node, "roles:ceph-calamari")
if calamari_host.empty?
  Chef::Log.info("Not deploying salt-minion (no host with ceph-calamari role found)")
elsif node.roles.include?("ceph-osd") || node.roles.include?("ceph-mon")
  package "salt-minion"
  template "/etc/salt/minion.d/calamari.conf" do
    source "calamari.conf.erb"
    variables(
      calamari_host: calamari_host[0]["fqdn"]
    )
    mode "0644"
  end
  service "salt-minion" do
    supports restart: true, status: true
    action [:enable, :start]
    subscribes :restart, resources(template: "/etc/salt/minion.d/calamari.conf")
  end
end

