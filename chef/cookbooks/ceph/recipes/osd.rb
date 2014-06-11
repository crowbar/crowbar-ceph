#
# Author:: Kyle Bader <kyle.bader@dreamhost.com>
# Cookbook Name:: ceph
# Recipe:: osd
#
# Copyright 2011, DreamHost Web Hosting
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# this recipe allows bootstrapping new osds, with help from mon
# Sample environment:
# #knife node edit ceph1
#"osd_devices": [
#   {
#       "device": "/dev/sdc"
#   },
#   {
#       "device": "/dev/sdd",
#       "dmcrypt": true,
#       "journal": "/dev/sdd"
#   }
#]

include_recipe "ceph::default"
include_recipe "ceph::conf"

package 'gdisk' do
  action :install
end

if !File.exists?("/etc/ceph/keyring")

  admin_secret = node["ceph"]["admin-secret"]

  execute "create admin keyring" do
    command "ceph-authtool --create-keyring /etc/ceph/keyring --name=client.admin --add-key='#{admin_secret}'"
  end

end

if !search(:node,"hostname:#{node['hostname']} AND dmcrypt:true").empty?
    package 'cryptsetup' do
      action :install
    end
end

service_type = node["ceph"]["osd"]["init_style"]
mons = node['ceph']['encrypted_data_bags'] ? get_mon_nodes : get_mon_nodes("ceph_bootstrap_osd_key:*")

if mons.empty? then
  puts "No ceph-mon found."
else

  directory "/var/run/ceph" do
    owner "root"
    group "root"
    mode 00755
    recursive true
    action :create
  end

  directory "/var/log/ceph" do
    owner "root"
    group "root"
    mode 00755
    recursive true
    action :create
  end

  directory "/var/lib/ceph/bootstrap-osd" do
    owner "root"
    group "root"
    mode "0755"
    recursive true
    action :create
  end

  directory "/var/lib/ceph/tmp" do
    owner "root"
    group "root"
    mode "0755"
    recursive true
    action :create
  end

  directory "/var/lib/ceph/osd" do
    owner "root"
    group "root"
    mode "0755"
    recursive true
    action :create
  end

  # TODO cluster name
  cluster = 'ceph'

  osd_secret = if node['ceph']['encrypted_data_bags']
    secret = Chef::EncryptedDataBagItem.load_secret(node["ceph"]["osd"]["secret_file"])
    Chef::EncryptedDataBagItem.load("ceph", "osd", secret)["secret"]
  else
    mons[0]["ceph"]["bootstrap_osd_key"]
  end

  execute "format as keyring" do
    command "ceph-authtool '/var/lib/ceph/bootstrap-osd/#{cluster}.keyring' --create-keyring --name=client.bootstrap-osd --add-key='#{osd_secret}'"
    creates "/var/lib/ceph/bootstrap-osd/#{cluster}.keyring"
  end

  if is_crowbar?
      unclaimed_disks = BarclampLibrary::Barclamp::Inventory::Disk.unclaimed(node).sort
      claimed_disks = BarclampLibrary::Barclamp::Inventory::Disk.claimed(node,"Ceph").sort
        if (node["ceph"]["osd_devices"].empty? && unclaimed_disks.empty? && claimed_disks.empty?)
          Chef::Log.fatal("There is no suitable disks for ceph")
	        raise "There is no suitable disks for ceph"
        else
          if node["ceph"]["disk_mode"] == "first"
            disk_list = [unclaimed_disks.first]
          else
            disk_list = unclaimed_disks
          end
          node["ceph"]["osd_devices"] = []
          index = 0
          # Now, we have the final list of devices to claim, so claim them
          claimed_disks = disk_list.select do |d|
            if d.claim("Ceph")
              Chef::Log.info("Ceph: Claimed #{d.name}")
              node["ceph"]["osd_devices"][index] = Hash.new
              node["ceph"]["osd_devices"][index]["device"] = d.name
            else
              Chef::Log.info("Ceph: Ignoring #{d.name}")
            end
            index += 1
            node.save
          end
        end
    # Calling ceph-disk-prepare is sufficient for deploying an OSD
    # After ceph-disk-prepare finishes, the new device will be caught
    # by udev which will run ceph-disk-activate on it (udev will map
    # the devices if dm-crypt is used).
    # IMPORTANT:
    #  - Always use the default path for OSD (i.e. /var/lib/ceph/
    # osd/$cluster-$id)
    #  - $cluster should always be ceph
    #  - The --dmcrypt option will be available starting w/ Cuttlefish
    unless node["ceph"]["osd_devices"].nil?
      osd_devices = []
      node["ceph"]["osd_devices"].each_with_index do |osd_device,index|
        if !osd_device["status"].nil?
          Log.info("osd: osd_device #{osd_device} has already been setup.")
          next
        end
        create_cmd = "ceph-disk prepare --zap #{osd_device['device']}"

        if %w(redhat centos).include? node.platform
          # redhat has buggy udev so we have to use workaround from ceph
          b_dev = osd_device['device'].gsub("/dev/", "")
          create_cmd = create_cmd + " && ceph-disk-udev 2 #{b_dev}2 #{b_dev} ; ceph-disk-udev 1 #{b_dev}1 #{b_dev}"
        else
          create_cmd = create_cmd + " && ceph-disk-activate #{osd_device['device']}1"
        end

        execute "Activating Ceph OSD on #{osd_device['device']}" do
          command create_cmd
          action :run
        end

        ruby_block "Get Ceph OSD ID for #{osd_device['device']}" do
          block do
            osd_id = ""
            while osd_id.empty?
              osd_id = get_osd_id(osd_device['device'])
              sleep 1
            end
            %x{ceph osd crush set #{osd_id} 1.00 root=default rack=susecloud host=#{node[:hostname]}}
            exitstatus = $?.exitstatus
            Chef::Log.info("Ceph OSD crush set exited with #{exitstatus}.")
          end
        end
        node["ceph"]["osd_devices"][index]["status"] = "deployed"

        execute "Writing Ceph OSD device mappings to fstab" do
          command "tail -n1 /etc/mtab >> /etc/fstab"
          action :run
        end

      end
      node.save

      service "ceph_osd" do
        case service_type
        when "upstart"
          service_name "ceph-osd-all-starter"
          provider Chef::Provider::Service::Upstart
        else
          service_name "ceph"
        end
        action [ :enable, :start ]
        supports :restart => true
      end

    else
      Log.info('node["ceph"]["osd_devices"] empty')
    end
  end
end
