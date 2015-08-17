# This recipe creates a monitor cluster
#
# You should never change the mon default path or
# the keyring path.
# Don't change the cluster name either
# Default path for mon data: /var/lib/ceph/mon/$cluster-$id/
#   which will be /var/lib/ceph/mon/ceph-`hostname`/
#   This path is used by upstart. If changed, upstart won't
#   start the monitor
# The keyring files are created using the following pattern:
#  /etc/ceph/$cluster.client.$name.keyring
#  e.g. /etc/ceph/ceph.client.admin.keyring
#  The bootstrap-osd and bootstrap-mds keyring are a bit
#  different and are created in
#  /var/lib/ceph/bootstrap-{osd,mds}/ceph.keyring

include_recipe "ceph::default"
include_recipe "ceph::server"
include_recipe "ceph::conf"

service_type = node["ceph"]["mon"]["init_style"]

directory "/var/lib/ceph/mon/ceph-#{node["hostname"]}" do
  owner "root"
  group "root"
  mode "0755"
  recursive true
  action :create
end

# TODO cluster name
cluster = 'ceph'

unless File.exists?("/var/lib/ceph/mon/ceph-#{node["hostname"]}/done")
  keyring = "#{Chef::Config[:file_cache_path]}/#{cluster}-#{node['hostname']}.mon.keyring"

  execute "create monitor keyring" do
    command "ceph-authtool '#{keyring}' --create-keyring --name=mon. --add-key='#{node["ceph"]["monitor-secret"]}' --cap mon 'allow *'"
    not_if { node['ceph']['monitor-secret'].empty? }
    notifies :run, 'execute[ceph-mon mkfs]', :immediately
  end

  ruby_block "generate monitor-secret" do
    block do
      gen_key = Mixlib::ShellOut.new("ceph-authtool --gen-print-key")
      monitor_key = gen_key.run_command.stdout.strip
      gen_key.error!

      add_key = Mixlib::ShellOut.new("ceph-authtool '#{keyring}' --create-keyring --name=mon. --add-key='#{monitor_key}' --cap mon 'allow *'")
      add_key.run_command
      add_key.error!

      node.set['ceph']['monitor-secret'] = monitor_key
      node.save
    end
    only_if { node['ceph']['monitor-secret'].empty? && node[:ceph][:master] }
    notifies :run, 'execute[ceph-mon mkfs]', :immediately
  end

  ruby_block "get monitor-secret" do
    block do
      monitor_key = ''
      while monitor_key.empty?
        mon_nodes = get_mon_nodes
        mon_nodes.each do |mon|
          if mon[:ceph][:master] && !mon['ceph']['monitor-secret'].empty?
            monitor_key = mon['ceph']['monitor-secret']
          end
        end
        sleep 1
      end

      add_key = Mixlib::ShellOut.new("ceph-authtool '#{keyring}' --create-keyring --name=mon. --add-key='#{monitor_key}' --cap mon 'allow *'")
      add_key.run_command
      add_key.error!

      node.set['ceph']['monitor-secret'] = monitor_key
      node.save
    end
    only_if { node['ceph']['monitor-secret'].empty? }
    notifies :run, 'execute[ceph-mon mkfs]', :immediately
  end

  execute 'ceph-mon mkfs' do
    command "ceph-mon --mkfs -i #{node['hostname']} --keyring '#{keyring}'"
    action :nothing
  end

  ruby_block "finalise" do
    block do
      ["done", service_type].each do |ack|
        File.open("/var/lib/ceph/mon/ceph-#{node["hostname"]}/#{ack}", "w").close()
      end
    end
  end
end

if service_type == "upstart"
  service "ceph-mon" do
    provider Chef::Provider::Service::Upstart
    action :enable
  end
  service "ceph-mon-all" do
    provider Chef::Provider::Service::Upstart
    supports :status => true
    action [ :enable, :start ]
  end
end

service "ceph_mon" do
  case service_type
  when "upstart"
    service_name "ceph-mon-all-starter"
    provider Chef::Provider::Service::Upstart
  when "systemd"
    service_name "ceph-mon@#{node["hostname"]}"
  else
    service_name "ceph"
  end
  supports :restart => true, :status => true
  action [ :enable, :start ]
  subscribes :restart, resources(:template => "/etc/ceph/ceph.conf")
end

# In addition to the mon service, ceph.target must be enabled when using systemd
service "ceph.target" do
  action :enable
end if service_type == "systemd"

execute "Create Ceph client.admin key when ceph-mon is ready" do
  command "ceph-create-keys -i #{node['hostname']}"
  not_if { File.exists?("/etc/ceph/#{cluster}.client.admin.keyring") }
end

get_mon_addresses.each do |addr|
  execute "peer #{addr}" do
    command "ceph --admin-daemon '/var/run/ceph/ceph-mon.#{node['hostname']}.asok' add_bootstrap_peer_hint #{addr}"
    ignore_failure true
  end
end

[ "admin", "bootstrap-osd" ].each do |auth|
  ruby_block "get #{auth}-secret" do
    block do
      auth_key = ''
      while auth_key.empty?
        get_key = Mixlib::ShellOut.new("ceph auth get-key client.#{auth}")
        auth_key = get_key.run_command.stdout.strip
        sleep 1
      end

      if node["ceph"]["#{auth}-secret"] != auth_key
        node.set["ceph"]["#{auth}-secret"] = auth_key
        node.save
      end
    end
  end
end
