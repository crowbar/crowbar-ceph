#
# Copyright 2011-2013, Dell
# Copyright 2013-2014, SUSE LINUX Products GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef'

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

class CephService < PacemakerServiceObject

  def initialize(thelogger)
    super(thelogger)
    @bc_name = "ceph"
  end

  class << self
    def role_constraints
      {
        "ceph-calamari" => {
          "unique" => false,
          "count" => 1,
          "exclude_platform" => {
            "suse" => "< 12.0",
            "windows" => "/.*/"
          },
          "conflicts_with" => [ "ceph-mon", "ceph-osd", "ceph-radosgw", "nova_dashboard-server" ]
        },
        "ceph-mon" => {
          "unique" => false,
          "count" => 3,
          "exclude_platform" => {
            "suse" => "< 12.0",
            "windows" => "/.*/"
          }
        },
        "ceph-osd" => {
          "unique" => false,
          "count" => 8,
          "exclude_platform" => {
            "suse" => "< 12.0",
            "windows" => "/.*/"
          }
        },
        "ceph-radosgw" => {
          "unique" => false,
          "count" => 1,
          "exclude_platform" => {
            "suse" => "< 12.0",
            "windows" => "/.*/"
          },
          "cluster" => true
        }
      }
    end
  end

  def proposal_dependencies(role)
    answer = []
    # keystone is not hard requirement, but once ceph-radosgw+keystone is deployed, warn about keystone removal
    radosgw_nodes  = role.override_attributes[@bc_name]["elements"]["ceph-radosgw"] || []
    unless role.default_attributes[@bc_name]["keystone_instance"].blank? || radosgw_nodes.empty?
      answer << { "barclamp" => "keystone", "inst" => role.default_attributes[@bc_name]["keystone_instance"] }
    end
    answer
  end

  def create_proposal
    @logger.debug("Ceph create_proposal: entering")
    base = super

    if base["attributes"]["ceph"]["config"]["fsid"].empty?
      base["attributes"]["ceph"]["config"]["fsid"] = generate_uuid
    end

    base["attributes"][@bc_name]["keystone_instance"] = find_dep_proposal("keystone", true)

    nodes = NodeObject.all

    osd_nodes = select_nodes_for_role(nodes, "ceph-osd", "storage")
    if osd_nodes.size < 2
      osd_nodes_controller = select_nodes_for_role(nodes, "ceph-osd", "controller")
      osd_nodes_all = select_nodes_for_role(nodes, "ceph-osd")
      # avoid controllers if possible (will likely be used for mon)
      osd_nodes_no_controller = osd_nodes_all - osd_nodes_controller
      osd_nodes = [ osd_nodes, osd_nodes_no_controller, osd_nodes_all ].flatten.uniq{|n| n.name}
      osd_nodes = osd_nodes.take(2)
    end

    mon_nodes = select_nodes_for_role(nodes, "ceph-mon", "controller")

    if mon_nodes.size < 3
      mon_nodes_storage = select_nodes_for_role(nodes, "ceph-mon", "storage")
      mon_nodes_all = select_nodes_for_role(nodes, "ceph-mon")
      mon_nodes = [ mon_nodes, mon_nodes_storage, mon_nodes_all ].flatten.uniq{|n| n.name}
    end
    mon_nodes = mon_nodes.take(mon_nodes.length > 2 ? 3 : 1)

    radosgw_node = select_nodes_for_role(nodes, "ceph-radosgw", "controller").first

    # Any spare node after allocating mons and osds is fair game
    # to automatically use as the calamari server
    calamari_nodes = select_nodes_for_role(nodes, "ceph-calamari")
    calamari_nodes.reject! { |n| osd_nodes.include? n or mon_nodes.include? n }
    calamari_node = calamari_nodes.first

    base["deployment"]["ceph"]["elements"] = {
        "ceph-calamari" => calamari_node.nil? ? [] : [ calamari_node.name ],
        "ceph-mon" => mon_nodes.map { |x| x.name },
        "ceph-osd" => osd_nodes.map { |x| x.name },
        "ceph-radosgw" => radosgw_node.nil? ? [] : [ radosgw_node.name ]
    }

    @logger.debug("Ceph create_proposal: exiting")
    base
  end

  def apply_role_pre_chef_call(old_role, role, all_nodes)
    @logger.debug("ceph apply_role_pre_chef_call: entering #{all_nodes.inspect}")
    monitors = role.override_attributes["ceph"]["elements"]["ceph-mon"] || []
    osd_nodes = role.override_attributes["ceph"]["elements"]["ceph-osd"] || []

    @logger.debug("monitors: #{monitors.inspect}")
    @logger.debug("osd_nodes: #{osd_nodes.inspect}")

    radosgw_elements, radosgw_nodes, ha_enabled = role_expand_elements(role, "ceph-radosgw")

    vip_networks = ["admin", "public"]

    dirty = false
    dirty = prepare_role_for_ha_with_haproxy(role, ["ceph", "ha", "radosgw", "enabled"], ha_enabled, radosgw_elements, vip_networks)
    role.save if dirty

    # Make sure to use the storage network
    net_svc = NetworkService.new @logger

    osd_nodes.each do |n|
      net_svc.allocate_ip "default", "storage", "host", n
    end

    radosgw_nodes.each do |n|
      net_svc.allocate_ip "default", "public", "host", n
    end

    # No specific need to call sync dns here, as the cookbook doesn't require
    # the VIP of the cluster to be setup
    allocate_virtual_ips_for_any_cluster_in_networks(radosgw_elements, vip_networks)

    # Save net info in attributes if we're applying
    unless all_nodes.empty?
      node = NodeObject.find_node_by_name osd_nodes[0]
      admin_net = node.get_network_by_type("admin")
      cluster_net = node.get_network_by_type("storage")

      role.default_attributes["ceph"]["config"]["public-network"] =
        "#{admin_net['subnet']}/#{mask_to_bits(admin_net['netmask'])}"
      role.default_attributes["ceph"]["config"]["cluster-network"] =
        "#{cluster_net['subnet']}/#{mask_to_bits(cluster_net['netmask'])}"

      role.save
    end

    # electing master ceph
    unless monitors.empty?
      mons = monitors.map {|n| NodeObject.find_node_by_name n}

      master = nil
      mons.each do |mon|
        if mon[:ceph].nil?
          mon[:ceph] = {}
          mon[:ceph][:master] = false
        end
        if mon[:ceph][:master] && master.nil?
          master = mon
        else
          mon[:ceph][:master] = false
          mon.save
        end
      end
      if master.nil?
        master = mons.first
        master[:ceph][:master] = true
        master.save
      end
    end

    # estimating number of osds for ceph cluster
    disks_num = 0
    osds_in_total = 0
    unless osd_nodes.empty? || role.default_attributes["ceph"]["config"]["osds_in_total"] != 0
      osds = osd_nodes.map {|n| NodeObject.find_node_by_name n}
      osds.each do |osd|
        disks_num = osd.unclaimed_physical_drives.length
        disks_num += osd.physical_drives.select { |d, data| osd.disk_owner(osd.unique_device_for(d)) == 'Ceph' }.length
        if role.default_attributes["ceph"]["disk_mode"] == "all"
          osds_in_total += disks_num
        else
          osds_in_total += 1 if disks_num
        end
      end
      role.default_attributes["ceph"]["config"]["osds_in_total"] = osds_in_total
      role.save
    end

  end

  def apply_role_post_chef_call(old_role, role, all_nodes)
    @logger.debug("ceph apply_role_post_chef_call: entering #{all_nodes.inspect}")
    calamari = role.override_attributes["ceph"]["elements"]["ceph-calamari"] || []

    calamari.each do |n|
      node = NodeObject.find_node_by_name(n)
      node.crowbar["crowbar"] ||= {}
      node.crowbar["crowbar"]["links"] ||= {}

      for t in ['admin'] do
        unless node.get_network_by_type(t)
          node.crowbar["crowbar"]["links"].delete("Calamari Dashboard (#{t})")
          next
        end
        ip = node.get_network_by_type(t)["address"]
        node.crowbar["crowbar"]["links"]["Calamari Dashboard (#{t})"] = "http://#{ip}/"
      end

      node.save
    end
  end

  def validate_proposal_after_save proposal
    validate_at_least_n_for_role proposal, "ceph-mon", 1
    validate_count_as_odd_for_role proposal, "ceph-mon"
    validate_at_least_n_for_role proposal, "ceph-osd", 2

    osd_nodes = proposal["deployment"]["ceph"]["elements"]["ceph-osd"] || []
    mon_nodes = proposal["deployment"]["ceph"]["elements"]["ceph-mon"] || []
    radosgw_nodes = proposal["deployment"]["ceph"]["elements"]["ceph-radosgw"] || []

    NodeObject.find("roles:ceph-osd").each do |n|
      unless osd_nodes.include? n.name
        validation_error "The ceph-osd role cannot be removed from a node '#{n.name}'"
      end
    end

    unless radosgw_nodes.empty?
      ProposalObject.find_proposals("swift").each {|p|
        if (p.status == "ready") || (p.status == "pending")
          validation_error("Swift is already deployed. Only one of Ceph with RadosGW and Swift can be deployed at any time.")
        end
      }
    end

    nodes = NodeObject.find("roles:provisioner-server")
    unless nodes.nil? or nodes.length < 1
      provisioner_server_node = nodes[0]
      if provisioner_server_node[:platform] == "suse"
        if (!provisioner_server_node[:provisioner][:suse][:storage_available] rescue true)
          validation_error "The SUSE Enterprise Storage repositories have not been setup."
        end
      end
    end

    # Make sure that all nodes with radosgw role have the same other ceph roles:
    # chef-client will first run on nodes with ceph-osd/ceph-mon and will execute the HA bits for radosgw,
    # causing the sync between nodes to fail if the other cluster nodes don't have the same roles
    if !radosgw_nodes.empty? && is_cluster?(radosgw_nodes.first)
      rgw_nodes         = PacemakerServiceObject.expand_nodes(radosgw_nodes.first)
      additional_roles  = {}
      rgw_nodes.each do |n|
        additional_roles["osd"] = true if osd_nodes.include?(n)
        additional_roles["mon"] = true if mon_nodes.include?(n)
      end
      rgw_nodes.each do |n|
        if additional_roles["osd"] && !osd_nodes.include?(n)
          validation_error("Nodes in cluster must have same roles: node #{n} is missing ceph-osd role.")
        end
        if additional_roles["mon"] && !mon_nodes.include?(n)
          validation_error("Nodes in cluster must have same roles: node #{n} is missing ceph-mon role.")
        end
      end
    end

    min_size_gb = proposal["attributes"]["ceph"]["osd"]["min_size_gb"]
    min_size_blocks = min_size_gb * 1024 * 1024 * 2

    nodes_without_suitable_drives = proposal["deployment"][@bc_name]["elements"]["ceph-osd"].select do |node_name|
      node = NodeObject.find_node_by_name(node_name)
      if node.nil?
          false
      else
          disks_count = node.unclaimed_physical_drives.select { |d, data| data['size'].to_i >= min_size_blocks }.length
          disks_count += node.physical_drives.select { |d, data| node.disk_owner(node.unique_device_for(d)) == 'Ceph' }.length
          disks_count == 0
      end
    end

    unless nodes_without_suitable_drives.empty?
      validation_error("Nodes #{nodes_without_suitable_drives.to_sentence} for ceph-osd role are missing at least one unclaimed disk larger than #{min_size_gb}GB")
    end

    super
  end

  def generate_uuid
    ary = SecureRandom.random_bytes(16).unpack("NnnnnN")
    ary[2] = (ary[2] & 0x0fff) | 0x4000
    ary[3] = (ary[3] & 0x3fff) | 0x8000
    "%08x-%04x-%04x-%04x-%04x%08x" % ary
  end
end
