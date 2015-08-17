name "ceph-glance"
description "Ceph Glance Client"
run_list(
        'recipe[ceph::glance]'
)
