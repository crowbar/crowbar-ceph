def upgrade ta, td, a, d
  a['disk-mode'] = ta['disk-mode'] || ta['disk_mode']
  a['config'] = ta['config']
  a['monitor-secret'] = ta['monitor-secret']
  a['admin-secret'] = ta['admin-secret']
  a.delete('devices')
  return a, d
end

def downgrade ta, td, a, d
  a['devices'] = ta['devices']
  a.delete('disk-mode')
  a.delete('config')
  a.delete('monitor-secret')
  a.delete('admin-secret')
  return a, d
end
