def upgrade ta, td, a, d
  a['disk_mode'] = a['disk-mode']
  a.delete('disk-mode')
  return a, d
end

def downgrade ta, td, a, d
  a['disk-mode'] = a['disk_mode']
  a.delete('disk_mode')
  return a, d
end
