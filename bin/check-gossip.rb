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
# NOTES:
#
# LICENSE:
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'nokogiri'
require '../lib/ip-helper.rb'
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
         description: 'The total number of nodes we expect to be gossiping, including this one. (Default 4)',
         short: '-e',
         long: '--expected_nodes expected_nodes',
         default: '4'

  def run
    discover_via_dns = config[:discover_via_dns]
    gossip_address = config[:gossip_address]
    gossip_port = config[:gossip_port]
    expected_nodes = config[:expected_nodes].to_i

    if discover_via_dns
      cluster_dns = config[:cluster_dns]

      helper = IpHelper.new
      gossip_address = helper.get_local_ip_that_also_on_cluster cluster_dns

      critical gossip_address unless helper.is_valid_v4_ip gossip_address

      expected_nodes = helper.get_ips_in_cluster cluster_dns
    end

    check_node gossip_address, gossip_port, expected_nodes
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
    exit 1
  end

  def node_is_alive?(node)
    node.content == 'true'
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