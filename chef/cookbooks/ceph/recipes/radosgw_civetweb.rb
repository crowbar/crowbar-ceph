# This recipe doesn't do anything other than deal with SSL keys and certificates.
# Everything else for civetweb setup is in conf.rb.  It could arguably be merged
# into radosgw.rb; it only exists as a separate file because it used to be
# radosgw_apache2.rb

return unless node["ceph"]["radosgw"]["ssl"]["enabled"]

certfile      = node["ceph"]["radosgw"]["ssl"]["certfile"]
keyfile       = node["ceph"]["radosgw"]["ssl"]["keyfile"]
pemfile       = node["ceph"]["radosgw"]["ssl"]["pemfile"]
if node["ceph"]["radosgw"]["ssl"]["generate_certs"]
  package "openssl"
  ruby_block "generate_certs for radosgw" do
    block do
      unless ::File.exist?(certfile) && ::File.exist?(keyfile)
        require "fileutils"

        Chef::Log.info("Generating SSL certificate for radosgw...")

        [:certfile, :keyfile].each do |k|
          dir = File.dirname(node[:ceph][:radosgw][:ssl][k])
          FileUtils.mkdir_p(dir) unless File.exist?(dir)
        end

        # Generate private key
        `openssl genrsa -out #{keyfile} 4096`
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
        `openssl req -new -key #{keyfile} -out #{ssl_csr_file} -subj #{ssl_subject}`
        if $?.exitstatus != 0
          message = "SSL certificate signed requests generation failed"
          Chef::Log.fatal(message)
          raise message
        end

        # Generate self-signed certificate with above CSR
        `openssl x509 -req -days 3650 -in #{ssl_csr_file} -signkey #{keyfile} -out #{certfile}`
        if $?.exitstatus != 0
          message = "SSL self-signed certificate generation failed"
          Chef::Log.fatal(message)
          raise message
        end

        File.delete ssl_csr_file # Nobody should even try to use this
      end # unless files exist
    end # block
  end # ruby_block
else # if generate_certs
  unless ::File.exist? certfile
    message = "Certificate \"#{certfile}\" is not present."
    Chef::Log.fatal(message)
    raise message
  end
  # we do not check for existence of keyfile, as the private key is allowed
  # to be in the certfile
end # if generate_certs

# Have to merge the SSL key and certificate into a pemfile, because that's what
# civetweb expects.  Per the comment above though, it's possible the keyfile
# may not actually exist, hence the existence check below
ruby_block "Creating radosgw pemfile" do
  block do
    `cp #{certfile} #{pemfile}`
    `cat #{keyfile} >> #{pemfile}` if ::File.exist? keyfile
    FileUtils.chown "root", node["ceph"]["radosgw"]["group"], pemfile
    FileUtils.chmod 0640, pemfile
  end # block
end # ruby_block
