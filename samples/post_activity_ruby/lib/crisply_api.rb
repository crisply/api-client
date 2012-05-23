require 'rubygems'
require 'rest_client'
require 'nokogiri'

class CrisplyApi
  attr_accessor :account, :token, :logger, :deployment_domain

  class << self #static

    def post_activity options
      api = new(options)
      api.post_activity(options)
    end

  end #static

  def initialize options
    self.logger = Logger.new($stdout)
    logger.level = options[:verbose] ? Logger::DEBUG : Logger::WARN
    self.account = options[:account]
    self.token = options[:token]
    self.deployment_domain = options[:deployment_domain] || 'crisply.com'
  end

  def endpoint thing
    base = "https://#{account}.#{deployment_domain}/timesheet/api/"
    url = case thing
    when :activity_items
      base + 'activity_items.xml'
    else
      raise "No endpoint found for #{thing}"
    end
    logger.debug "Using URL #{url}"
    return url
  end

  def headers
    {
      'Content-Type' => 'application/xml',
      'Accept' => 'application/xml',
      'X-Crisply-Authentication' => token
      }
  end

  def post_activity options
    options[:date] = options[:date].xmlschema if options[:date]
    builder = Nokogiri::XML::Builder.new do |xml|
      xml.send('activity-item',
        'xmlns' => 'http://crisply.com/api/v1') {
        [:guid, :text, :date, :type, :author, :duration, :project_id].each do |attr|
          value = options[attr]
          unless value.nil?
            logger.debug "Setting #{attr} to #{value}"
            xml.send((attr.to_s.gsub('_','-') + '_').to_sym, value)
          end
        end
        if options[:tag]
          xml.tags {
            options[:tag].each do |tag|
              xml.tag tag
            end
          }
        end
      }

    end

    xml = builder.to_xml
    puts "POSTing payload: #{xml}"
    response = RestClient.post(endpoint(:activity_items), xml, headers)
    puts "Received response: #{response.body}"

  rescue RestClient::InternalServerError, RestClient::RequestFailed, RestClient::Request::Unauthorized => e
    puts e.response.body
  end

end