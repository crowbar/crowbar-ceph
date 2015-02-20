actions :create
default_action :create

attribute :name, :kind_of => String, :name_attribute => true

# Whether we have ceph cluster deployed with non standard configuration
# and ceph.conf and admin keyring is placed somewhere else than in /etc/ceph
# This can happened when we want to use external ceph cluster deployed 
# without crowbar
attribute :ceph_conf, :kind_of => String, :default => '/etc/ceph/ceph.conf'
attribute :admin_keyring, :kind_of => String, :default => '/etc/ceph/ceph.client.admin.keyring'

# what pool should be created in the ceph cluster
attribute :pool_name, :kind_of => String
attribute :pg_num, :kind_of => Integer
