def upgrade ta, td, a, d
  a['calamari']['ssl'] = ta['calamari']['ssl']
  return a, d
end

def downgrade ta, td, a, d
  a['calamari'].delete('ssl')
  return a, d
end
