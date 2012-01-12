#! /usr/bin/env ruby
require 'optparse'
require 'optparse/time'
require 'time'
require 'logger'

require File.join(File.dirname(__FILE__),'lib/crisply_api')

#
# Return a structure describing the options[:
#
def parse(args)
  # The options specified on the command line will be collected in *options*.
  # We set default values here.
  options = {}
  options[:guid] = 'post-activity-' + Time.now.to_f.to_s + "-" + Kernel.rand(2**64).to_s
  options[:verbose] = false

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{__FILE__} [options]"

    opts.separator ""
    opts.separator "Specific options:"

    opts.on("-a", "--account ACCOUNT", "The Crisply account to post activity to. This should be the part that comes before .crisply.com in your account URL.") do |acct|
      options[:account] = acct
    end

    opts.on("-u", "--user USER", "The Crisply user to post on behalf of. If specified, this user must be a member of the ACCOUNT, and the owner of the API key must be authorized to act on behalf of this user. The value of this parameter must either be the user's First and Last Name or one of their other aliases.") do |user|
      options[:author] = user
    end

    opts.on("-k", "--key KEY", "Crisply API key.") do |key|
      options[:key] = options[:token] = key
    end

    opts.on("-t", "--text TEXT", "The text of the activity item.") do |txt|
      options[:text] = txt
    end

    opts.on("-d", "--date DATE", Time, "The date/time at which the activity occurred. Server will default to now.") do |date|
      options[:date] = date
    end

    opts.on("-g", "--guid GUID", "A unique value that identifies this activity item and should be used by Crisply to prevent duplicate activity. Defaults to a random value.") do |guid|
      options[:guid] = guid
    end

    opts.on('--duration DURATION', Float, "The total duration of the activity in hours (decimal ok).") do |dur|
      options[:duration] = dur
    end

    opts.on('--type TYPE', "The type of activity (task, calendar, email, phone, document, place)") do |type|
      options[:type] = type
    end

    opts.on("--tag x[,y,z]", Array, "Tags to associate with the activity item") do |list|
      options[:tag] = list
    end

    opts.on("--deployment-domain DOMAIN", "Specify an alternate deployment domain to use. You probably don't want to use this unless you are a Crisply developer.") do |domain|
      options[:deployment_domain] = domain
    end

    opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
      options[:verbose] = v
    end

    # No argument, shows at tail.  This will print an options summary.
    # Try it and see!
    opts.on_tail("-h", "--help", "Show this message") do
      puts opts
      exit
    end

  end

  parser.parse!(args)
  
  need_exit = false

  ['account', 'key', 'text'].each do |required|
    if options[required.to_sym].nil?
      puts "Missing argument '#{required}'"
      need_exit = true
    end
  end
  
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

CrisplyApi.post_activity(options)


puts "\nDone" # This is for Dave
