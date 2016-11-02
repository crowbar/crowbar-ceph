def upgrade(ta, td, a, d)
  unless a.key? "client_network"
    # Force client_network to "admin" here during upgrades,
    # so ceph client network will match existing deploys.
    # New deployments will default to the value actually
    # in the template ("public")
    a["client_network"] = "admin"
  end

  return a, d
end

def downgrade(ta, td, a, d)
  unless ta.key? "client_network"
    a.delete("client_network")
  end

  return a, d
end
