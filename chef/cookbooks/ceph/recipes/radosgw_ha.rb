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

transaction_objects = []

# stolen from radosgw.rb, sort of; we're using just the instance name
# for the pacemaker primitive, because rgw.hostname is enough to make
# it unique, and anyway we can't prefix it with "ceph-radosgw@" because
# '@' is invalid in pacemaker primitive IDs...
rgw_hostname = get_ceph_client_name(node)
service_name = "rgw.#{rgw_hostname}"

pacemaker_primitive service_name do
  # ...but we still need the full "ceph-radosgw@..." form here for systemd.
  agent "systemd:ceph-radosgw@#{service_name}"
  op node[:ceph][:ha][:radosgw][:op]
  action :update
end
transaction_objects << "pacemaker_primitive[#{service_name}]"

location_constraint = "l-#{service_name}"
pacemaker_location location_constraint do
  # I tried inf: for this node, but pacemaker would still try to start the
  # resource on other nodes when this node went down, hence the reversed
  # -inf for nodes that don't have this hostname (is there a better way
  # to do this?)
  definition "location #{location_constraint} #{service_name} " \
    "rule -inf: #uname ne #{node[:hostname]}"
  action :update
end
transaction_objects << "pacemaker_location[#{location_constraint}]"

pacemaker_transaction "ceph-radosgw" do
  cib_objects transaction_objects
  # note that this will also automatically start the resources
  action :commit_new
end

crowbar_pacemaker_sync_mark "create-ceph-radosgw_ha_resources"
