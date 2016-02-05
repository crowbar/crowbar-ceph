include_recipe "ceph::default"
include_recipe "ceph::conf"

keyring = "/etc/ceph/ceph.client.admin.keyring"
if !File.exists?(keyring)

  mons = get_mon_nodes("ceph_admin-secret:*")

  if mons.empty? then
    msg = "No ceph-mon found"
    Chef::Log.fatal(msg)
    raise msg
  end

  if !mons[0]["ceph"]["admin-secret"].empty?
    admin_key = mons[0]["ceph"]["admin-secret"]

    execute "create admin keyring" do
      command "ceph-authtool '#{keyring}' --create-keyring  --name=client.admin --add-key='#{admin_key}'"
    end
  else
    Chef::Log.warn("Ceph admin keyring was not generated yet")
  end
end
