#! /usr/bin/env ruby
#
#   check-gossip
#
# DESCRIPTION:
#    Checks the event store gossip page, making sure everything is working as expected
# OUTPUT:
#   plain text, metric data, etc
#
# PLATFORMS:
#   Linux, Windows
#
# DEPENDENCIES:
#   gem: sensu-plugin
#   gem: nokogiri
#
# USAGE:
#   #YELLOW
#
# NOTES:
#
# LICENSE:
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'nokogiri'
require 'open-uri'
require 'socket'
require 'resolv'
require 'sensu-plugin/check/cli'


class CheckGossip < Sensu::Plugin::Check::CLI
  option :discover_via_dns,
         description: 'Whether to use DNS lookup to discover other cluster nodes. (Default: true)',
         short: '-v',
         long: '--discover_via_dns discover_via_dns',
         default: 'true'

  option :cluster_dns,
         description: 'DNS name from which other nodes can be discovered.',
         short: '-d',
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
         default: '2'

  def run
    discover_via_dns = config[:discover_via_dns]
    gossip_address = config[:gossip_address]
    gossip_port = config[:gossip_port]
    expected_nodes = config[:expected_nodes].to_i

    if discover_via_dns
      cluster_dns = config[:cluster_dns]

      current_machine_ips = get_current_machine_ipv4s
      event_store_ips = get_event_store_ips_from_dns cluster_dns
      critical_no_event_store_ips cluster_dns unless event_store_ips.any?
      gossip_address = get_matching_ips current_machine_ips, event_store_ips
      expected_nodes = event_store_ips.count
    end

    check_node gossip_address, gossip_port, expected_nodes
  end

  def get_matching_ips(machine_ips, event_store_ips)
    matched_ips = machine_ips.select do |ip_to_look_for|
      event_store_ips.find { |ip_to_match| ip_to_look_for == ip_to_match }
    end
    critical_no_matching_ips machine_ips, event_store_ips unless matched_ips.one?
    matched_ips[0]
  end

  def get_master_count(document)
    get_states(document).count { |state| state.content == 'Master' }
  end

  def get_members(document)
    document.xpath '//MemberInfoDto'
  end

  def get_is_alive_nodes(document)
    document.xpath '//IsAlive'
  end

  def get_states(document)
    document.xpath '//State'
  end

  def only_one_master?(document)
    get_master_count(document) == 1
  end

  def all_nodes_master_or_slave?(document)
    states = get_states document
    states.all? {|node| node.content == "Master" || node.content == "Slave"}
  end

  def node_count_is_correct?(document, expected_count)
    get_members(document).count == expected_count
  end

  def nodes_all_alive?(document)
    nodes = get_is_alive_nodes document
    nodes.all? { |node| node_is_alive? node }
  end

  def critical_no_matching_ips(machine_ips, event_store_ips)
    critical "this machine has ips of #{machine_ips}, event store (according to dns lookup) has ips of #{event_store_ips}. There should be exactly one match, but wasn't. "
  end
  def critical_no_event_store_ips(dns_name)
    critical "could not find any ips at dns name #{dns_name} so cannot check gossips"
  end
  def critical_missing_nodes(xml_doc, expected_nodes)
    critical "Wrong number of nodes, was #{get_members(xml_doc).count} should be #{expected_nodes}"
  end
  def critical_dead_nodes(xml_doc, expected_nodes)
    critical "Only #{get_is_alive_nodes(xml_doc).count { |node| node_is_alive? node}} alive nodes, should be #{expected_nodes} alive"
  end
  def critical_master_count(xml_doc)
    critical "Wrong number of node masters, there should be 1 but there were #{get_master_count(xml_doc)} masters"
  end
  def warn_nodes_not_ready(xml_doc)
    states = get_states xml_doc
    states = states.find { |node| node.content != "Master" and node.content != "Slave"}
    warn "nodes found with states: #{states} when expected Master or Slave."
  end

  def node_is_alive?(node)
    node.content == 'true'
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
                          .select {|info| not loopback_regex.match(info)}

    potential_ips.select { |info| ipv4_regex.match(info)}
  end

  def check_node(gossip_address, gossip_port, expected_nodes)
    puts "\nchecking gossip at #{gossip_address}:#{gossip_port}"

    begin
      connection_url = "http://#{gossip_address}:#{gossip_port}/gossip?format=xml"
      gossip = open(connection_url)

    rescue StandardError
      critical "Could not connect to #{connection_url} to check gossip, has event store fallen over on this node? "
    end

    xml_doc = Nokogiri::XML(gossip.readline)

    puts "Checking for #{expected_nodes} nodes"
    critical_missing_nodes xml_doc, expected_nodes unless node_count_is_correct? xml_doc, expected_nodes

    puts "Checking nodes for IsAlive state"
    critical_dead_nodes xml_doc, expected_nodes unless nodes_all_alive? xml_doc

    puts "Checking for exactly 1 master"
    critical_master_count xml_doc unless only_one_master? xml_doc

    puts "Checking node state"
    warn_nodes_not_ready xml_doc unless all_nodes_master_or_slave? xml_doc

    ok "#{gossip_address} is gossiping with #{expected_nodes} nodes, all nodes are alive, exactly one master node was found and all other nodes are in the 'Slave' state."
  end
end