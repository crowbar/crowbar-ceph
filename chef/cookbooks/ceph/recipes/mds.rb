#
# Copyright 2016, SUSE LINUX GmbH
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

if node.roles.include?("ceph-mon")
  include_recipe "ceph::default"
  include_recipe "ceph::conf"
else
  include_recipe "ceph::keyring"
end
include_recipe "ceph::server"

directory "/var/lib/ceph/mds/ceph-#{node["hostname"]}" do
  owner "ceph"
  group "ceph"
  mode "0750"
  recursive true
  action :create
end

execute "create mds keyring" do
  command "ceph auth get-or-create mds.#{node["hostname"]} \
             osd 'allow rwx' mds 'allow' mon 'allow profile mds' \
             -o /var/lib/ceph/mds/ceph-#{node["hostname"]}/keyring && \
           chown ceph.ceph /var/lib/ceph/mds/ceph-#{node["hostname"]}/keyring"
  not_if { File.exist?("/var/lib/ceph/mds/ceph-#{node["hostname"]}/keyring") }
end

service "ceph-mds.target" do
  action :enable
end
service "ceph.target" do
  action :enable
end

execute "create data pool" do
  # Using `rados mkpool` in order to have it pick up the default pg_num from
  # ceph.conf (compare `ceph osd pool create`, which requires the pg_num to
  # be specified on the command line)
  command "rados mkpool #{node[:ceph][:cephfs][:data_pool]}"
  not_if "rados lspools|grep -q '^#{node[:ceph][:cephfs][:data_pool]}$'"
end

execute "create metadata pool" do
  command "rados mkpool #{node[:ceph][:cephfs][:metadata_pool]}"
  not_if "rados lspools|grep -q '^#{node[:ceph][:cephfs][:metadata_pool]}$'"
end

service "ceph_mds" do
  service_name "ceph-mds@#{node["hostname"]}"
  supports restart: true, status: true
  action [:enable, :start]
  subscribes :restart, resources(template: "/etc/ceph/ceph.conf")
  notifies :run, "execute[create-cephfs]", :immediately
end

execute "create-cephfs" do
  # NOTE: not_if condition will be fragile if `ceph fs ls` output ever changes
  command "ceph fs new #{node[:ceph][:cephfs][:fs_name]} \
             #{node[:ceph][:cephfs][:metadata_pool]} #{node[:ceph][:cephfs][:data_pool]}"
  action :nothing
  not_if "ceph fs ls|grep -q 'name: #{node[:ceph][:cephfs][:fs_name]},"
end
