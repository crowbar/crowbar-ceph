default["ceph"]["mon"]["init_style"] = "sysvinit"
if node["platform_family"] == "suse"
  default["ceph"]["mon"]["init_style"] = "systemd"
elsif node["platform"] == "ubuntu"
  default["ceph"]["mon"]["init_style"] = "upstart"
end

default["ceph"]["mon"]["secret_file"] = "/etc/chef/secrets/ceph_mon"
