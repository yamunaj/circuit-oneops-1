# Exit the chef application process with the given error message
#
# @param : msg -  Error message
#
def exit_with_error(msg)
  puts "***FAULT:FATAL=#{msg}"
  Chef::Application.fatal!(msg)
end

# get enabled network using the openstack compute cloud service
def get_enabled_network(compute_service,attempted_networks)

  has_sdn = true
  enabled_networks = []
  if compute_service.has_key?('enabled_networks')
    enabled_networks = JSON.parse(compute_service['enabled_networks'])
  end

  if enabled_networks.nil? || enabled_networks.empty?
    enabled_networks = [ compute_service['subnet'] ]
  end

  enabled_networks = enabled_networks - attempted_networks

  if enabled_networks.size == 0
    exit_with_error "no ip available in enabled networks for cloud #{node[:workorder][:cloud][:ciName]}. tried: #{attempted_networks} - escalate to openstack team"
  end

  network_name = enabled_networks.sample
  Chef::Log.info("network_name: "+network_name)

  # net_id for specifying network to use via subnet attr
  net_id = ''
  begin
    quantum = Fog::Network.new({
      :provider => 'OpenStack',
      :openstack_api_key => compute_service[:password],
      :openstack_username => compute_service[:username],
      :openstack_tenant => compute_service[:tenant],
      :openstack_auth_url => compute_service[:endpoint]
    })

    quantum.networks.each do |net|
      if net.name == network_name
        Chef::Log.info("network_id: "+net.id)
        net_id = net.id
        break
      end
    end
  rescue Exception => e
    Chef::Log.warn("no quantum or neutron networking installed")
    has_sdn = false
  end
   
  exit_with_error "Your #{node[:workorder][:cloud][:ciName]} cloud is configured to use network: #{compute_service[:subnet]} but is not found." if net_id.empty? && has_sdn

  return network_name, net_id
end

def is_propagate_update
  rfcCi = node.workorder.rfcCi
  if (rfcCi.ciBaseAttributes.nil? || rfcCi.ciBaseAttributes.empty?) && rfcCi.has_key?('hint') && !rfcCi.hint.empty?
    hint = JSON.parse(rfcCi.hint)
    puts "rfc hint >> " + rfcCi.hint.inspect
    if hint.has_key?('propagation') && hint['propagation'] == 'true'
      return true;
    end
  end
  return false
end

def find_latest_fast_image(images, pattern)
  return_image = nil
  images.each do |image|
    # check if valid
    if image.name =~ /#{pattern}/i
      # break up name into its parts
      image_name_parts = image.name.split('-')

      # get age
      age_current = "#{image_name_parts[4].gsub(/v/, "")}#{image_name_parts[5]}".to_i

      # check against saved if exists
      if return_image.nil?
        return_image = image
      else
        age_old =  "#{(return_image.name.split('-'))[4].gsub(/v/, "")}#{(return_image.name.split('-'))[5]}".to_i
        if age_current > age_old
          return_image = image
        end
      end
    end
  end
  return return_image
end

# Returns the image object from Openstack
# Looks up by name if global flag is set and flavor is not baremetal
# Reverts to image id lookup if no Fast Image is found by name
def get_image(images, flavor, flag_FAST_IMAGE, flag_TESTING_MODE, default_image, custom_id, ostype)
  if flag_FAST_IMAGE =~ /true/ && flavor.name.downcase !~ /baremetal/ && !custom_id

    flag_TESTING_MODE =~ /true/ ? (pattern = "wmlabs-#{ostype.gsub(/\./, "")}.*snapshot") : (pattern = "wmlabs-#{ostype.gsub(/\./, "")}")
    return_image = find_latest_fast_image(images, pattern)

    if return_image.nil?
      return default_image
    else
      return return_image
    end

  else

    return default_image

  end
end