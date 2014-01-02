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

    nodes        = NodeObject.all
    storage_nodes = nodes.select { |n| n.intended_role == "storage" }
    controller  = nodes.detect { |n| n.intended_role == "controller" } || storage_nodes.first || nodes.first

    base["deployment"]["ceph"]["elements"] = {
        "ceph-mon" =>  [ controller.name ],
        "ceph-osd" =>  storage_nodes.map { |x| x.name },
    } unless storage_nodes.nil?

    @logger.debug("Ceph create_proposal: exiting")
    base
  end

  def apply_role_pre_chef_call(old_role, role, all_nodes)
    @logger.debug("ceph apply_role_pre_chef_call: entering #{all_nodes.inspect}")
    monitors = role.override_attributes["ceph"]["elements"]["ceph-mon"] || []
    osd_nodes = role.override_attributes["ceph"]["elements"]["ceph-osd"] || []

    @logger.debug("monitors: #{monitors.inspect}")
    @logger.debug("osd_nodes: #{osd_nodes.inspect}")
    
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
    if ((not elements.has_key?("ceph-mon") or elements["ceph-mon"].length == 0) and
        (not elements.has_key?("ceph-osd") or elements["ceph-osd"].length == 0)):
       return
    end

    errors = []

    if not elements.has_key?("ceph-mon") or elements["ceph-mon"].length < 2
      errors << "Need at least two ceph-mon nodes."
    end

    if not elements.has_key?("ceph-osd") or elements["ceph-osd"].length < 2
      errors << "Need at least two ceph-osd nodes."
    end

    if elements.has_key?("ceph-osd")
      elements["ceph-osd"].each do |n|
        node = NodeObject.find_node_by_name(n)
        roles = node.roles()

        role = "nova-multi-controller"
        if roles.include?(role) and node["nova"]["volume"]["type"] != "rados"
          errors << "Node #{n} already has the #{role} role; nodes cannot have both ceph-osd and #{role} roles if Ceph is not used for volume storage in Nova."
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
