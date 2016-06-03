raise "fsid must be set in config" if node["ceph"]["config"]["fsid"].nil?

mon_nodes = get_mon_nodes
osd_nodes = get_osd_nodes
mon_addr = get_mon_addresses

mon_init = []
mon_nodes.each do |monitor|
    mon_init << monitor.name.split(".")[0]
end

unless node["platform_family"] == "suse"
  # These directories are all created by the ceph packages on SUSE distros.
  # TODO: Check if this is true for other distros (it probably is)
  directory "/etc/ceph" do
    owner "root"
    group "root"
    mode "0755"
    action :create
  end

  directory "/var/run/ceph" do
    owner "ceph"
    group "ceph"
    mode "0770"
    action :create
  end

  directory "/var/log/ceph" do
    owner "ceph"
    group "ceph"
    mode "3770"
    action :create
  end
end

is_rgw = node.roles.include?("ceph-radosgw")
rgw_port = rgw_pemfile = nil
if is_rgw
  rgw_use_ssl = node["ceph"]["radosgw"]["ssl"]["enabled"]
  if node["ceph"]["ha"]["radosgw"]["enabled"]
    rgw_port = rgw_use_ssl ? node["ceph"]["ha"]["ports"]["radosgw_ssl"] : node["ceph"]["ha"]["ports"]["radosgw_plain"]
  else
    rgw_port = rgw_use_ssl ? node["ceph"]["radosgw"]["rgw_port_ssl"] : node["ceph"]["radosgw"]["rgw_port"]
  end
  rgw_pemfile = node["ceph"]["radosgw"]["ssl"]["pemfile"] if rgw_use_ssl
end

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

case num_osds
when 0
  # This can only happen if the search in get_osd_nodes() doesn't find any OSDs, which
  # should be impossible.  But if it *does* fail, pg_num needs to be set to something,
  # so let's run with the default of 8 (see "osd pool default pg num" at
  # http://docs.ceph.com/docs/master/rados/configuration/pool-pg-config-ref/)
  Chef::Log.warn("Ceph recipe invoked but there are no OSDs!  Defaulting to pg_num = 8")
  pg_num = 8
else
  # There'll always be at least the default rbd pool (which Ceph always creates
  # with 64 PGs, irrespective of what "osd pool default pg num" is set to)
  expected_pools = 1

  rgw_host = search(:node, "roles:ceph-radosgw")
  # RGW will use up to 14 pools (try "RGW only" with http://ceph.com/pgcalc/)
  # These are not all created immediately though.  Six will be created when
  # the radosgw daemon starts for the first time.  The swift pool(s) will be
  # created when you create a swift subuser for the first time, and the usage
  # pool will only be created if the usage log is explicitly enabled.  Here,
  # to be conservative, we're assuming the full 14 pools will be used for RGW
  # deployments.
  expected_pools += 14 unless rgw_host.empty?

  mds_host = search(:node, "roles:ceph-mds")
  # If there's a ceph MDS (which actually isn't implemented in barclamp yet,
  # but might be in future), there'll be two more pools
  expected_pools += 2 unless mds_host.empty?

  # Figure out a sane number for "osd pool default pg num" based on the logic
  # at http://ceph.com/pgcalc/ -- for any given number of expected pools, this
  # results in "about 100" PGs per OSD, but experimentation indicates it can
  # go as low as 70 and as high as 150, depending on the exact number of OSDs
  # and expected number of pools.
  pg_calc = (100 * num_osds * (1.0 / expected_pools)) / rep_num
  # Get nearest power of 2
  pg_num = 2**Math.log2(pg_calc).round
  # Edge case with >=50 pools and 1 OSD gives pg_num of less than 1
  pg_num = 1 if pg_num < 1
  # If nearest power of 2 is more than 25% below original value, use next highest power
  pg_num *= 2 if pg_num < (pg_calc * 0.75)
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
    rgw_port: rgw_port,
    rgw_pemfile: rgw_pemfile,
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

