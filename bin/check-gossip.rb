require 'nokogiri'
require 'open-uri'
require 'socket'
require 'Resolv'
require 'sensu-plugin/check/cli'


class CheckGossip < Sensu::Plugin::Check::CLI
  option :discover_via_dns,
         description: 'Whether to use DNS lookup to discover other cluster nodes. (Default: true)',
         short: '-discover_via_dns',
         long: '--discover_via_dns discover_via_dns',
         default: 'true'

  option :cluster_dns,
         description: 'DNS name from which other nodes can be discovered.',
         short: '-dns',
         long: '--cluster_dns cluster_dns',
         default: 'localhost'

  option :gossip_address,
         description: 'If discover_via_dns is set to false then this address will be used for gossip. (Default localhost)',
         short: '-g',
         long: '--gossip_ip gossip_ip',
         default: 'localhost'

  option :gossip_port,
         description: 'What port to use when connecting to gossip. (Default 2113)',
         short: '-p',
         long: '--gossip_port gossip_port',
         default: '2113'

  option :expected_nodes,
         description: 'The total number of nodes we expect to be gossiping, including this one. (Default 2)',
         short: '-e',
         long: '--expected_nodes expected_nodes',
         default: 2

  def run
    discover_via_dns = config[:discover_via_dns]
    gossip_address = config[:gossip_address]
    gossip_port = config[:gossip_port]
    expected_nodes = config[:expected_nodes]

    if discover_via_dns
      cluster_dns = config[:cluster_dns]

      current_machine_ips = get_current_machine_ipv4s
      event_store_ips = get_event_store_ips_from_dns cluster_dns
      gossip_address = get_matching_ips current_machine_ips, event_store_ips
      #expected_nodes = event_store_ips.count
    end

    check_node gossip_address, gossip_port, expected_nodes
  end

  def get_matching_ips(machine_ips, event_store_ips)
    matched_ips = machine_ips.select do |ip_to_look_for|
      event_store_ips.find { |ip_to_match| ip_to_look_for == ip_to_match }
    end
    critical "#{matched_ips.count} ips were found for this machine in the event store dns lookup, cannot figure out where to check gossip from" unless matched_ips.one?
    matched_ips[0]
  end

  def get_masters(document)
    states = document.xpath '//State'
    states.count { |state| state.content == 'Master' }
  end

  def get_members(document)
    document.xpath '//MemberInfoDto'
  end

  def get_is_alive_nodes(document)
    document.xpath '//IsAlive'
  end

  def only_one_master?(document)
    get_masters(document) == 1
  end

  def node_count_is_correct?(document, expected_count)
    get_members(document).count == expected_count
  end

  def nodes_all_alive?(document)
    nodes = get_is_alive_nodes document
    nodes.all? { |node| node.content == 'true' }
  end

  def check_node(gossip_address, gossip_port, expected_nodes)
    puts "\nchecking gossip at #{gossip_address}:#{gossip_port}"
    gossip = open("http://#{gossip_address}:#{gossip_port}/gossip?format=xml")

    xml_doc = Nokogiri::XML(gossip.readline)

    puts "\tchecking for #{expected_nodes} nodes"
    critical "\twrong number of nodes, was #{get_members(xml_doc).count} should be exactly #{expected_nodes}" unless node_count_is_correct? xml_doc, expected_nodes

    puts "\tchecking nodes for IsAlive state"
    critical "\tat least 1 node is not alive" unless nodes_all_alive? xml_doc

    puts "\tchecking for exactly 1 master"
    critical "\twrong number of node masters, there should be exactly 1" unless only_one_master? xml_doc
    ok
  end

  def print_all(collection, type)
    puts "\nprinting #{type} collection"
    collection.each { |item| p item }
  end

  def get_event_store_ips_from_dns(dns_name)
    Resolv::DNS.open { |dns|
      resources = dns.getresources dns_name, Resolv::DNS::Resource::IN::A
      resources.map { |res| res.address.to_s }
    }
  end

  def get_current_machine_ipv4s
    loopback_regex = /^localhost$|^127(?:\.[0-9]+){0,2}\.[0-9]+$|^(?:0*\:)*?:?0*1$/
    ipv4_regex = /^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/

    potential_ips = Socket.ip_address_list.map{|info| info.ip_address}
    #.select {|info| not loopback_regex.match(info)}

    potential_ips.select { |info| ipv4_regex.match(info)}
  end
end

CheckGossip.new
