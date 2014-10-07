node['ceph']['calamari']['packages'].each do |pkg|
  package pkg
end

# TODO: do we need pacemaker sync marks? (nothing here uses pacemaker;
# something for further consideration is making the calamari server HA)

ruby_block "initialize calamari server" do
  block do
    check_cmd = Mixlib::ShellOut.new("/srv/www/calamari/manage.py check >/dev/null 2>&1")
    check_cmd.run_command
    if check_cmd.exitstatus != 0
      Chef::Log.info("Ceph: Initializing Calamari")
      # If check failed, it'll be because calamari isn't initialized yet, so
      # set it up (newer versions of Mixlib::ShellOut have an error? method
      # we could call instead of checking exitstatus, but this seems to be
      # sadly missing on SLE at the moment)
      init_cmd = Mixlib::ShellOut.new(
        "calamari-ctl", "initialize",
          "--admin-username", node[:ceph][:calamari][:username],
          "--admin-password", node[:ceph][:calamari][:password],
          "--admin-email", node[:ceph][:calamari][:email])
      init_cmd.run_command
      init_cmd.error!
    else
      # Check passed, so it's already configured.  Need to update admin user.
      # Is it unholy to generate python from ruby?
      Chef::Log.info("Ceph: Updating Calamari admin user")
      update_cmd = Mixlib::ShellOut.new('/srv/www/calamari/manage.py shell', :input => <<eos)
from django.contrib.auth.models import User
admin_user = User.objects.filter(is_superuser=True)[0]
admin_user.username = #{node[:ceph][:calamari][:username].dump}
admin_user.set_password(#{node[:ceph][:calamari][:password].dump})
admin_user.email = #{node[:ceph][:calamari][:email].dump}
admin_user.save()
eos
      update_cmd.run_command
      update_cmd.error!
    end
    # verify services are all started (slightly paranoid; the only
    # one of these I've seen fail in real life was apache when the
    # config was broken due to a bug)
    [ 'salt-master', 'carbon-cache', 'cthulhu', 'apache2' ].each do |s|
      %x[service '#{s}' status]
      # this works to catch service failure, but output is horrible
      # (has a backtrace & whatnot)
      raise "Service #{s} is not running" unless $?.exitstatus == 0
    end
  end
end

# TODO: Is there any way we can auto-auth salt minions?  This would be nice,
# but is not critical given the user is prompted to authorize them the first
# time they log in to Calamari.

