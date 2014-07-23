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

haproxy_loadbalancer "ceph-radosgw" do
  address "0.0.0.0"
  port node["ceph"]["radosgw"]["rgw_port"]
  use_ssl false
  servers CrowbarPacemakerHelper.haproxy_servers_for_service(node, "ceph", "ceph-radosgw", "radosgw_plain")
  action :nothing
end.run_action(:create)

# FIXME the rest (=pacemaker parts) should be only done when apache primitive does not exist yet
# (might be created by other barclamp)

# Wait for all nodes to reach this point so we know that all nodes will have
# all the required packages installed before we create the pacemaker
# resources
crowbar_pacemaker_sync_mark "sync-ceph-radosgw_before_ha"

# Avoid races when creating pacemaker resources
crowbar_pacemaker_sync_mark "wait-ceph-radosgw_ha_resources"

agent_name = "ocf:heartbeat:apache"
apache_op = {}
apache_op["monitor"] = {}
apache_op["monitor"]["interval"] = "10s"

service_name = "apache"

pacemaker_primitive service_name do
  agent agent_name
  params ({
    "statusurl" => "http://127.0.0.1:#{node[:ceph][:radosgw][:ha][:ports][:plain]}/server-status"
  })
  op    apache_op
  action :create
end

pacemaker_clone "cl-#{service_name}" do
  rsc service_name
  action [ :create, :start ]
end

crowbar_pacemaker_sync_mark "create-ceph-radosgw_ha_resources"

# Override service provider for apache2 resource defined in apache2 cookbook
resource = resources(:service => "apache2")
resource.provider(Chef::Provider::CrowbarPacemakerService)
