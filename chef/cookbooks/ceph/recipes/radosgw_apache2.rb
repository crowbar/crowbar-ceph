if node['ceph']['radosgw']['use_apache_fork']
  case node['lsb']['codename']
  when 'precise', 'oneiric'
    apt_repository 'ceph-apache2' do
      repo_name 'ceph-apache2'
      uri "http://gitbuilder.ceph.com/apache2-deb-#{node['lsb']['codename']}-x86_64-basic/ref/master"
      distribution node['lsb']['codename']
      components ['main']
      key 'https://ceph.com/git/?p=ceph.git;a=blob_plain;f=keys/autobuild.asc'
    end
    apt_repository 'ceph-modfastcgi' do
      repo_name 'ceph-modfastcgi'
      uri "http://gitbuilder.ceph.com/libapache-mod-fastcgi-deb-#{node['lsb']['codename']}-x86_64-basic/ref/master"
      distribution node['lsb']['codename']
      components ['main']
      key 'https://ceph.com/git/?p=ceph.git;a=blob_plain;f=keys/autobuild.asc'
    end
  else
    Log.info("Ceph's Apache and Apache FastCGI forks not available for this distribution")
  end
end

packages = []
case node['platform_family']
  when 'debian'
    packages = ['libapache2-mod-fastcgi']
  when 'rhel', 'fedora'
    packages = ['mod_fastcgi']
  when 'suse'
    packages = ['apache2-mod_fastcgi', 'apache2-worker' ]
end

packages.each do |pkg|
  package pkg do
    action :install
  end
end

include_recipe 'apache2'

rgw_addr        = node['ceph']['radosgw']['rgw_addr']
rgw_port        = node['ceph']['radosgw']['rgw_port']

if node['ceph']['ha']['radosgw']['enabled']
  rgw_addr        = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
  rgw_port        = node['ceph']['ha']['ports']['radosgw_plain']
end

node.normal[:apache][:listen_ports_crowbar] ||= {}
node.normal[:apache][:listen_ports_crowbar][:ceph] = { :plain => [rgw_port] }
node.save

# Override what the apache2 cookbook does since it enforces the ports
resource = resources(:template => "#{node[:apache][:dir]}/ports.conf")
resource.variables({:apache_listen_ports => node.normal[:apache][:listen_ports_crowbar].values.map{ |p| p.values }.flatten.uniq.sort})

apache_module 'fastcgi' do
  conf true
end

apache_module 'rewrite' do
  conf false
end

web_app 'rgw' do
  template 'rgw.conf.erb'
  host rgw_addr
  port rgw_port
end

directory node['ceph']['radosgw']['path'] do
  owner 'root'
  group 'root'
  mode "0755"
  action :create
end

template "#{node['ceph']['radosgw']['path']}/s3gw.fcgi" do
  source 's3gw.fcgi.erb'
  owner 'root'
  group 'root'
  mode '0755'
  variables(
    :ceph_rgw_client => "client.radosgw.#{node['hostname']}"
  )
end

if node[:platform] == "suse"
  bash "Set MPM apache value" do
    code 'sed -i s/^[[:space:]]*APACHE_MPM=.*/APACHE_MPM=\"worker\"/ /etc/sysconfig/apache2'
    not_if 'grep -q "^[[:space:]]*APACHE_MPM=\"worker\"" /etc/sysconfig/apache2'
    notifies :restart, resources(:service => "apache2")
  end
end
