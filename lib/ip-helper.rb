require 'open-uri'
require 'socket'
require 'resolv'


class IpHelper
  def get_local_ip_that_also_on_cluster(cluster_dns)
    current_machine_ips = get_current_machine_ipv4s
    event_store_ips = get_event_store_ips_from_dns cluster_dns

    return no_event_store_ips_error cluster_dns unless event_store_ips.any?

    get_matching_ips current_machine_ips, event_store_ips
  end

  def get_ips_in_cluster(cluster_dns)
    event_store_ips = get_event_store_ips_from_dns cluster_dns
    return event_store_ips.count unless event_store_ips == nil
    return 0
  end

  def is_valid_v4_ip(potential_ip)
    /^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/.match potential_ip
  end

  def get_current_machine_ipv4s
    loopback_regex = /^localhost$|^127(?:\.[0-9]+){0,2}\.[0-9]+$|^(?:0*\:)*?:?0*1$/

    potential_ips = Socket.ip_address_list.map{|info| info.ip_address}
                          .select {|info| not loopback_regex.match(info)}

    potential_ips.select { |info| is_valid_v4_ip info}
  end

  def get_matching_ips(machine_ips, event_store_ips)
    matched_ips = machine_ips.select do |ip_to_look_for|
      event_store_ips.find { |ip_to_match| ip_to_look_for == ip_to_match }
    end
    return no_matching_ip_error machine_ips, event_store_ips unless matched_ips.one?

    matched_ips[0]
  end

  def get_event_store_ips_from_dns(dns_name)
    Resolv::DNS.open { |dns|
      resources = dns.getresources dns_name, Resolv::DNS::Resource::IN::A
      resources.map { |res| res.address.to_s }
    }
  end

  def no_matching_ip_error(machine_ips, event_store_ips)
    "this machine has ips of #{machine_ips}, event store (according to dns lookup) has ips of #{event_store_ips}. There should be exactly one match, but wasn't. "
  end

  def no_event_store_ips_error(dns_name)
    "could not find any ips at dns name #{dns_name} so cannot check gossips"
  end
end