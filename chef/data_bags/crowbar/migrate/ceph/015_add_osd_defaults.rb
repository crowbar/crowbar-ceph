def upgrade ta, td, a, d
  a['osd'] = ta['osd']
  return a, d
end

def downgrade ta, td, a, d
  a.delete('osd')
  return a, d
end
