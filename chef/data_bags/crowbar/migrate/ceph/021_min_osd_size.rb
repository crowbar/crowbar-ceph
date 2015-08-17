def upgrade ta, td, a, d
  a["osd"]["min_size_gb"] = ta["osd"]["min_size_gb"]
  return a, d
end

def downgrade ta, td, a, d
  a["osd"].delete("min_size_gb")
  return a, d
end
