# Ceph integration with Keystone

# Keystone itself needs to be configured to point to the Ceph Object Gateway as an object-storage endpoint:
keystone_settings = KeystoneHelper.keystone_settings(node, @cookbook_name)
register_auth_hash = { user: keystone_settings["admin_user"],
                       password: keystone_settings["admin_password"],
                       domain: keystone_settings["admin_domain"],
                       project: keystone_settings["admin_project"] }

crowbar_pacemaker_sync_mark "wait-radosgw_register"

keystone_register "radosgw wakeup keystone" do
  protocol keystone_settings["protocol"]
  insecure keystone_settings["insecure"]
  host keystone_settings["internal_url_host"]
  port keystone_settings["admin_port"]
  auth register_auth_hash
  action :wakeup
end

keystone_register "register ceph user" do
  protocol keystone_settings["protocol"]
  insecure keystone_settings["insecure"]
  host keystone_settings["internal_url_host"]
  port keystone_settings["admin_port"]
  auth register_auth_hash
  user_name keystone_settings["service_user"]
  user_password keystone_settings["service_password"]
  project_name keystone_settings["service_tenant"]
  action :add_user
end

keystone_register "give ceph user access" do
  protocol keystone_settings["protocol"]
  insecure keystone_settings["insecure"]
  host keystone_settings["internal_url_host"]
  port keystone_settings["admin_port"]
  auth register_auth_hash
  user_name keystone_settings["service_user"]
  project_name keystone_settings["service_tenant"]
  role_name "admin"
  action :add_access
end

role = "ResellerAdmin"
keystone_register "add #{role} role" do
  protocol keystone_settings["protocol"]
  insecure keystone_settings["insecure"]
  host keystone_settings["internal_url_host"]
  port keystone_settings["admin_port"]
  auth register_auth_hash
  role_name role
  action :add_role
end

# keystone service-create --name swift --type object-store
keystone_register "register swift service" do
  protocol keystone_settings["protocol"]
  insecure keystone_settings["insecure"]
  host keystone_settings["internal_url_host"]
  port keystone_settings["admin_port"]
  auth register_auth_hash
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
  port keystone_settings["admin_port"]
  auth register_auth_hash
  endpoint_service "swift"
  endpoint_region keystone_settings["endpoint_region"]
  endpoint_publicURL "#{protocol}://#{public_host}:#{port}/swift/v1"
  endpoint_adminURL "#{protocol}://#{admin_host}:#{port}/swift/v1"
  endpoint_internalURL "#{protocol}://#{admin_host}:#{port}/swift/v1"
  action :add_endpoint
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

keystone_node = search_env_filtered(:node, "roles:keystone-server
  AND keystone_certificates_content:*").first

if !keystone_node.nil?
  file "#{nss_dir}/keystone_ca.pem" do
    content keystone_node[:keystone][:certificates][:content][:ca]
  end

  bash "convert signing ca certificate to nss db format" do
    code <<-EOH
openssl x509 -in #{nss_dir}/keystone_ca.pem -pubkey | certutil -d #{nss_dir} -A -n ca -t 'TCu,Cu,Tuw'
chown #{node[:apache][:user]}:#{node[:apache][:group]} #{nss_dir}/*.db
    EOH
    subscribes :run, "file[#{nss_dir}/keystone_ca.pem]"
  end

  file "#{nss_dir}/keystone_signing_cert.pem" do
    content keystone_node[:keystone][:certificates][:content][:signing_cert]
  end

  bash "convert signing certificate to nss db format" do
    code <<-EOH
openssl x509 -in #{nss_dir}/keystone_signing_cert.pem -pubkey | certutil -A -d #{nss_dir} -n signing_cert -t 'P,P,P'
chown #{node[:apache][:user]}:#{node[:apache][:group]} #{nss_dir}/*.db
    EOH
    subscribes :run, "file[#{nss_dir}/keystone_signing_cert.pem]"
  end
end
