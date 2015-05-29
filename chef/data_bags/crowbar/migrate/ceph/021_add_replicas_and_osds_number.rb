def upgrade ta, td, a, d
  a['config']['osds_in_total'] = ta['config']['osds_in_total']
  a['config']['replicas_number'] = ta['config']['replicas_number']
  return a, d
end

def downgrade ta, td, a, d
  a['config'].delete('osds_in_total')
  a['config'].delete('replicas_number')
  return a, d
end
