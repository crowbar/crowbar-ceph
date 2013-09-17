# Copyright 2011, Dell
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
require 'chef'

class CephService < ServiceObject

  def initialize(thelogger)
    @bc_name = "ceph"
    @logger = thelogger
  end

  def create_proposal
    @logger.debug("Ceph create_proposal: entering")
    base = super
    @logger.debug("Ceph create_proposal: exiting")
    base
  end

  def apply_role_pre_chef_call(old_role, role, all_nodes)
    @logger.debug("ceph apply_role_pre_chef_call: entering #{all_nodes.inspect}")
    master_mon = role.override_attributes["ceph"]["elements"]["ceph-mon-master"] || []
    monitors = role.override_attributes["ceph"]["elements"]["ceph-mon"] || []
    monitors += master_mon
    osd_nodes = role.override_attributes["ceph"]["elements"]["ceph-store"] || []
    devices = role.default_attributes["ceph"]["devices"] || []

    if old_role
      old_osd_nodes = old_role.override_attributes["ceph"]["elements"]["ceph-store"] || []
    else
      old_osd_nodes = []
    end

    @logger.debug("master_mon: #{master_mon.inspect}")
    @logger.debug("monitors: #{monitors.inspect}")
    @logger.debug("devices: #{devices.inspect}")
    @logger.debug("osd_nodes: #{osd_nodes.inspect}")
    @logger.debug("old_osd_nodes: #{old_osd_nodes.inspect}")
    @logger.debug("role: #{role.inspect}")
    @logger.debug("old_role: #{old_role.inspect}")
    
    role.override_attributes["ceph"]["monitors"] = monitors
    role.override_attributes["ceph"]["osd_nodes"] = {}
    role.override_attributes["ceph"]["rack"] = "unknownrack"

    if old_role
      role.override_attributes["ceph"]["num_osds"] = old_role.override_attributes["ceph"]["num_osds"]
    else
      role.override_attributes["ceph"]["num_osds"] = 0
    end

    osd_count = role.override_attributes["ceph"]["num_osds"]

    # just take the remaining osd_nodes
    (old_osd_nodes & osd_nodes).each do |osd_node|
      role.override_attributes["ceph"]["osd_nodes"]["#{osd_node}"] = old_role.override_attributes["ceph"]["osd_nodes"]["#{osd_node}"]
    end

    # create new osds on new osd nodes
    (osd_nodes - old_osd_nodes).each do |osd_node|
      node_hash = {}
      devices.each do |device|
        node_hash["#{osd_count}"] = device  
        @logger.debug("new osd_node: #{osd_node}, #{device}, #{osd_count}")
        osd_count += 1
      end
      role.override_attributes["ceph"]["osd_nodes"]["#{osd_node}"] = node_hash
      role.override_attributes["ceph"]["num_osds"] = osd_count
    end
    role.save

    # Make sure to use the storage network
    net_svc = NetworkService.new @logger
           
    all_nodes.each do |n|
      net_svc.allocate_ip "default", "storage", "host", n
    end
  end

  def validate_proposal_after_save proposal
    super

    elements = proposal["deployment"]["ceph"]["elements"]

    # accept proposal with no allocated node -- ie, initial state
    if ((not elements.has_key?("ceph-mon-master") or elements["ceph-mon-master"].length == 0) and
        (not elements.has_key?("ceph-mon") or elements["ceph-mon"].length == 0) and
        (not elements.has_key?("ceph-store") or elements["ceph-store"].length == 0)):
       return
    end

    errors = []

#    if proposal["attributes"]["ceph"]["devices"].length < 1
#      errors << "Need a list of devices to use on ceph-store nodes in the raw attributes."
#    end

#    if not elements.has_key?("ceph-mon-master") or elements["ceph-mon-master"].length != 1
#      errors << "Need one (and only one) ceph-mon-master node."
#    end

#    if not elements.has_key?("ceph-mon") or elements["ceph-mon"].length % 2 != 0
#      errors << "Need multiple of two ceph-mon nodes."
#    end

#    if not elements.has_key?("ceph-store") or elements["ceph-store"].length < 2
#      errors << "Need at least two ceph-store nodes."
#    end

#    if (elements.has_key?("ceph-mon") and
#        elements.has_key?("ceph-mon-master") and elements["ceph-mon-master"].length > 0 and
#        elements["ceph-mon"].include? elements["ceph-mon-master"][0])
#      errors << "Node cannot be a member of ceph-mon and ceph-mon-master at the same time."
#    end

    if elements.has_key?("ceph-store")
      elements["ceph-store"].each do |n|
        node = NodeObject.find_node_by_name(n)
        roles = node.roles()

        role = "nova-multi-controller"
        if roles.include?(role) and node["nova"]["volume"]["type"] != "rados"
          errors << "Node #{n} already has the #{role} role; nodes cannot have both ceph-store and #{role} roles if Ceph is not used for volume storage in Nova."
        end

        role = "swift-storage"
        if roles.include?(role)
          errors << "Node #{n} already has the #{role} role; nodes cannot have both ceph-store and #{role} roles."
        end
      end
    end

    if errors.length > 0
      raise Chef::Exceptions::ValidationFailed.new(errors.join("\n"))
    end
  end
end
