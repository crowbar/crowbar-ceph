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

  class << self
    def role_constraints
      @role_constraints ||= begin
        {
          "ceph-mon" => {
            "unique" => false,
            "count" => 3
          },
          "ceph-osd" => {
            "unique" => false,
            "count" => 8
          }
        }
      end
    end
  end

  def create_proposal
    @logger.debug("Ceph create_proposal: entering")
    base = super

    nodes        = NodeObject.all
    nodes.delete_if { |n| n.nil? or n.admin? }

    storage_nodes = nodes.select { |n| n.intended_role == "storage" }
    controller_nodes = nodes.select { |n| n.intended_role == "controller"}
    if controller_nodes.size < 3
      controller_nodes = [ controller_nodes, storage_nodes, nodes ].flatten.uniq{|n| n.name}
      controller_nodes = controller_nodes.take(3)
    end

    if storage_nodes.size < 2
      storage_nodes = [ storage_nodes, controller_nodes, nodes ].flatten.uniq{|n| n.name}
      storage_nodes = storage_nodes.take(2)
    end

    base["deployment"]["ceph"]["elements"] = {
        "ceph-mon" => controller_nodes.map { |x| x.name },
        "ceph-osd" => storage_nodes.map{ |x| x.name },
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
    validate_at_least_n_for_role proposal, "ceph-mon", 1
    validate_at_least_n_for_role proposal, "ceph-osd", 2

    super
  end
end
