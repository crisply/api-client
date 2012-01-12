#! /usr/bin/env ruby
require 'optparse'
require 'optparse/time'
require 'time'
require 'logger'
require 'yaml'

require File.join(File.dirname(__FILE__),'jira_crawler/jira')
require File.join(File.dirname(__FILE__),'jira_crawler/crisply_api')

module JiraCrawler
  class ActivityItem
    attr_accessor :text, :date, :tags, :guid, :author, :duration, :activity_type
  end
end

def parse(args)
  # The options specified on the command line will be collected in *options*.
  # We set default values here.
  options = {}
  options[:verbose] = false

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{__FILE__} [options]"

    opts.separator ""
    opts.separator "Specific options:"

    opts.on("-c", "--config path", "Path containing jira_crawler.yaml and jira_crawler.state. Defaults to the current working directory.") do |config_path|
      options[:config_path] = config_path
    end

    # No argument, shows at tail.  This will print an options summary.
    # Try it and see!
    opts.on_tail("-h", "--help", "Show this message") do
      puts opts
      exit
    end

  end

  parser.parse!(args)

  unless ARGV.empty?
    puts "Unrecognized argument(s): #{ARGV.join(', ')}"
    need_exit = true
  end

  if need_exit
    puts parser
    puts "Exiting"
    exit(1)
  end

  return options
end

options = parse ARGV

path = options[:config_path] || Dir.pwd
props = YAML.load(File.open(File.join(path,'jira_crawler.yaml')))

begin
  state = YAML.load(File.open(File.join(path,'jira_crawler.state')))
rescue Errno::ENOENT
  state = {}
end

logger = Logger.new($stdout)
logger.level = props['log_level'] || Logger::DEBUG

jira = JiraCrawler::Jira.new(props['jira_url'],props['jira_username'],props['jira_password'],state['jira_high_water_mark'])
jira.logger = logger

logger.info("Staring Jira crawl")

begin
  ai_list = jira.crawl(props['jira_max_items'],props['jira_max_days_old'])
rescue Exception => e
  logger.error "Content at the time of #{e}:\n#{jira.current_content}"
  raise e
end

logger.info("Found #{ai_list.size} activity items in the Jira feed")

#Sort chronologically (Jira Atom feed is reverse chrono)
ai_list.sort! {|a,b| a.date <=> b.date}


crisply = JiraCrawler::CrisplyApi.new(props['crisply_api_key'],props['crisply_account'],props['crisply_deployment_domain'])
crisply.logger = logger

ai_list.each do |ai|
  crisply.post_activity(ai)
end

#Raise high water mark only after a successful run
if(ai_list.size > 0)
  new_state = {'jira_high_water_mark' => ai_list.last.date}
  YAML.dump(new_state, File.open(File.join(path,'jira_crawler.state'),'w'))
end

puts "\nDone" # This is for Dave
