default["ceph"]["osd"]["init_style"] = "sysvinit"
if node["platform_family"] == "suse"
  default["ceph"]["osd"]["init_style"] = "systemd"
elsif node["platform"] == "ubuntu"
  default["ceph"]["osd"]["init_style"] = "upstart"
end

default["ceph"]["mon"]["secret_file"] = "/etc/chef/secrets/ceph_mon"
