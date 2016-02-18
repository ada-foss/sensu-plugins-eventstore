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
require 'open-uri'
require 'socket'
require 'resolv'
require 'sensu-plugin/check/cli'
require 'json'

class MetricsStats < Sensu::Plugin::Check::CLI

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

  def add_standard_stats(json_stats, stats_dict)
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
    metrics_wanted = ["avgItemsPerSecond", "avgProcessingTime", "currentIdleTime", "idleTimePercent", "length", "lengthCurrentTryPeak", "lengthLifetimePeak", "totalItemsProcessed"]

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

  def run
    stats = JSON.parse '{ "proc-startTime": "2016-02-10T13:21:58Z", "proc-id": 26613, "proc-mem": 494968832, "proc-cpu": 0.0, "proc-cpuScaled": 0.0, "proc-threadsCount": 0, "proc-contentionsRate": 0.0, "proc-thrownExceptionsRate": 0.0, "sys-cpu": 11.4026785, "sys-freeMem": 183107584, "proc-diskIo-readBytes": 1734651904, "proc-diskIo-writtenBytes": 34955264, "proc-diskIo-readOps": 459692, "proc-diskIo-writeOps": 9638, "proc-tcp-connections": 2, "proc-tcp-receivingSpeed": 28.403300796143856, "proc-tcp-sendingSpeed": 1065.1570389898163, "proc-tcp-inSend": 0, "proc-tcp-measureTime": "00:00:30.0669280", "proc-tcp-pendingReceived": 0, "proc-tcp-pendingSend": 0, "proc-tcp-receivedBytesSinceLastRun": 854, "proc-tcp-receivedBytesTotal": 14412940, "proc-tcp-sentBytesSinceLastRun": 32026, "proc-tcp-sentBytesTotal": 8499466, "proc-gc-allocationSpeed": 0.0, "proc-gc-gen0ItemsCount": 0, "proc-gc-gen0Size": 0, "proc-gc-gen1ItemsCount": 0, "proc-gc-gen1Size": 0, "proc-gc-gen2ItemsCount": 0, "proc-gc-gen2Size": 0, "proc-gc-largeHeapSize": 0, "proc-gc-timeInGc": 0.0, "proc-gc-totalBytesInHeaps": 0, "es-checksum": 2775762783, "es-checksumNonFlushed": 2775762783, "sys-drive-/var-availableBytes": 1793228800, "sys-drive-/var-totalBytes": 6159654912, "sys-drive-/var-usage": "70%", "sys-drive-/var-usedBytes": 4366426112, "es-queue-MainQueue-queueName": "MainQueue", "es-queue-MainQueue-groupName": "", "es-queue-MainQueue-avgItemsPerSecond": 26, "es-queue-MainQueue-avgProcessingTime": 0.063112862547288776, "es-queue-MainQueue-currentIdleTime": "0:00:00:00.0123288", "es-queue-MainQueue-currentItemProcessingTime": null, "es-queue-MainQueue-idleTimePercent": 99.83352707437956, "es-queue-MainQueue-length": 0, "es-queue-MainQueue-lengthCurrentTryPeak": 5, "es-queue-MainQueue-lengthLifetimePeak": 1154, "es-queue-MainQueue-totalItemsProcessed": 993316, "es-queue-MainQueue-inProgressMessage": "<none>", "es-queue-MainQueue-lastProcessedMessage": "Schedule", "es-queue-Master Replication Service-queueName": "Master Replication Service", "es-queue-Master Replication Service-groupName": "", "es-queue-Master Replication Service-avgItemsPerSecond": 0, "es-queue-Master Replication Service-avgProcessingTime": 0.0, "es-queue-Master Replication Service-currentIdleTime": "0:00:00:00.0004328", "es-queue-Master Replication Service-currentItemProcessingTime": null, "es-queue-Master Replication Service-idleTimePercent": 98.433272489548671, "es-queue-Master Replication Service-length": 2, "es-queue-Master Replication Service-lengthCurrentTryPeak": 0, "es-queue-Master Replication Service-lengthLifetimePeak": 0, "es-queue-Master Replication Service-totalItemsProcessed": 0, "es-queue-Master Replication Service-inProgressMessage": "<none>", "es-queue-Master Replication Service-lastProcessedMessage": "<none>", "es-queue-MonitoringQueue-queueName": "MonitoringQueue", "es-queue-MonitoringQueue-groupName": "", "es-queue-MonitoringQueue-avgItemsPerSecond": 0, "es-queue-MonitoringQueue-avgProcessingTime": 0.0, "es-queue-MonitoringQueue-currentIdleTime": "0:01:25:06.3000363", "es-queue-MonitoringQueue-currentItemProcessingTime": null, "es-queue-MonitoringQueue-idleTimePercent": 100.0, "es-queue-MonitoringQueue-length": 0, "es-queue-MonitoringQueue-lengthCurrentTryPeak": 0, "es-queue-MonitoringQueue-lengthLifetimePeak": 2, "es-queue-MonitoringQueue-totalItemsProcessed": 26, "es-queue-MonitoringQueue-inProgressMessage": "<none>", "es-queue-MonitoringQueue-lastProcessedMessage": "WriteEventsCompleted", "es-queue-Projection Core #0-queueName": "Projection Core #0", "es-queue-Projection Core #0-groupName": "Projection Core", "es-queue-Projection Core #0-avgItemsPerSecond": 0, "es-queue-Projection Core #0-avgProcessingTime": 0.0, "es-queue-Projection Core #0-currentIdleTime": "0:01:25:06.4274620", "es-queue-Projection Core #0-currentItemProcessingTime": null, "es-queue-Projection Core #0-idleTimePercent": 99.999999667417313, "es-queue-Projection Core #0-length": 0, "es-queue-Projection Core #0-lengthCurrentTryPeak": 0, "es-queue-Projection Core #0-lengthLifetimePeak": 0, "es-queue-Projection Core #0-totalItemsProcessed": 5, "es-queue-Projection Core #0-inProgressMessage": "<none>", "es-queue-Projection Core #0-lastProcessedMessage": "StartReader", "es-queue-Projections Master-queueName": "Projections Master", "es-queue-Projections Master-groupName": "", "es-queue-Projections Master-avgItemsPerSecond": 0, "es-queue-Projections Master-avgProcessingTime": 0.0, "es-queue-Projections Master-currentIdleTime": "0:01:25:06.3265243", "es-queue-Projections Master-currentItemProcessingTime": null, "es-queue-Projections Master-idleTimePercent": 100.0, "es-queue-Projections Master-length": 0, "es-queue-Projections Master-lengthCurrentTryPeak": 0, "es-queue-Projections Master-lengthLifetimePeak": 1, "es-queue-Projections Master-totalItemsProcessed": 19, "es-queue-Projections Master-inProgressMessage": "<none>", "es-queue-Projections Master-lastProcessedMessage": "RegularTimeout", "es-queue-Storage Chaser-queueName": "Storage Chaser", "es-queue-Storage Chaser-groupName": "", "es-queue-Storage Chaser-avgItemsPerSecond": 10, "es-queue-Storage Chaser-avgProcessingTime": 0.016086798679867988, "es-queue-Storage Chaser-currentIdleTime": "0:00:00:00.0460818", "es-queue-Storage Chaser-currentItemProcessingTime": null, "es-queue-Storage Chaser-idleTimePercent": 99.983877720833746, "es-queue-Storage Chaser-length": 0, "es-queue-Storage Chaser-lengthCurrentTryPeak": 0, "es-queue-Storage Chaser-lengthLifetimePeak": 0, "es-queue-Storage Chaser-totalItemsProcessed": 316000, "es-queue-Storage Chaser-inProgressMessage": "<none>", "es-queue-Storage Chaser-lastProcessedMessage": "ChaserCheckpointFlush", "es-queue-StorageReaderQueue #1-queueName": "StorageReaderQueue #1", "es-queue-StorageReaderQueue #1-groupName": "StorageReaderQueue", "es-queue-StorageReaderQueue #1-avgItemsPerSecond": 0, "es-queue-StorageReaderQueue #1-avgProcessingTime": 0.1688375, "es-queue-StorageReaderQueue #1-currentIdleTime": "0:00:00:02.9902373", "es-queue-StorageReaderQueue #1-currentItemProcessingTime": null, "es-queue-StorageReaderQueue #1-idleTimePercent": 99.995503814347856, "es-queue-StorageReaderQueue #1-length": 0, "es-queue-StorageReaderQueue #1-lengthCurrentTryPeak": 0, "es-queue-StorageReaderQueue #1-lengthLifetimePeak": 0, "es-queue-StorageReaderQueue #1-totalItemsProcessed": 7884, "es-queue-StorageReaderQueue #1-inProgressMessage": "<none>", "es-queue-StorageReaderQueue #1-lastProcessedMessage": "ReadStreamEventsForward", "es-queue-StorageReaderQueue #2-queueName": "StorageReaderQueue #2", "es-queue-StorageReaderQueue #2-groupName": "StorageReaderQueue", "es-queue-StorageReaderQueue #2-avgItemsPerSecond": 0, "es-queue-StorageReaderQueue #2-avgProcessingTime": 0.169975, "es-queue-StorageReaderQueue #2-currentIdleTime": "0:00:00:01.9896212", "es-queue-StorageReaderQueue #2-currentItemProcessingTime": null, "es-queue-StorageReaderQueue #2-idleTimePercent": 99.9954838587244, "es-queue-StorageReaderQueue #2-length": 0, "es-queue-StorageReaderQueue #2-lengthCurrentTryPeak": 0, "es-queue-StorageReaderQueue #2-lengthLifetimePeak": 0, "es-queue-StorageReaderQueue #2-totalItemsProcessed": 7884, "es-queue-StorageReaderQueue #2-inProgressMessage": "<none>", "es-queue-StorageReaderQueue #2-lastProcessedMessage": "ReadStreamEventsForward", "es-queue-StorageReaderQueue #3-queueName": "StorageReaderQueue #3", "es-queue-StorageReaderQueue #3-groupName": "StorageReaderQueue", "es-queue-StorageReaderQueue #3-avgItemsPerSecond": 0, "es-queue-StorageReaderQueue #3-avgProcessingTime": 0.18105, "es-queue-StorageReaderQueue #3-currentIdleTime": "0:00:00:00.9881607", "es-queue-StorageReaderQueue #3-currentItemProcessingTime": null, "es-queue-StorageReaderQueue #3-idleTimePercent": 99.995188192444189, "es-queue-StorageReaderQueue #3-length": 0, "es-queue-StorageReaderQueue #3-lengthCurrentTryPeak": 0, "es-queue-StorageReaderQueue #3-lengthLifetimePeak": 0, "es-queue-StorageReaderQueue #3-totalItemsProcessed": 7884, "es-queue-StorageReaderQueue #3-inProgressMessage": "<none>", "es-queue-StorageReaderQueue #3-lastProcessedMessage": "ReadStreamEventsForward", "es-queue-StorageReaderQueue #4-queueName": "StorageReaderQueue #4", "es-queue-StorageReaderQueue #4-groupName": "StorageReaderQueue", "es-queue-StorageReaderQueue #4-avgItemsPerSecond": 0, "es-queue-StorageReaderQueue #4-avgProcessingTime": 0.16297142857142857, "es-queue-StorageReaderQueue #4-currentIdleTime": "0:00:00:03.9916165", "es-queue-StorageReaderQueue #4-currentItemProcessingTime": null, "es-queue-StorageReaderQueue #4-idleTimePercent": 99.996207225933688, "es-queue-StorageReaderQueue #4-length": 0, "es-queue-StorageReaderQueue #4-lengthCurrentTryPeak": 0, "es-queue-StorageReaderQueue #4-lengthLifetimePeak": 0, "es-queue-StorageReaderQueue #4-totalItemsProcessed": 7883, "es-queue-StorageReaderQueue #4-inProgressMessage": "<none>", "es-queue-StorageReaderQueue #4-lastProcessedMessage": "ReadStreamEventsForward", "es-queue-StorageWriterQueue-queueName": "StorageWriterQueue", "es-queue-StorageWriterQueue-groupName": "", "es-queue-StorageWriterQueue-avgItemsPerSecond": 0, "es-queue-StorageWriterQueue-avgProcessingTime": 6.0735, "es-queue-StorageWriterQueue-currentIdleTime": "0:00:00:30.0562357", "es-queue-StorageWriterQueue-currentItemProcessingTime": null, "es-queue-StorageWriterQueue-idleTimePercent": 99.979799919461087, "es-queue-StorageWriterQueue-length": 0, "es-queue-StorageWriterQueue-lengthCurrentTryPeak": 0, "es-queue-StorageWriterQueue-lengthLifetimePeak": 24, "es-queue-StorageWriterQueue-totalItemsProcessed": 1977, "es-queue-StorageWriterQueue-inProgressMessage": "<none>", "es-queue-StorageWriterQueue-lastProcessedMessage": "WritePrepares", "es-queue-Subscriptions-queueName": "Subscriptions", "es-queue-Subscriptions-groupName": "", "es-queue-Subscriptions-avgItemsPerSecond": 1, "es-queue-Subscriptions-avgProcessingTime": 0.037046875, "es-queue-Subscriptions-currentIdleTime": "0:00:00:00.0123960", "es-queue-Subscriptions-currentItemProcessingTime": null, "es-queue-Subscriptions-idleTimePercent": 99.996039604171145, "es-queue-Subscriptions-length": 0, "es-queue-Subscriptions-lengthCurrentTryPeak": 0, "es-queue-Subscriptions-lengthLifetimePeak": 1111, "es-queue-Subscriptions-totalItemsProcessed": 213721, "es-queue-Subscriptions-inProgressMessage": "<none>", "es-queue-Subscriptions-lastProcessedMessage": "CheckPollTimeout", "es-queue-Timer-queueName": "Timer", "es-queue-Timer-groupName": "", "es-queue-Timer-avgItemsPerSecond": 19, "es-queue-Timer-avgProcessingTime": 0.2103560732113145, "es-queue-Timer-currentIdleTime": "0:00:00:00.0001258", "es-queue-Timer-currentItemProcessingTime": null, "es-queue-Timer-idleTimePercent": 99.577986697785988, "es-queue-Timer-length": 14, "es-queue-Timer-lengthCurrentTryPeak": 14, "es-queue-Timer-lengthLifetimePeak": 17, "es-queue-Timer-totalItemsProcessed": 555432, "es-queue-Timer-inProgressMessage": "<none>", "es-queue-Timer-lastProcessedMessage": "ExecuteScheduledTasks", "es-queue-Worker #1-queueName": "Worker #1", "es-queue-Worker #1-groupName": "Workers", "es-queue-Worker #1-avgItemsPerSecond": 3, "es-queue-Worker #1-avgProcessingTime": 0.25345267857142856, "es-queue-Worker #1-currentIdleTime": "0:00:00:00.0133278", "es-queue-Worker #1-currentItemProcessingTime": null, "es-queue-Worker #1-idleTimePercent": 99.905856789454674, "es-queue-Worker #1-length": 0, "es-queue-Worker #1-lengthCurrentTryPeak": 1, "es-queue-Worker #1-lengthLifetimePeak": 2, "es-queue-Worker #1-totalItemsProcessed": 145988, "es-queue-Worker #1-inProgressMessage": "<none>", "es-queue-Worker #1-lastProcessedMessage": "PurgeTimedOutRequests", "es-queue-Worker #2-queueName": "Worker #2", "es-queue-Worker #2-groupName": "Workers", "es-queue-Worker #2-avgItemsPerSecond": 3, "es-queue-Worker #2-avgProcessingTime": 0.220705, "es-queue-Worker #2-currentIdleTime": "0:00:00:00.0132287", "es-queue-Worker #2-currentItemProcessingTime": null, "es-queue-Worker #2-idleTimePercent": 99.91183064198367, "es-queue-Worker #2-length": 0, "es-queue-Worker #2-lengthCurrentTryPeak": 1, "es-queue-Worker #2-lengthLifetimePeak": 3, "es-queue-Worker #2-totalItemsProcessed": 146278, "es-queue-Worker #2-inProgressMessage": "<none>", "es-queue-Worker #2-lastProcessedMessage": "PurgeTimedOutRequests", "es-queue-Worker #3-queueName": "Worker #3", "es-queue-Worker #3-groupName": "Workers", "es-queue-Worker #3-avgItemsPerSecond": 3, "es-queue-Worker #3-avgProcessingTime": 0.14876902654867258, "es-queue-Worker #3-currentIdleTime": "0:00:00:00.0130986", "es-queue-Worker #3-currentItemProcessingTime": null, "es-queue-Worker #3-idleTimePercent": 99.9440366273687, "es-queue-Worker #3-length": 0, "es-queue-Worker #3-lengthCurrentTryPeak": 1, "es-queue-Worker #3-lengthLifetimePeak": 2, "es-queue-Worker #3-totalItemsProcessed": 147177, "es-queue-Worker #3-inProgressMessage": "<none>", "es-queue-Worker #3-lastProcessedMessage": "PurgeTimedOutRequests", "es-queue-Worker #4-queueName": "Worker #4", "es-queue-Worker #4-groupName": "Workers", "es-queue-Worker #4-avgItemsPerSecond": 3, "es-queue-Worker #4-avgProcessingTime": 0.12049732142857142, "es-queue-Worker #4-currentIdleTime": "0:00:00:00.0131623", "es-queue-Worker #4-currentItemProcessingTime": null, "es-queue-Worker #4-idleTimePercent": 99.955079040395148, "es-queue-Worker #4-length": 0, "es-queue-Worker #4-lengthCurrentTryPeak": 1, "es-queue-Worker #4-lengthLifetimePeak": 2, "es-queue-Worker #4-totalItemsProcessed": 145948, "es-queue-Worker #4-inProgressMessage": "<none>", "es-queue-Worker #4-lastProcessedMessage": "PurgeTimedOutRequests", "es-queue-Worker #5-queueName": "Worker #5", "es-queue-Worker #5-groupName": "Workers", "es-queue-Worker #5-avgItemsPerSecond": 3, "es-queue-Worker #5-avgProcessingTime": 0.18515221238938054, "es-queue-Worker #5-currentIdleTime": "0:00:00:00.0130835", "es-queue-Worker #5-currentItemProcessingTime": null, "es-queue-Worker #5-idleTimePercent": 99.9303564968982, "es-queue-Worker #5-length": 0, "es-queue-Worker #5-lengthCurrentTryPeak": 1, "es-queue-Worker #5-lengthLifetimePeak": 2, "es-queue-Worker #5-totalItemsProcessed": 146073, "es-queue-Worker #5-inProgressMessage": "<none>", "es-queue-Worker #5-lastProcessedMessage": "PurgeTimedOutRequests", "es-writer-lastFlushSize": 15486, "es-writer-lastFlushDelayMs": 5.558, "es-writer-meanFlushSize": 9025, "es-writer-meanFlushDelayMs": 3.19490869140625, "es-writer-maxFlushSize": 186369, "es-writer-maxFlushDelayMs": 9646.2947, "es-writer-queuedFlushMessages": 0, "es-readIndex-cachedRecord": 23764, "es-readIndex-notCachedRecord": 159691, "es-readIndex-cachedStreamInfo": 94434, "es-readIndex-notCachedStreamInfo": 23, "es-readIndex-cachedTransInfo": 0, "es-readIndex-notCachedTransInfo": 0  }'

    stats_dict = Hash.new

    add_standard_stats stats, stats_dict

    add_queue_stats stats, stats_dict

    puts stats_dict
  end

end