require 'rubygems'
require 'rest_client'
require 'nokogiri'

module JiraCrawler

  class CrisplyApi
    attr_accessor :logger

    def initialize(crisply_api_key, crisply_account, crisply_deployment_domain)
      @crisply_api_key = crisply_api_key
      @crisply_account = crisply_account
      @crisply_deployment_domain = crisply_deployment_domain || 'crisply.com'
      self.logger = Logger.new($stdout)
    end

    def endpoint thing
      base = "https://#{@crisply_account}.#{@crisply_deployment_domain}/timesheet/api/"
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
        'X-Crisply-Authentication' => @crisply_api_key
        }
    end

    def post_activity activity_item
      builder = Nokogiri::XML::Builder.new do |xml|
        xml.send('activity-item',
          'xmlns' => 'http://crisply.com/api/v1') {
            xml.guid activity_item.guid
            xml.text_ activity_item.text
            xml.date activity_item.date.xmlschema
            xml.type_ activity_item.activity_type
            xml.author activity_item.author
            if !activity_item.tags.empty?
              xml.tags {
                activity_item.tags.each do |tag|
                  xml.tag tag
                end
              }
            end
          }
      end

      xml = builder.to_xml
      logger.debug "POSTing payload: #{xml}"

      response = RestClient.post(endpoint(:activity_items), xml, headers)

      logger.debug "Response: #{response.body}"

    rescue RestClient::UnprocessableEntity => e
      if e.response.body =~ /<guid>taken<\/guid>/
        logger.info "Duplicate GUID (#{activity_item.guid} for author: #{activity_item.author}"
      else
        logger.warn "Unable to POST activity: #{xml}\nResponse:#{e.response.body}"
      end
    rescue RestClient::InternalServerError, RestClient::RequestFailed, RestClient::Request::Unauthorized => e
      logger.error e.response.body
      raise e
    end

  end
end