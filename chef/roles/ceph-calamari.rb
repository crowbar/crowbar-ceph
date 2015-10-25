name "ceph-calamari"
description "Ceph Calamari Server"
run_list("recipe[ceph::role_ceph_calamari]")
