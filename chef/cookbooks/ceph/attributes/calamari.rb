case node['platform_family']
  when 'suse'
    # this pulls in calamari-server and all other deps
    default['ceph']['calamari']['packages'] = ['calamari-clients']
  else
    default['ceph']['calamari']['packages'] = []
end
