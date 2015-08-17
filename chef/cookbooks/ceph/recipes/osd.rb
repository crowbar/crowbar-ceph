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
include_recipe "ceph::server"
include_recipe "ceph::conf"

package "gdisk"

service_type = node["ceph"]["osd"]["init_style"]
mons = get_mon_nodes("ceph_bootstrap-osd-secret:*")

if mons.empty? then
  Chef::Log.fatal("No ceph-mon found")
  raise "No ceph-mon found"
elsif mons[0]["ceph"]["bootstrap-osd-secret"].empty?
  Chef::Log.fatal("No authorization keys found")
else

  ["tmp", "osd", "bootstrap-osd"].each do |name|
    directory "/var/lib/ceph/#{name}" do
      owner "root"
      group "root"
      mode "0755"
      recursive true
      action :create
    end
  end

  # TODO cluster name
  cluster = "ceph"

  osd_secret = mons[0]["ceph"]["bootstrap-osd-secret"]

  execute "create bootstrap-osd keyring" do
    command "ceph-authtool '/var/lib/ceph/bootstrap-osd/#{cluster}.keyring' --create-keyring --name=client.bootstrap-osd --add-key='#{osd_secret}'"
  end

  if is_crowbar?
    node.set["ceph"]["osd_devices"] = [] if node["ceph"]["osd_devices"].nil?
    min_size_blocks = node["ceph"]["osd"]["min_size_gb"] * 1024 * 1024 * 2
    unclaimed_disks = BarclampLibrary::Barclamp::Inventory::Disk.unclaimed(node).sort.select { |d| d.size >= min_size_blocks }

    # if devices for journal are explicitely listed, do not use automatic journal assigning to SSD
    if !node["ceph"]["osd"]["journal_devices"].empty?
      node.set["ceph"]["osd"]["use_ssd_for_journal"]        = false
    end

    # If no OSDs have yet been deployed, check what type of disks are available.
    # If they are all of one type, turn off automatic journal assigning to SSD
    # (automatic SSD journals only makes sense if there's a mix of disk types).
    # Note: this also effectively disables SSD journal assignment if there's
    # only one disk available (can't have a mix of disks if there's only one
    # disk!)
    if node["ceph"]["osd_devices"].empty? && unclaimed_disks.any?
      has_ssds = unclaimed_disks.any? { |d| node[:block_device][d.name.gsub("/dev/", "")]["rotational"] == "0" }
      has_hdds = unclaimed_disks.any? { |d| node[:block_device][d.name.gsub("/dev/", "")]["rotational"] == "1" }

      node.set["ceph"]["osd"]["use_ssd_for_journal"] = false unless has_ssds && has_hdds
    end

    if node["ceph"]["disk_mode"] == "first" && node["ceph"]["osd_devices"].empty?
      if unclaimed_disks.empty?
        Chef::Log.fatal("There are no suitable disks for ceph")
        raise "There are no suitable disks for ceph"
      else
        # take first available disk, regardless of whether it's an SSD or not
        # (use_ssd_for_journal doesn't make sense if you're only trying to claim
        # one disk)
        disk_list = [unclaimed_disks.first]
      end
    elsif node["ceph"]["disk_mode"] == "all"
      disk_list = unclaimed_disks
    else
      disk_list = []
    end

    # Now, we have the final list of devices to claim, so claim them
    disk_list.select do |d|
      if d.claim("Ceph")
        Chef::Log.info("Ceph: Claimed #{d.name}")
        device = {}
        dev_name = d.name.gsub("/dev/", "")
        if node["ceph"]["osd"]["journal_devices"].include?(d.name) ||
            (node[:block_device][dev_name]["rotational"] == "0" &&
             node["ceph"]["osd"]["use_ssd_for_journal"] &&
             node["ceph"]["disk_mode"] == "all")
          # Disk marked as journal if explicitly specified in journal_devices,
          # or if disk is SSD, and use_ssd_for_journal and disk_mode == all.
          # Note: journal_devices with disk_mode == first probably doesn't work,
          # but if you know how to define journal_devices, you probably know
          # you don't want to only allocate one disk to ceph.
          Chef::Log.info("Ceph: Mark #{d.name} as journal")
          device["status"] = "journal"
        end
        device["device"] = d.name
        node.set["ceph"]["osd_devices"].push(device)
        node.save
      else
        Chef::Log.info("Ceph: Ignoring #{d.name}")
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
    unless disk_list.empty?
      ssd_devices = node["ceph"]["osd_devices"].select { |d| d["status"] == "journal" }
      partitions_per_ssd = (disk_list.size - ssd_devices.size) / ssd_devices.size rescue 1
      ssd_index         = 0
      ssd_partitions    = 1
      node["ceph"]["osd_devices"].each_with_index do |osd_device,index|
        if !osd_device["status"].nil?
          Log.info("osd: osd_device #{osd_device['device']} has already been set up.")
          next
        end
        create_cmd = "ceph-disk prepare --cluster '#{cluster}' --journal-dev --zap-disk '#{osd_device['device']}'"
        unless ssd_devices.empty?
          ssd_device            = ssd_devices[ssd_index]
          journal_device        = ssd_device["device"]
          create_cmd            = create_cmd + " #{journal_device}" if journal_device
          # move to next fee SSD if number of partitions on current one is too big
          ssd_partitions        = ssd_partitions + 1
          if ssd_partitions > partitions_per_ssd && ssd_devices[ssd_index+1]
            ssd_partitions      = 0
            ssd_index           = ssd_index + 1
          end
        end

        if %w(redhat centos).include? node.platform
          # redhat has buggy udev so we have to use workaround from ceph
          b_dev = osd_device["device"].gsub("/dev/", "")
          create_cmd = create_cmd + " && ceph-disk-udev 2 #{b_dev}2 #{b_dev} ; ceph-disk-udev 1 #{b_dev}1 #{b_dev}"
        else
          extra_options = ""
          extra_options = "--mark-init systemd" if service_type == "systemd"
          create_cmd = create_cmd + " && ceph-disk activate #{extra_options} -- '#{osd_device['device']}1'"
        end

        execute "Activating Ceph OSD on #{osd_device['device']}" do
          command create_cmd
          action :run
        end

        ruby_block "Get Ceph OSD ID for #{osd_device['device']}" do
          block do
            osd_id = ""
            while osd_id.empty?
              osd_id = get_osd_id(osd_device["device"])
              sleep 1
            end
          end
        end
        node.set["ceph"]["osd_devices"][index]["status"] = "deployed"
        node.set["ceph"]["osd_devices"][index]["journal"] = journal_device unless journal_device.nil?

        execute "Writing Ceph OSD device mappings to fstab" do
          command "tail -n1 /etc/mtab >> /etc/fstab"
          action :run
        end

        # No need to specifically enable ceph-osd@N on systemd systems, as this
        # is done automatically by ceph-disk-activate
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
        action [:enable, :start]
        supports restart: true
        subscribes :restart, resources(template: "/etc/ceph/ceph.conf")
      end unless service_type == "systemd"

      # In addition to the osd services, ceph.target must be enabled when using systemd
      service "ceph.target" do
        action :enable
      end if service_type == "systemd"
    end
  end
end
