def upgrade ta, td, a, d
  a['radosgw'] = ta['radosgw']
  return a, d
end

def downgrade ta, td, a, d
  a.delete('radosgw')
  return a, d
end
