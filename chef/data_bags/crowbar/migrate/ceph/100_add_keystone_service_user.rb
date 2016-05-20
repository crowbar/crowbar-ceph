# Using a class instance variable to make sure to set the same password
# in the proposal and in the role
unless defined?(@ceph_service_password)
  @ceph_service_password = nil
end

def upgrade(ta, td, a, d)
  unless @ceph_service_password
    service = ServiceObject.new "fake-logger"
    @ceph_service_password = service.random_password
  end
  unless a.key? "service_password"
    a["service_password"] = @ceph_service_password
  end
  unless a.key? "service_user"
    a["service_user"] = ta["service_user"]
  end
  return a, d
end

def downgrade(ta, td, a, d)
  a.delete("service_user")
  a.delete("service_password")
  return a, d
end
