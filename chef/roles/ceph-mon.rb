name "ceph-mon"
description "Ceph Monitor"
run_list("recipe[ceph::role_ceph_mon]")
