# Ceph integration with Keystone

# Keystone itself needs to be configured to point to the Ceph Object Gateway as an object-storage endpoint:
keystone_settings = KeystoneHelper.keystone_settings(node, @cookbook_name)

crowbar_pacemaker_sync_mark "wait-radosgw_register"

keystone_register "radosgw wakeup keystone" do
  protocol keystone_settings["protocol"]
  insecure keystone_settings["insecure"]
  host keystone_settings["internal_url_host"]
  port keystone_settings["admin_port"]
  token keystone_settings["admin_token"]
  action :wakeup
end

role = "ResellerAdmin"
keystone_register "add #{role} role" do
  protocol keystone_settings["protocol"]
  insecure keystone_settings["insecure"]
  host keystone_settings["internal_url_host"]
  port keystone_settings["admin_port"]
  token keystone_settings["admin_token"]
  role_name role
  action :add_role
end

# keystone service-create --name swift --type object-store
keystone_register "register swift service" do
  protocol keystone_settings["protocol"]
  insecure keystone_settings["insecure"]
  host keystone_settings["internal_url_host"]
  token keystone_settings["admin_token"]
  port keystone_settings["admin_port"]
  service_name "swift"
  service_type "object-store"
  service_description "Openstack Swift Object Store Service API provided by RADOS Gateway"
  action :add_service
end

# keystone endpoint-create --service-id <id> --publicurl http://radosgw.example.com/swift/v1 \
# --internalurl http://radosgw.example.com/swift/v1 --adminurl http://radosgw.example.com/swift/v1

if node[:ceph][:radosgw][:ssl][:enabled]
  protocol      = "https"
  port          = node["ceph"]["radosgw"]["rgw_port_ssl"]
else
  protocol      = "http"
  port          = node["ceph"]["radosgw"]["rgw_port"]
end
ha_enabled      = node[:ceph][:ha][:radosgw][:enabled]

admin_host = CrowbarHelper.get_host_for_admin_url(node, ha_enabled)
public_host = CrowbarHelper.get_host_for_public_url(node, protocol == "https", ha_enabled)

keystone_register "register radosgw endpoint" do
    protocol keystone_settings["protocol"]
    insecure keystone_settings["insecure"]
    host keystone_settings["internal_url_host"]
    token keystone_settings["admin_token"]
    port keystone_settings["admin_port"]
    endpoint_service "swift"
    endpoint_region keystone_settings["endpoint_region"]
    endpoint_publicURL "#{protocol}://#{public_host}:#{port}/swift/v1"
    endpoint_adminURL "#{protocol}://#{admin_host}:#{port}/swift/v1"
    endpoint_internalURL "#{protocol}://#{admin_host}:#{port}/swift/v1"
   action :add_endpoint_template
end

crowbar_pacemaker_sync_mark "create-radosgw_register"

# Convert OpenSSL certificates that Keystone uses for creating the requests to the nss db format
# See http://ceph.com/docs/master/radosgw/keystone/
package "mozilla-nss-tools"

nss_dir = node["ceph"]["radosgw"]["nss_directory"]

directory nss_dir do
  owner node[:apache][:user]
  group node[:apache][:group]
  mode "0755"
  action :create
end

keystone_node = search_env_filtered(:node, "roles:keystone-server AND keystone_pki_content:*").first

if !keystone_node.nil?
  file "#{nss_dir}/keystone_pki_ca.pem" do
    content keystone_node[:keystone][:pki][:content][:ca]
  end

  bash "convert signing ca certificate to nss db format" do
    code <<-EOH
openssl x509 -in #{nss_dir}/keystone_pki_ca.pem -pubkey | certutil -d #{nss_dir} -A -n ca -t 'TCu,Cu,Tuw'
chown #{node[:apache][:user]}:#{node[:apache][:group]} #{nss_dir}/*.db
    EOH
    subscribes :run, "file[#{nss_dir}/keystone_pki_ca.pem]"
  end

  file "#{nss_dir}/keystone_pki_signing_cert.pem" do
    content keystone_node[:keystone][:pki][:content][:signing_cert]
  end

  bash "convert signing certificate to nss db format" do
    code <<-EOH
openssl x509 -in #{nss_dir}/keystone_pki_signing_cert.pem -pubkey | certutil -A -d #{nss_dir} -n signing_cert -t 'P,P,P'
chown #{node[:apache][:user]}:#{node[:apache][:group]} #{nss_dir}/*.db
    EOH
    subscribes :run, "file[#{nss_dir}/keystone_pki_signing_cert.pem]"
  end
end
