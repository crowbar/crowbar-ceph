def upgrade ta, td, a, d
  a["config"].delete("public-network")

  return a, d
end

def downgrade ta, td, a, d
  a["config"]["public-network"] = ta["config"]["public-network"]

  return a, d
end
