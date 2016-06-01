name "ceph-mds"
description "Ceph Metadata Server"
run_list("recipe[ceph::role_ceph_mds]")
