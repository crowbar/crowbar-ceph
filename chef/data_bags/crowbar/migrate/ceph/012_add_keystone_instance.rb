def upgrade ta, td, a, d
  a["keystone_instance"] = ta["keystone_instance"]

  return a, d
end

def downgrade ta, td, a, d
  a.delete("keystone_instance")
  return a, d
end
