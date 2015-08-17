# Copyright 2014 SUSE
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

ssl_enabled = node[:ceph][:radosgw][:ssl][:enabled]

haproxy_loadbalancer "ceph-radosgw" do
  address "0.0.0.0"
  port ssl_enabled ? node["ceph"]["radosgw"]["rgw_port_ssl"] : node["ceph"]["radosgw"]["rgw_port"]
  use_ssl ssl_enabled
  servers CrowbarPacemakerHelper.haproxy_servers_for_service(node, "ceph", "ceph-radosgw", ssl_enabled ? "radosgw_ssl" : "radosgw_plain")
  action :nothing
end.run_action(:create)

# Wait for all nodes to reach this point so we know that all nodes will have
# all the required packages installed before we create the pacemaker
# resources
crowbar_pacemaker_sync_mark "sync-ceph-radosgw_before_ha"

# Avoid races when creating pacemaker resources
crowbar_pacemaker_sync_mark "wait-ceph-radosgw_ha_resources"

service_name = "ceph-radosgw"

pacemaker_primitive service_name do
  agent node[:ceph][:ha][:radosgw][:agent]
  op node[:ceph][:ha][:radosgw][:op]
  action :create
  only_if { CrowbarPacemakerHelper.is_cluster_founder?(node) }
end

pacemaker_clone "cl-#{service_name}" do
  rsc service_name
  action [:create, :start]
  only_if { CrowbarPacemakerHelper.is_cluster_founder?(node) }
end

include_recipe "crowbar-pacemaker::apache"

crowbar_pacemaker_sync_mark "create-ceph-radosgw_ha_resources"
