#!/usr/bin/env ruby

require 'nokogiri'
require 'socket'
require 'optparse'
require 'yaml'

script_dir = File.dirname(__FILE__)
if ( File.exist?('/etc/passenger_collectd.conf'))
  conf_file = '/etc/passenger_collectd.conf'
elsif ( File.exist?('/usr/local/etc/passenger_collectd.conf'))
  conf_file = '/usr/local/etc/passenger_collectd.conf'
elsif ( File.exist?("#{script_dir}/passenger_collectd.conf"))
  conf_file = "#{script_dir}/passenger_collectd.conf"
else
    abort("\nNo configuration file in /etc, /usr/local/etc, or #{script_dir}")
end

options = YAML.load_file("#{conf_file}")

# set defaults for some options if not specified in config and abort if no server is specifed
if ( options['cmd_path'].nil? ) || (!options['cmd_path'].nil? && options['cmd_path'].empty?)
  options['cmd_path'] = '/usr/bin/passenger-status'
end
if ( options['scheme'].nil? ) || (!options['scheme'].nil? && options['scheme'].empty?)
  options['scheme'] = "#{Socket.gethostname.downcase}/passenger"
end
if ( options['collect_interval'].nil? ) || (!options['collect_interval'].nil? && options['collect_interval'].empty?)
  options['collect_interval'] = '60'
end

# REMOVE_PATH is stripped from the metric name. The root directory which contains the directories for your app(s).
REMOVE_PATH = "#{options['metric_strip']}"
TIMESTAMP = Time.now.to_i.to_s
METRIC_BASE_NAME = "#{options['scheme']}"
INTERVAL= "#{options['collect_interval']}"

#PROCESS_ELEMENTS = %w(pid real_memory swap cpu vmsize processed)
PROCESS_ELEMENTS = %w(real_memory cpu vmsize processed sessions busyness)
#PROCESS_ELEMENTS = %w(real_memory cpu)

while true
  
  #doc = Nokogiri::XML(File.open("#{script_dir}/passenger-out.xml"))  # for testing with a local xml file
  doc = Nokogiri::XML(`sudo #{options['cmd_path']} --show=xml`)
  
  # Get overall (top level) passenger stats
  process_count = doc.xpath('//process_count').children[0].to_s
  max_pool_size = doc.xpath('//max').children[0].to_s
  capacity_used = doc.xpath('//capacity_used').children[0].to_s
  top_level_queue = doc.xpath('//get_wait_list_size').children[0].to_s
  
  puts("PUTVAL \"#{METRIC_BASE_NAME}/process_count\" interval=#{INTERVAL} N:#{process_count} ")
  puts("PUTVAL \"#{METRIC_BASE_NAME}/max_pool_size\" interval=#{INTERVAL} N:#{max_pool_size} ")
  puts("PUTVAL \"#{METRIC_BASE_NAME}/capacity_used\" interval=#{INTERVAL} N:#{capacity_used} ")
  puts("PUTVAL \"#{METRIC_BASE_NAME}/top_level_queue\" interval=#{INTERVAL} N:#{top_level_queue} ")
  
  # extract stat given process element
  def extract_elements(process, prefix_name)
    PROCESS_ELEMENTS.map { |el| "\"#{prefix_name}/#{el}\" " + "interval=#{INTERVAL} N:" + process.xpath("./#{el}").first.content }
  end
  
  # get process stats in the correct format and strip REMOVE_PATH
  def name_format(name, process_index)
    name.gsub(/#{REMOVE_PATH}/,'').gsub(/current$/,'') + "process_#{process_index}"
  end
  
  # Get per app and per process stats
  doc.xpath('//supergroups')[0].xpath('./supergroup').each do |supergroup|
    name = METRIC_BASE_NAME + '/' + supergroup.xpath('./name')[0].content
    # Per app overall stats
    wait_list = supergroup.xpath('./get_wait_list_size')[0].content
    capacity_used = supergroup.xpath('./capacity_used')[0].content
    prefix_name_ = name.gsub(/#{REMOVE_PATH}/,'').gsub(/\/current$/,'')
    puts("PUTVAL \"#{prefix_name_}/wait_list\" interval=#{INTERVAL} N:#{wait_list} ")
    puts("PUTVAL \"#{prefix_name_}/capacity_used\" interval=#{INTERVAL} N:#{capacity_used} ")
   # Per process stats
    supergroup.xpath('./group/processes/process').each_with_index do |process, i|
      prefix_name = name_format(name, i)
      extract_elements(process, prefix_name).each do |stat| 
      #  puts("prefix_name: #{prefix_name}")
        puts("PUTVAL #{stat}")
      end
    end
  end
  sleep INTERVAL.to_f
end 
