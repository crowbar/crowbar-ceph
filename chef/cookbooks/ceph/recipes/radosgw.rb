# do not include "ceph::keyring" recipe,
# when node role is "ceph-mon"
if node.roles.include?("ceph-mon")
  include_recipe "ceph::default"
  include_recipe "ceph::conf"
else
  include_recipe "ceph::keyring"
end

node["ceph"]["radosgw"]["packages"].each do |pkg|
  package pkg
end

hostname = node["hostname"]

include_recipe "ceph::radosgw_civetweb"

crowbar_pacemaker_sync_mark "wait-ceph_client_generate"

ceph_client "rgw" do
  caps("mon" => "allow rw", "osd" => "allow rwx")
  owner "root"
  group node["ceph"]["radosgw"]["group"]
  mode 0640
end

crowbar_pacemaker_sync_mark "create-ceph_client_generate"

directory "/var/lib/ceph/radosgw/ceph-radosgw.#{hostname}" do
  recursive true
  only_if { node["platform"] == "ubuntu" }
end

# needed by https://github.com/ceph/ceph/blob/master/src/upstart/radosgw-all-starter.conf
file "/var/lib/ceph/radosgw/ceph-radosgw.#{hostname}/done" do
  action :create
  only_if { node["platform"] == "ubuntu" }
end

# check if keystone is deployed (not a requirement for ceph)
unless node[:ceph][:keystone_instance].nil? || node[:ceph][:keystone_instance].empty?
  include_recipe "ceph::radosgw_keystone"
end

rgw_conf = "ceph.conf"

if node["platform_family"] == "suse"
  rgw_conf = "ceph.conf.radosgw"
  # When generating the override systemd unit file, we have to disable the
  # radosgw service so that it gets re-enabled later, thus picking up the
  # override unit file (if we didn't do this, a host that was already
  # running radosgw and was then upgraded wouldn't pick up the new unit file).
  # (see also the comments about this in conf.rb)
  # The first sed strips any existing --conf option out of the ExecStart line
  # (this was present in Hammer, but is no longer present in Jewel).  The
  # second sed tells radosgw to explicitly use our radosgw specific conf file.
  bash "generating override ceph-radosgw systemd unit file" do
    code <<-EOH
      sed -e 's%^\\(ExecStart=.*\\)\\(--conf [^ ]*\\)\\(.*\\)%\\1\\3%' \
        /usr/lib/systemd/system/ceph-radosgw@.service | \
      sed -e 's%^\\(ExecStart=.*\\)%\\1 --conf /etc/ceph/ceph.conf.radosgw%' \
         > /etc/systemd/system/ceph-radosgw@.service
      systemctl daemon-reload
      systemctl disable #{node["ceph"]["radosgw"]["service_name"]}
    EOH
    not_if do
      File.exist?("/etc/systemd/system/ceph-radosgw@.service") &&
        File.mtime("/etc/systemd/system/ceph-radosgw@.service") >
          File.mtime("/usr/lib/systemd/system/ceph-radosgw@.service")
    end
  end
end

service "radosgw" do
  service_name node["ceph"]["radosgw"]["service_name"]
  supports restart: true
  action [:enable, :start]
  subscribes :restart, "template[/etc/ceph/#{rgw_conf}]"
end

# In the systemd case, need extra targets enabled
service "ceph-radosgw.target" do
  action :enable
  only_if { File.exist?("/usr/lib/systemd/system/ceph-radosgw.target") }
end
service "ceph.target" do
  action :enable
  only_if { File.exist?("/usr/lib/systemd/system/ceph.target") }
end

if node[:ceph][:ha][:radosgw][:enabled]
  log "HA support for ceph-radosgw is enabled"
  include_recipe "ceph::radosgw_ha"
end
