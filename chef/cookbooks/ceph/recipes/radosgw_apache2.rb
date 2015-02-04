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
  package pkg
end


include_recipe 'apache2'

ha_enabled = node['ceph']['ha']['radosgw']['enabled']

if ha_enabled
  rgw_addr      = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
  rgw_port      = node['ceph']['ha']['ports']['radosgw_plain']
  rgw_port_ssl  = node['ceph']['ha']['ports']['radosgw_ssl']
else
  rgw_addr        = node['ceph']['radosgw']['rgw_addr']
  rgw_port        = node['ceph']['radosgw']['rgw_port']
  rgw_port_ssl    = node['ceph']['radosgw']['rgw_port_ssl']
end
use_ssl = node['ceph']['radosgw']['ssl']['enabled']

node.normal[:apache][:listen_ports_crowbar] ||= {}
if use_ssl
  include_recipe "apache2::mod_ssl"
  # the non-ssl port is needed to allow mod_status over http
  node.normal[:apache][:listen_ports_crowbar][:ceph] = { :plain => [rgw_port], :ssl => [rgw_port_ssl] }
else
  node.normal[:apache][:listen_ports_crowbar][:ceph] = { :plain => [rgw_port] }
end
node.save

# Override what the apache2 cookbook does since it enforces the ports
resource = resources(:template => "#{node[:apache][:dir]}/ports.conf")
resource.variables({:apache_listen_ports => node.normal[:apache][:listen_ports_crowbar].values.map{ |p| p.values }.flatten.uniq.sort})

if use_ssl
  certfile      = node['ceph']['radosgw']['ssl']['certfile']
  keyfile       = node['ceph']['radosgw']['ssl']['keyfile']
  if  node['ceph']['radosgw']['ssl']['generate_certs']
    package "openssl"
    ruby_block "generate_certs for radosgw" do
        block do
          unless ::File.exists? certfile and ::File.exists? keyfile
            require "fileutils"

            Chef::Log.info("Generating SSL certificate for radosgw...")

            [:certfile, :keyfile].each do |k|
              dir = File.dirname(node[:ceph][:radosgw][:ssl][k])
              FileUtils.mkdir_p(dir) unless File.exists?(dir)
            end

            # Generate private key
            %x(openssl genrsa -out #{keyfile} 4096)
            if $?.exitstatus != 0
              message = "SSL private key generation failed"
              Chef::Log.fatal(message)
              raise message
            end
            FileUtils.chown "root", node[:ceph][:group], keyfile
            FileUtils.chmod 0640, keyfile

            # Generate certificate signing requests (CSR)
            conf_dir = File.dirname certfile
            ssl_csr_file = "#{conf_dir}/signing_key.csr"
            ssl_subject = "\"/C=US/ST=Unset/L=Unset/O=Unset/CN=#{node[:fqdn]}\""
            %x(openssl req -new -key #{keyfile} -out #{ssl_csr_file} -subj #{ssl_subject})
            if $?.exitstatus != 0
              message = "SSL certificate signed requests generation failed"
              Chef::Log.fatal(message)
              raise message
            end

            # Generate self-signed certificate with above CSR
            %x(openssl x509 -req -days 3650 -in #{ssl_csr_file} -signkey #{keyfile} -out #{certfile})
            if $?.exitstatus != 0
              message = "SSL self-signed certificate generation failed"
              Chef::Log.fatal(message)
              raise message
            end

            File.delete ssl_csr_file  # Nobody should even try to use this
          end # unless files exist
      end # block
    end # ruby_block
  else # if generate_certs
    unless ::File.exists? certfile
      message = "Certificate \"#{certfile}\" is not present."
      Chef::Log.fatal(message)
      raise message
    end
    # we do not check for existence of keyfile, as the private key is allowed
    # to be in the certfile
  end # if generate_certs
end

apache_module 'fastcgi' do
  conf true
end

apache_module 'rewrite' do
  conf false
end

web_app 'rgw' do
  template 'rgw.conf.erb'
  host rgw_addr
  port use_ssl ? rgw_port_ssl : rgw_port
  behind_proxy ha_enabled
end

directory node['ceph']['radosgw']['path'] do
  owner 'root'
  group 'root'
  mode '0755'
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

if node['platform_family'] == 'suse'
  bash 'Set MPM apache value' do
    code 'sed -i s/^[[:space:]]*APACHE_MPM=.*/APACHE_MPM=\"worker\"/ /etc/sysconfig/apache2'
    not_if 'grep -q "^[[:space:]]*APACHE_MPM=\"worker\"" /etc/sysconfig/apache2'
    notifies :restart, 'service[apache2]'
  end
end
