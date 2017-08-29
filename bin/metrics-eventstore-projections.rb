#! /usr/bin/env ruby
#
#   metrics-eventstore-projections
#
# DESCRIPTION:
#    Metrics for the event store projections 
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

require 'json'
require 'ip-helper.rb'
require 'sensu-plugin/check/cli'
require 'time'

class StatsProjections < Sensu::Plugin::Check::CLI
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

  option :api_address,
         description: 'If discover_via_dns is set to false then this address will be used for the eventstore api. (Default localhost)',
         short: '-a',
         long: '--api_address api_address',
         default: 'localhost'

  option :api_port,
         description: 'What port to use when connecting to the eventstore api. (Default 2113)',
         short: '-p',
         long: '--api_port api_port',
         default: '2113'

  option :format,
         description: 'What to prepend to output each projection metric (Default "<cluster_dns>.eventstore")',
         short: '-f',
         long: '--format format',
         default: ''

  option :verbose,
           description: 'output extra messaging (Default false)',
           short: '-v',
           long: '--verbose verbose',
           default: 'false'

  def run
    no_discover_via_dns = config[:no_discover_via_dns]
    api_address = config[:api_address]
    api_port = config[:api_port]

    unless no_discover_via_dns
      cluster_dns = config[:cluster_dns]

      helper = IpHelper.new
      api_address = helper.get_local_ip_that_also_on_cluster cluster_dns

      critical api_address unless helper.is_valid_v4_ip api_address

    end

    collect_metrics api_address, api_port
  end

  def collect_metrics(api_address, api_port)

    begin
      connection_url = "http://#{api_address}:#{api_port}/projections/any"
      projections_api = open(connection_url)
    rescue StandardError
      critical "Could not connect to #{connection_url} to check api, has event store fallen over on this node? "
    end

    time_now = Time.now.to_i
    projections_data = JSON.parse projections_api.read

    projections_data['projections'].each { |projection|
      put_projection_metrics projection, time_now
    }

  end

  def put_projection_metrics(projection, time_of_reading)
    wanted_numeric_metrics = %w(writesInProgress readsInProgress partitionsCached progress eventsProcessedAfterRestart bufferedEvents writePendingEventsBeforeCheckpoint writePendingEventsAfterCheckpoint)

    this_prefix = get_graphite_prefix projection
    puts "#{this_prefix}.status #{get_encoded_status projection} #{time_of_reading}"
    
    wanted_numeric_metrics.each { |metric|
      puts "#{this_prefix}.#{metric} #{projection[metric]} #{time_of_reading}"
    }

    ok
  end

  def get_format
    return config[:format] unless config[:format].empty?
    dns_name = /^[^.]+/.match config[:cluster_dns]
    "#{dns_name}.eventstore"
  end

  def get_graphite_prefix(projection)
    "#{get_format}.#{projection['name']}"
  end

  def get_encoded_status(projection)
    lookup_table = {
      'Running' => 0,
      'Stopped' => 1
    }

    lookup_table[projection['status']] or -1 # -1 is unknown
  end

end
