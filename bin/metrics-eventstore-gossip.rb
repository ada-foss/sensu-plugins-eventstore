#! /usr/bin/env ruby
#
#   metrics-eventstore-gossip
#
# DESCRIPTION:
#    Checks the event store gossip page, collecting metrics and outputting them in a graphite compatible format
# OUTPUT:
#   metric data
#
# PLATFORMS:
#   Linux, Windows
#
# DEPENDENCIES:
#   gem: sensu-plugin
#   gem: json
#
# NOTES:
#
# LICENSE:
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'json'
require 'date'
require 'ip-helper.rb'
require 'sensu-plugin/metric/cli'


class GossipMetrics < Sensu::Plugin::Metric::CLI::Graphite
  option :no_discover_via_dns,
         description: 'Whether to use DNS lookup to discover other cluster nodes. (Default: false)',
         boolean: true,
         short: '-v',
         long: '--no_discover_via_dns',
         default: false

  option :cluster_dns,
         description: 'DNS name from which other nodes can be discovered.',
         short: '-d',
         long: '--cluster_dns cluster_dns',
         default: 'localhost'

  option :address,
         description: 'If no_discover_via_dns is set then this address will be used. (Default localhost)',
         short: '-a',
         long: '--address address',
         default: 'localhost'

  option :port,
         description: 'What port to use. (Default 2114)',
         short: '-p',
         long: '--port port',
         default: '2114'

  option :metric_path,
         description: 'What to prepend to output metrics (Default "<hostname>.eventstore")',
         short: '-m',
         long: '--metric_path metric_path',
         default: "#{Socket.gethostname}.eventstore"

  option :eventstore_identifier,
         description: 'An optional identifier to tag the data in graphite with a specific eventstore instance (Default nil, meaning no additional tag at all)',
         long: '--eventstore_identifier eventstore_identifier',
         default: nil

  def run
    no_discover_via_dns = config[:no_discover_via_dns]
    address = config[:address]
    port = config[:port]

    eventstore_identifier = config[:eventstore_identifier].nil? ? '' : ( '.' + config[:eventstore_identifier] )
    @prefix = config[:metric_path] + eventstore_identifier + '.'

    unless no_discover_via_dns
      cluster_dns = config[:cluster_dns]

      helper = IpHelper.new
      address = helper.get_local_ip_that_also_on_cluster cluster_dns

      critical address unless helper.is_valid_v4_ip address

      expected_nodes = helper.get_ips_in_cluster cluster_dns
    end

    collect_metrics address, port
  end

  def collect_metrics(address, port)
    json_data = open("http://#{address}:#{port}/gossip?format=json") { |f| JSON.parse f.read }

    this_member = get_this_member json_data

    # time is taken to be from the point of view of eventstore
    member_time = DateTime.parse this_member['timeStamp']

    # state is a special case that need enumeration
    output ( @prefix + 'state' ), (get_encoded_state this_member['state']), member_time

    # other gossip metrics are passed straight through
    [
      'lastCommitPosition',
      'writerCheckpoint',
      'chaserCheckpoint',
      'epochPosition',
      'epochNumber'
    ].each do |metric|
      output ( @prefix + metric ), this_member[metric], member_time
    end

    ok
  end

  def get_this_member(json_data)
    serverIp = json_data['serverIp']
    these_members = json_data['members'].select { |m| m['internalHttpIp'] == serverIp }
    unknown "#{these_members.length} members matched serverIp in gossip" unless these_members.length == 1
    these_members[0]
  end

  def get_encoded_state(raw_state)
    [
      'Initialising', # 0
      'Unknown',      # 1
      'PreReplica',   # 2
      'CatchingUp',   # 3
      'Clone',        # 4
      'Slave',        # 5
      'PreMaster',    # 6
      'Master',       # 7
      'Manager',      # 8
      'ShuttingDown', # 9
      'Shutdown'      # 10
    ].index(raw_state) or -1 # unknown state
  end

end
