def upgrade ta, td, a, d
  a.delete("bootstrap-osd-secret")
  return a, d
end

def downgrade ta, td, a, d
  a["bootstrap-osd-secret"] = ta["bootstrap-osd-secret"]
  return a, d
end
