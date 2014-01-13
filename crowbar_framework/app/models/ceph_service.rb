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
    super(thelogger)
    @bc_name = "ceph"
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
    validate_at_least_n_for_role proposal, "ceph-mon", 2
    validate_at_least_n_for_role proposal, "ceph-osd", 2

    super
  end
end
