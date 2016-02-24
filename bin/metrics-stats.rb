#! /usr/bin/env ruby
#
#   check-gossip
#
# DESCRIPTION:
#    Metrics for the event store stats
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
require 'sensu-plugin/metric/cli'
require '../lib/ip-helper.rb'
require 'json'

class Stats < Sensu::Plugin::Metric::CLI::Graphite
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

  option :address,
         description: 'If discover_via_dns is set to false then this address will be used. (Default localhost)',
         short: '-a',
         long: '--address address',
         default: 'localhost'

  option :port,
         description: 'What port to use. (Default 2113)',
         short: '-p',
         long: '--port port',
         default: '2113'

  def run
    discover_via_dns = config[:discover_via_dns]
    address = config[:address]
    port = config[:port]

    if discover_via_dns
      cluster_dns = config[:cluster_dns]

      helper = IpHelper.new
      address = helper.get_local_ip_that_also_on_cluster cluster_dns

      critical address unless helper.is_valid_v4_ip address
    end

    force_downloaded_files_to_be_temp_files
    collect_metrics address, port
  end

  def force_downloaded_files_to_be_temp_files
    # Don't allow downloaded files to be created as StringIO. Force a tempfile to be created.
    OpenURI::Buffer.send :remove_const, 'StringMax' if OpenURI::Buffer.const_defined?('StringMax')
    OpenURI::Buffer.const_set 'StringMax', -1
  end

  def collect_metrics(address, port)
    #connection_url = "http://#{address}:#{port}/streams/$stats-#{address}:#{port}"
    stream_url = "http://127.0.0.1:5114/streams/$stats-127.0.0.1:5114"

    stream_temp_file = open stream_url, http_basic_authentication: ["admin", "changeit"],  "Accept" => "application/atom+xml"

    namespace_regex = / xmlns="[A-Za-z:\/.0-9]+"/

    #if we don't remove the namespace nokogiri parsing fails
    xml_stream_without_namespace = stream_temp_file.read.sub namespace_regex, ''

    xml_doc = Nokogiri::XML xml_stream_without_namespace

    puts xml_doc

    latest_entry = xml_doc.xpath('.//entry')
                       .sort  { |node| DateTime.parse node.xpath('.//updated').text }
                       .last

    event_number_regex = /[0-9]+$/
    event_number = event_number_regex.match latest_entry.at_xpath('.//id').content

    latest_event_url = "#{stream_url}/#{event_number.to_s.to_i}"

    element_temp_file = open latest_event_url, http_basic_authentication: ["admin", "changeit"],  "Accept" => "application/json"
    json_stats = element_temp_file.read



    ok
  end


  def add_metric(json_stats, stats_dict, stat_name_mapping)
    stat_value = json_stats[stat_name_mapping[:source_name]]
    stats_dict[stat_name_mapping[:target_name]] = stat_value
  end

  def add_metrics(json_stats, stats_dict, stat_name_mappings)
    stat_name_mappings.each {|stat_mapping| add_metric json_stats, stats_dict, stat_mapping}
  end

  def create_metric_mapping(source_name, target_name)
    {
      source_name: source_name,
      target_name:"eventstore.#{target_name}"
    }
  end

  def parse_json_stats(json_stats)
    name_mappings = [
        create_metric_mapping("proc-mem", "memory"),
        create_metric_mapping("proc-cpu", "cpu"),
        create_metric_mapping("proc-threadsCount", "threadsCount"),
        create_metric_mapping("proc-contentionsRate", "contentionsRate"),
        create_metric_mapping("proc-thrownExceptionsRate", "thrownExceptionsRate"),
        create_metric_mapping("proc-diskIo-readBytes", "diskIo.readBytes"),
        create_metric_mapping("proc-diskIo-writtenBytes", "diskIo.writtenBytes"),
        create_metric_mapping("proc-diskIo-readOps", "diskIo.readOps"),
        create_metric_mapping("proc-diskIo-writeOps", "diskIo.writeOps"),
        create_metric_mapping("proc-tcp-receivingSpeed", "tcp.receivingSpeed"),
        create_metric_mapping("proc-tcp-sendingSpeed", "tcp.sendingSpeed"),
        create_metric_mapping("proc-tcp-inSend", "tcp.inSend"),
        create_metric_mapping("proc-tcp-measureTime", "tcp.measureTime"),
        create_metric_mapping("proc-tcp-receivedBytesSinceLastRun", "tcp.receivedBytesSinceLastRun"),
        create_metric_mapping("proc-tcp-sentBytesSinceLastRun", "tcp.sentBytesSinceLastRun"),
        create_metric_mapping("proc-gc-gen0Size", "gc.gen0Size"),
        create_metric_mapping("proc-gc-gen1Size", "gc.gen1Size"),
        create_metric_mapping("proc-gc-gen2Size", "gc.gen2Size"),
        create_metric_mapping("proc-gc-largeHeapSize", "gc.largeHeapSize"),
        create_metric_mapping("proc-gc-totalBytesInHeaps", "gc.totalBytesInHeaps")
    ]

    add_metrics json_stats, stats_dict, name_mappings
  end

  def add_metrics_from_queue(queue, json_stats, stats_dict)
    queue_name = queue[0]

    metric_mappings = queue[1].map { |metric_name| create_metric_mapping "es-queue-#{queue_name}-#{metric_name}", "#{cleaned_name queue_name}.#{metric_name}" }

    metric_mappings.each {|mapping| add_metric json_stats, stats_dict, mapping}
  end

  def add_queue_stats(json_stats, stats_dict)
    metrics_wanted = %w(avgItemsPerSecond avgProcessingTime currentIdleTime idleTimePercent length lengthCurrentTryPeak lengthLifetimePeak totalItemsProcessed)

    split_on_queues = json_stats.keys
                          .select { |key| key.start_with? "es-queue-" }
                          .map { |key| key.split '-' }
                          .select { |split_key| metrics_wanted.any? { |metric| metric == split_key[3] } }
                          .group_by { |split_key| split_key[2] }

    queue_metrics = split_on_queues.map { |queue_with_metrics| [queue_with_metrics[0], queue_with_metrics[1].map { |metrics| metrics[3] }]}

    queue_metrics.each { |queue| add_metrics_from_queue queue, json_stats, stats_dict }
  end


  def cleaned_name(queue_name)
    character_regex = /[^A-Za-z0-9]+|es-queue/
    queue_name.gsub character_regex, ''
  end
end