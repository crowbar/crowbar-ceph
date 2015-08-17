name "ceph-cinder"
description "Ceph Cinder Client"
run_list(
        "recipe[ceph::cinder]"
)
