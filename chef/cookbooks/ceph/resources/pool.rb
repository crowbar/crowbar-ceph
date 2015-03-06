actions :create
default_action :create

attribute :name, :kind_of => String, :name_attribute => true

# Allow using non-standard locations for ceph.conf and admin keyring.
# This can happen when using and external ceph cluster not deployed with crowbar
attribute :ceph_conf, :kind_of => String, :default => '/etc/ceph/ceph.conf'
attribute :admin_keyring, :kind_of => String, :default => '/etc/ceph/ceph.client.admin.keyring'

# what pool should be created in the ceph cluster
attribute :pool_name, :kind_of => String
attribute :pg_num, :kind_of => Integer
