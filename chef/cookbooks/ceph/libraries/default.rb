require "ipaddr"
require "json"
require "timeout"

def is_crowbar?()
  return defined?(Chef::Recipe::Barclamp) != nil
end

def get_ceph_client_name(cnode)
  if cnode["ceph"] && cnode["ceph"]["client_network"]
    net_name = cnode["ceph"]["client_network"]
  elsif node["ceph"] && node["ceph"]["client_network"]
    net_name = node["ceph"]["client_network"]
  else
    mons = get_mon_nodes
    net_name = mons[0]["ceph"]["client_network"]
  end
  node_name = cnode["hostname"]
  if net_name == "admin"
    node_name
  else
    net_name + "." + node_name
  end
end

def get_mon_nodes(extra_search=nil)
  if is_crowbar?
    mon_roles = search(:role, "name:crowbar-* AND run_list_map:ceph-mon")
    if not mon_roles.empty?
      search_string = mon_roles.map { |role_object| "roles:"+role_object.name }.join(" OR ")
    else
      return []
    end
  else
    search_string = "roles:ceph-mon AND chef_environment:#{node.chef_environment}"
  end

  if not extra_search.nil?
    search_string = "(#{search_string}) AND (#{extra_search})"
  end
  mons = search(:node, search_string)

  begin
    Timeout.timeout(60) do
      while mons.empty?
        mons = search(:node, search_string)
        sleep(2)
      end
    end
  rescue Timeout::Error
    Chef::Log.warn("No monitor nodes were found within a minute")
  end

  return mons
end

# If public-network is specified
# we need to search for the monitor IP
# in the node environment.
# 1. We look if the network is IPv6 or IPv4
# 2. We look for a route matching the network
# 3. We grab the IP and return it with the port
def find_node_ip_in_network(network, nodeish=nil)
  nodeish = node unless nodeish
  net = IPAddr.new(network)
  nodeish["network"]["interfaces"].each do |iface|
    if iface[1]["routes"].nil?
      next
    end
    if net.ipv4?
      iface[1]["routes"].each_with_index do |route, index|
        if iface[1]["routes"][index]["destination"] == network
          return "#{iface[1]["routes"][index]["src"]}:6789"
        end
      end
    else
      # Here we are getting an IPv6. We assume that
      # the configuration is stateful.
      # For this configuration to not fail in a stateless
      # configuration, you should run:
      #  echo "0" > /proc/sys/net/ipv6/conf/*/use_tempaddr
      # on each server, this will disabe temporary addresses
      # See: http://en.wikipedia.org/wiki/IPv6_address#Temporary_addresses
      iface[1]["routes"].each_with_index do |route, index|
        if iface[1]["routes"][index]["destination"] == network
          iface[1]["addresses"].each do |k,v|
            if v["scope"] == "Global" and v["family"] == "inet6"
              return "[#{k}]:6789"
            end
          end
        end
      end
    end
  end
end

def get_mon_addresses()
  mon_ips = []
  node_name = get_ceph_client_name(node)
  if File.exist?("/var/run/ceph/ceph-mon.#{node_name}.asok")
    mon_ips = get_quorum_members_ips()
  else
    mons = []
    # make sure if this node runs ceph-mon, it's always included even if
    # search is laggy; put it first in the hopes that clients will talk
    # primarily to local node
    if node["roles"].include? "ceph-mon"
      mons << node
    end

    mons += get_mon_nodes()
    if is_crowbar?
      mon_ips = mons.map do |node|
        Chef::Recipe::Barclamp::Inventory.get_network_by_type(
          node, node["ceph"]["client_network"]
        ).address
      end
    else
      if node["ceph"]["config"] && node["ceph"]["config"]["public-network"]
        mon_ips = mons.map { |nodeish| find_node_ip_in_network(node["ceph"]["config"]["public-network"], nodeish) }
      else
        mon_ips = mons.map { |node| node["ipaddress"] + ":6789" }
      end
    end
  end
  return mon_ips.uniq
end

def get_quorum_members_ips()
  mon_ips = []
  node_name = get_ceph_client_name(node)
  mon_status = `ceph --admin-daemon /var/run/ceph/ceph-mon.#{node_name}.asok mon_status`
  raise "getting quorum members failed" unless $?.exitstatus == 0

  mons = JSON.parse(mon_status)["monmap"]["mons"]
  mons.each do |k|
    mon_ips.push(k["addr"][0..-3])
  end
  return mon_ips
end

QUORUM_STATES = ["leader", "peon"]
def have_quorum?()
  # "ceph auth get-or-create-key" would hang if the monitor wasn't
  # in quorum yet, which is highly likely on the first run. This
  # helper lets us delay the key generation into the next
  # chef-client run, instead of hanging.
  #
  # Also, as the UNIX domain socket connection has no timeout logic
  # in the ceph tool, this exits immediately if the ceph-mon is not
  # running for any reason; trying to connect via TCP/IP would wait
  # for a relatively long timeout.
  node_name = get_ceph_client_name(node)
  mon_status = `ceph --admin-daemon /var/run/ceph/ceph-mon.#{node_name}.asok mon_status`
  raise "getting monitor state failed" unless $?.exitstatus.zero?
  state = JSON.parse(mon_status)["state"]
  QUORUM_STATES.include?(state)
end

def get_osd_id(device)
  osd_path = %x[mount | grep #{device} | awk '{print $3}'].tr("\n","")
  osd_id = %x[cat #{osd_path}/whoami].tr("\n","")
  return osd_id
end

def get_osd_nodes()
  osds = []
  if is_crowbar?
    osd_roles = search(:role, "name:crowbar-* AND run_list_map:ceph-osd")
    if not osd_roles.empty?
      search_string = osd_roles.map { |role_object| "roles:"+role_object.name }.join(" OR ")
    else
      return []
    end
  else
    search_string = "roles:ceph-osd AND chef_environment:#{node.chef_environment}"
  end

  search(:node, search_string).each do |node|
    osd = {}
    osd[:hostname] = node.name.split(".")[0]
    osds << osd
  end

  return osds
end
