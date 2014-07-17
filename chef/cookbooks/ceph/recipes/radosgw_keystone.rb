# Ceph integration with Keystone

# Keystone itself needs to be configured to point to the Ceph Object Gateway as an object-storage endpoint:
keystone_settings = KeystoneHelper.keystone_settings(node, @cookbook_name)

keystone_register "radosgw wakeup keystone" do
  protocol keystone_settings['protocol']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  action :wakeup
end

# keystone service-create --name swift --type object-store
keystone_register "register swift service" do
  protocol keystone_settings['protocol']
  host keystone_settings['internal_url_host']
  token keystone_settings['admin_token']
  port keystone_settings['admin_port']
  service_name "swift"
  service_type "object-store"
  service_description "Openstack Swift Object Store Service API provided by RADOS Gateway"
  action :add_service
end

# keystone endpoint-create --service-id <id> --publicurl http://radosgw.example.com/swift/v1 \
# --internalurl http://radosgw.example.com/swift/v1 --adminurl http://radosgw.example.com/swift/v1

protocol        = "http"
ha_enabled      = false

admin_host = CrowbarHelper.get_host_for_admin_url(node, ha_enabled)
public_host = CrowbarHelper.get_host_for_public_url(node, protocol == "https", ha_enabled)

keystone_register "register radosgw endpoint" do
    protocol keystone_settings['protocol']
    host keystone_settings['internal_url_host']
    token keystone_settings['admin_token']
    port keystone_settings['admin_port']
    endpoint_service "swift"
    endpoint_region "RegionOne"
    endpoint_publicURL "#{protocol}://#{public_host}/swift/v1"
    endpoint_adminURL "#{protocol}://#{admin_host}/swift/v1"
    endpoint_internalURL "#{protocol}://#{admin_host}/swift/v1"
   action :add_endpoint_template
end


# TODO adaptation of ceph.conf with keystone related keys
