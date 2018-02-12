#! /usr/bin/env ruby
#
#   check-projections
#
# DESCRIPTION:
#    Checks the event store projections 
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


class CheckProjections < Sensu::Plugin::Check::CLI
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

  option :progress_minimum,
         description: 'The minimum percentage of progress that is acceptable before raising critical. (Default: 100.0)',
         short: '-m',
         long: '--progress_minimum progress_minimum',
         proc: proc(&:to_f),
         default: 100.0

  def run
    no_discover_via_dns = config[:no_discover_via_dns]
    api_address = config[:api_address]
    api_port = config[:api_port]
    @progress_minimum = config[:progress_minimum]

    unless no_discover_via_dns
      cluster_dns = config[:cluster_dns]

      helper = IpHelper.new
      api_address = helper.get_local_ip_that_also_on_cluster cluster_dns

      critical api_address unless helper.is_valid_v4_ip api_address

    end

    check_node api_address, api_port
  end

  def get_projections_not_running
    @json_doc['projections'].select { |projection| projection['status'] != 'Running' }
  end

  def get_projections_not_done
    @json_doc['projections'].select { |projection| projection['progress'] < @progress_minimum }
  end

  def all_projections_running?
    get_projections_not_running.count == 0
  end

  def all_projections_done?
    get_projections_not_done.count == 0
  end

  def critical_projections_not_running
    critical "The following projections are not running: #{get_projections_not_running.map{|p| p['name']}.join ', '}"
  end

  def critical_projections_not_done
    critical "The following projections are not #{@progress_minimum}% done: #{get_projections_not_done.map{|p| p['name']}.join ', '}"
  end

  def check_node(api_address, api_port)

    begin
      connection_url = "http://#{api_address}:#{api_port}/projections/continuous"
      puts "\nchecking projections api at #{connection_url}"
      projections_api = open(connection_url)
    rescue StandardError
      critical "Could not connect to #{connection_url} to check api, has event store fallen over on this node? "
    end

    @json_doc = JSON.parse projections_api.read
    
    puts "Checking that all projections are running"
    critical_projections_not_running unless all_projections_running?

    puts "Checking that all projections are at least #{@progress_minimum}% done"
    critical_projections_not_done unless all_projections_done?

    ok "projections api at #{api_address} reports all projections are running and up to date"
  end
end
