

case node[:platform]
when "suse"
  package "ceph" do
    action :install
  end
end

