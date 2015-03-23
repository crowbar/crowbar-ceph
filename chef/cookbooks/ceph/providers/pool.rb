action :create do
  ceph_conf = @new_resource.ceph_conf
  admin_keyring = @new_resource.admin_keyring
  pool_name = @new_resource.name
  if @new_resource.pg_num
    pg_num = @new_resource.pg_num
  else
    pg_num = get_pg_num(ceph_conf, admin_keyring)
  end
  create_pool(ceph_conf, admin_keyring, pool_name, pg_num)
end

def load_current_resource
  @current_resource = Chef::Resource::CephPool.new(@new_resource.name)
end

def get_pg_num(ceph_conf, admin_keyring)
  Chef::Log.info("Getting pg_num from ceph rbd pool")
  cmd = ["ceph", "-k", admin_keyring, "-c", ceph_conf, "osd", "pool", "get", "rbd", "pg_num"]
  get_pg_num = Mixlib::ShellOut.new(cmd)
  pg_num = get_pg_num.run_command.stdout.split.last
  get_pg_num.error!
  pg_num
end

def create_pool(ceph_conf, admin_keyring, pool_name, pg_num)
  Chef::Log.info("Creating ceph pool #{pool_name} with pg number #{pg_num}")
  cmd = ["ceph", "-k", admin_keyring, "-c", ceph_conf, "osd", "pool", "create", pool_name, pg_num]
  create_pool = Mixlib::ShellOut.new(cmd)
  create_pool.run_command
  create_pool.error!
end
