#
# Copyright 2017 SUSE Linux GmbH
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

return unless node["roles"].include?("monasca-agent")

if node[:monasca][:agent][:monitor_ceph]
  monasca_agent_plugin_ceph "monasca-agent ceph check" do
    built_by "crowbar-ceph"
    use_sudo true
    cluster_name "ceph" # TODO: use cluster name if it becomes variable
  end
end
