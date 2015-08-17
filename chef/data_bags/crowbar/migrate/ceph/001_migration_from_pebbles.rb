def upgrade ta, td, a, d
  a["disk_mode"] = a["disk-mode"] || ta["disk_mode"]
  a["config"] = ta["config"]
  a["monitor-secret"] = ta["monitor-secret"]
  a["admin-secret"] = ta["admin-secret"]
  a.delete("disk-mode")
  a.delete("devices")

  d["element_states"] = td["element_states"]
  d["element_order"] = td["element_order"]
  d["element_run_list_order"] = td["element_run_list_order"]
  unless d["elements"]["ceph-mon-master"].nil?
    d["elements"]["ceph-mon"] = [d["elements"]["ceph-mon-master"], d["elements"]["ceph-mon"] || []].flatten
    d["elements"].delete("ceph-mon-master")
  end
  unless d["elements"]["ceph-store"].nil?
    d["elements"]["ceph-osd"] = d["elements"]["ceph-store"]
    d["elements"].delete("ceph-store")
  end

  return a, d
end

def downgrade ta, td, a, d
  a["devices"] = ta["devices"]
  a["disk-mode"] = ta["disk_mode"]
  a.delete("disk_mode")
  a.delete("config")
  a.delete("monitor-secret")
  a.delete("admin-secret")

  d["element_states"] = td["element_states"]
  d["element_order"] = td["element_order"]
  d["element_run_list_order"] = td["element_run_list_order"]
  unless d["elements"]["ceph-mon"].nil?
    d["elements"]["ceph-mon-master"] = d["elements"]["ceph-mon"].pop(1)
  end
  unless d["elements"]["ceph-osd"].nil?
    d["elements"]["ceph-store"] = d["elements"]["ceph-osd"]
    d["elements"].delete("ceph-osd")
  end

  return a, d
end
