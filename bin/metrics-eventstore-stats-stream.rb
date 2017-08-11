#! /usr/bin/env ruby
#
#   Stats
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

require 'date'
require 'nokogiri'
require 'sensu-plugin/metric/cli'
require 'ip-helper.rb'
require 'json'

class Stats < Sensu::Plugin::Metric::CLI::Graphite
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
         description: 'If discover_via_dns is set to false then this address will be used. (Default localhost)',
         short: '-a',
         long: '--address address',
         default: 'localhost'

  option :port,
         description: 'What port to use. (Default 2114)',
         short: '-p',
         long: '--port port',
         default: '2114'

  option :use_authentication,
         description: 'Should use authentication (Default false)',
         short: '-u',
         long: '--use_authentication use_authentication',
         default: 'false'

  option :auth_user,
         description: 'Username for stats stream auth. (Default "admin")',
         short: '-r',
         long: '--auth_user auth_user',
         default: 'admin'

  option :auth_password,
         description: 'What port to use. (Default "changeit")',
         short: '-w',
         long: '--auth_password auth_password',
         default: 'changeit'

  option :proc_scheme,
         description: 'What to prepend to output proc metrics (Default "<hostname>.eventstore")',
         short: '-s',
         long: '--proc_scheme proc_scheme',
         default: "#{Socket.gethostname}.eventstore"

  option :queue_scheme,
         description: 'What to prepend to output queue metrics (Default "<cluster_dns>.eventstore")',
         short: '-q',
         long: '--queue_scheme queue_scheme',
         default: ""

  option :eventstore_identifier,
         description: 'An optional identifier to tag the data in graphite with a specific eventstore instance (Default nil, meaning no additional tag at all)',
         long: '--eventstore_identifier eventstore_identifier',
         default: nil

  option :verbose,
           description: 'output extra messaging (Default false)',
           short: '-v',
           long: '--verbose verbose',
           default: 'false'

  def get_queue_scheme
    return config[:queue_scheme] unless config[:queue_scheme].empty?
    #get the first part of the cluster dns
    dns_name = /^[^.]+/.match config[:cluster_dns]
    "#{dns_name}.eventstore"
  end

  def run
    no_discover_via_dns = config[:no_discover_via_dns]
    address = config[:address]
    port = config[:port]

    unless no_discover_via_dns
      cluster_dns = config[:cluster_dns]

      helper = IpHelper.new
      address = helper.get_local_ip_that_also_on_cluster cluster_dns

      critical address unless helper.is_valid_v4_ip address
    end

    collect_metrics address, port
  end

  def force_web_requests_to_use_temp_files
    # Don't allow downloaded files to be created as StringIO. Force a tempfile to be created.
    OpenURI::Buffer.send :remove_const, 'StringMax' if OpenURI::Buffer.const_defined?('StringMax')
    OpenURI::Buffer.const_set 'StringMax', -1
  end

  def collect_metrics(address, port)
    stream_url = "http://#{address}:#{port}/streams/$stats-#{address}:#{port}"

    force_web_requests_to_use_temp_files
    stream_temp_file = get_stream stream_url, "application/atom+xml"

    namespace_regex = / xmlns="[A-Za-z:\/.0-9]+"/

    #if we don't remove the namespace nokogiri parsing fails
    xml_stream_without_namespace = stream_temp_file.read.sub namespace_regex, ''

    xml_doc = Nokogiri::XML xml_stream_without_namespace

    puts xml_doc if verbose?

    latest_entry = xml_doc.xpath('.//entry')
                       .sort  { |node| DateTime.parse node.xpath('.//updated').text }
                       .last


    ok if latest_entry.nil?
    
    latest_event_url = latest_entry.at_xpath('.//id').content

    element_temp_file = get_stream latest_event_url, "application/json"

    json_stats = JSON.parse element_temp_file.read

    puts "json stats #{json_stats}" if verbose?

    stats_dict = add_standard_metrics json_stats

    add_metrics_for_queues json_stats, stats_dict

    stat_time = latest_entry.at_xpath('.//updated').content

    puts "stat retrived for time #{stat_time}" if verbose?

    parsed_date_time = DateTime.parse(stat_time)

    stats_dict.each { |stat| output stat[0], stat[1], parsed_date_time.strftime('%s')}

    ok
  end

  def verbose?
    config_is_true config[:verbose]
  end

  def get_stream(stream_url, accept_type)
    puts "opening stream @ url #{stream_url}" if verbose?

    if config_is_true config[:use_authentication]
      username = config[:auth_user]
      password = config[:auth_password]
      open stream_url, http_basic_authentication:[username, password], "Accept" => accept_type
    else
      open stream_url, "Accept" => accept_type
    end
  end

  def config_is_true(config)
    "true".casecmp(config) == 0
  end

  def add_metric(json_stats, stats_dict, stat_name_mapping)
    stat_value = json_stats[stat_name_mapping[:source_name]]
    stats_dict[stat_name_mapping[:target_name]] = stat_value
  end

  def get_eventstore_identifier
    eventstore_identifier = config[:eventstore_identifer].nil? ? '' : ( config[:eventstore_identifier] + '.' )
  end

  def create_proc_mapping(source_name, target_name)
    {
        source_name: source_name,
        target_name:"#{config[:proc_scheme]}.#{get_eventstore_identifier}#{target_name}"
    }
  end
  def create_queue_mapping(source_name, target_name)
    {
        source_name: source_name,
        target_name:"#{get_queue_scheme}.#{get_eventstore_identifier}#{target_name}"
    }
  end

  def add_standard_metrics(json_stats)
    name_mappings = [
        create_proc_mapping("proc-mem", "memory"),
        create_proc_mapping("proc-cpu", "cpu"),
        create_proc_mapping("proc-threadsCount", "threadsCount"),
        create_proc_mapping("proc-contentionsRate", "contentionsRate"),
        create_proc_mapping("proc-thrownExceptionsRate", "thrownExceptionsRate"),
        create_proc_mapping("proc-diskIo-readBytes", "diskIo.readBytes"),
        create_proc_mapping("proc-diskIo-writtenBytes", "diskIo.writtenBytes"),
        create_proc_mapping("proc-diskIo-readOps", "diskIo.readOps"),
        create_proc_mapping("proc-diskIo-writeOps", "diskIo.writeOps"),
        create_proc_mapping("proc-tcp-receivingSpeed", "tcp.receivingSpeed"),
        create_proc_mapping("proc-tcp-sendingSpeed", "tcp.sendingSpeed"),
        create_proc_mapping("proc-tcp-inSend", "tcp.inSend"),
        create_proc_mapping("proc-tcp-measureTime", "tcp.measureTime"),
        create_proc_mapping("proc-tcp-receivedBytesSinceLastRun", "tcp.receivedBytesSinceLastRun"),
        create_proc_mapping("proc-tcp-sentBytesSinceLastRun", "tcp.sentBytesSinceLastRun"),
        create_proc_mapping("proc-gc-gen0Size", "gc.gen0Size"),
        create_proc_mapping("proc-gc-gen1Size", "gc.gen1Size"),
        create_proc_mapping("proc-gc-gen2Size", "gc.gen2Size"),
        create_proc_mapping("proc-gc-largeHeapSize", "gc.largeHeapSize"),
        create_proc_mapping("proc-gc-totalBytesInHeaps", "gc.totalBytesInHeaps")
    ]
    stats_dict = Hash.new
    name_mappings.each {|stat_mapping| add_metric json_stats, stats_dict, stat_mapping}

    stats_dict
  end

  def add_metrics_for_queues(json_stats, stats_dict)
    metrics_wanted = %w(avgItemsPerSecond avgProcessingTime currentIdleTime idleTimePercent length lengthCurrentTryPeak lengthLifetimePeak totalItemsProcessed)

    split_on_queues = json_stats.keys
                          .select { |key| key.start_with? "es-queue-" }
                          .map { |key| key.split '-' }
                          .select { |split_key| metrics_wanted.any? { |metric| metric == split_key[3] } }
                          .group_by { |split_key| split_key[2] }

    queue_metrics = split_on_queues.map { |queue_with_metrics| [queue_with_metrics[0], queue_with_metrics[1].map { |metrics| metrics[3] }]}

    queue_metrics.each { |queue| add_metrics_for_queue queue, json_stats, stats_dict }
  end

  def add_metrics_for_queue(queue, json_stats, stats_dict)
    queue_name = queue[0]

    metric_mappings = queue[1].map { |metric_name| create_queue_mapping "es-queue-#{queue_name}-#{metric_name}", "#{cleaned_name queue_name}.#{metric_name}" }

    metric_mappings.each {|mapping| add_metric json_stats, stats_dict, mapping}
  end

  def cleaned_name(queue_name)
    character_regex = /[^A-Za-z0-9]+|es-queue/
    queue_name.gsub character_regex, ''
  end
end
