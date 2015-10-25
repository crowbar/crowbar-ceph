name "ceph-radosgw"
description "Ceph RADOS Gateway"
run_list("recipe[ceph::role_ceph_radosgw]")
