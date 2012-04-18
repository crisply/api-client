require 'uri'
require 'rubygems'
require 'nokogiri'
require 'rest_client'

module JiraCrawler

  class Jira
    DEFAULT_MAX_DAYS_OLD = 14
    DEFAULT_MAX_ITEMS = 100
    #14 days old
    TOO_OLD = 14
    attr_reader :current_content
    attr_accessor :logger


    def initialize(jira_url, jira_username, jira_password, jira_high_water_mark)
      @jira_url = jira_url
      @jira_username = jira_username
      @jira_password = jira_password
      @jira_high_water_mark = jira_high_water_mark
      @current_content = nil
      self.logger = Logger.new($stdout)
    end


    def crawl max_items, max_days_old
      max_days_old ||= DEFAULT_MAX_DAYS_OLD
      max_items ||= DEFAULT_MAX_ITEMS
      @jira_high_water_mark = @jira_high_water_mark || (Time.now - (max_days_old * 24 * 60 * 60))
      # assuming an url formatted like http://tickets.opscode.com/browse/COOK
      base_url, project_name = @jira_url.split('browse/')
      min_date_param = (@jira_high_water_mark.to_i + 1)  * 1000 # jira expects milliseconds since epoch
      activity_stream_url = base_url + "plugins/servlet/streams?key=#{project_name}&minDate=#{min_date_param}&maxResults=#{max_items}"
      #Log it before we tack on auth info
      logger.debug("Requesting feed URL: #{activity_stream_url}")
      activity_stream_url += auth_string
      args = {:method => :get, :url => activity_stream_url, :user => @jira_username, :password => @jira_password}
      raw_feed = RestClient::Request.execute(args)
      @current_content = raw_feed
      from_rss_xml(raw_feed, project_name)
    end

    private

    def from_rss_xml(raw_xml, project_name)
      xml = Nokogiri::XML(raw_xml)
      #We're relying on the fact that the Jira feed is well-formed and uses
      #a namespace; this won't work for a non-namespaced Atom feed (i.e. lacking the xmlns declaration in the root element)
      entries = xml.xpath('/xmlns:feed/xmlns:entry')

      ai_list = []

      if entries.size > 0
        entries.each do |atom_item|
          @current_content = atom_item
          ai = split_item_atom(atom_item)
          ai.tags << project_name
          ai_list << ai
        end
      else
        logger.info("No <entry> elements found in the feed; This is expected if nothing new has happened since #{@jira_high_water_mark}")
      end

      @current_content = raw_xml

      return ai_list
    end

    def split_item_atom(item)
      description =  item.at_xpath('xmlns:title').inner_text
      html = Nokogiri::HTML(description)

      ai = ActivityItem.new
      ai.activity_type = 'task'
      ai.author = (item.at_xpath('xmlns:author/xmlns:name') || item.at_xpath('xmlns:author/xmlns:email') || item.at_xpath('xmlns:author/usr:username')).inner_text rescue nil
      ai.date = Time.parse((item.at_xpath('xmlns:updated') || item.at_xpath('xmlns:published') || item.at_xpath('dc:date')).inner_text)
      ai.text = html.inner_text.strip
      ai.guid = item.at_xpath('xmlns:id').inner_text

      ai.duration = Jira.parse_duration(ai.text, item.at_xpath('xmlns:content'))

      item_html_url = item.at_xpath('xmlns:link[@rel = "alternate"]')['href']
      base_url, item_id_fragment = item_html_url.split('browse/')

      if item_id_fragment.nil?
        ai.activity_type = ActivityItem::ACTIVITY_TYPE::DOCUMENT if item_html_url.include?('changelog/')
        return ai
      end

      item_id, garbage_afterward = item_id_fragment.split('?')
      item_xml_url = base_url + "si/jira.issueviews:issue-xml/#{item_id}/#{item_id}.xml?#{auth_string}"
      args = {:method => :get, :url => item_xml_url, :user => @jira_username, :password => @jira_password}
      logger.debug "Going off to #{item_xml_url.split('?').first}?[omitted] to get more info on this jira item."

      begin
        item_xml = RestClient::Request.execute(args)
      rescue RestClient::ResourceNotFound
        return ai
      end

      xml = Nokogiri::XML(item_xml).at_xpath('/rss/channel/item')
      ai.tags ||= []
      type = xml.at_xpath('type')
      if !type.nil?
        ai.tags << "type:#{type.inner_text}"
      end

      parent = xml.at_xpath('parent')
      if !parent.nil?
        value = parent.inner_text
        ai.tags << "parent:#{value}" unless value.empty?
      end

      xml.xpath('customfields/customfield').each do |field|
        name = field.at_xpath('customfieldname').inner_text
        values = field.xpath('customfieldvalues/customfieldvalue')

        next if values.size == 0 || name == "Rank"
        values.each do |value|
          value_text = value.inner_text
          next if value_text.empty?
          ai.tags << "#{name}:#{value_text}"
        end
      end

      return ai
    end

    def auth_string
      return "" if @jira_username.nil? || @jira_username.empty?
      "&os_password=#{@jira_password}&os_username=#{@jira_username}&os_authType=basic"
    end

    # Expression to get the number associated with the given units
    def self.duration_per_unit_regex(unit)
      # Some number possibly followed by a space followed by the unit
      # NOTE: it doesn't appear that Jira allows you to enter negative numbers but being defensive
      #       here incase some plugin might allow it - its important we "see" "-" if its there.
      /([\d.-])+(\s?)#{unit}/i
    end

    # Note: made this a class method just for the convenience of unit testing it
    def self.parse_duration(description, content=nil)
      # Assuming logged hours is in description OR content.  If in both we'll take it from the description
      # Also assuming it appears no more than once in content.  We just take the first instance.

      # When time is logged the text looks something like:
      #   Logged '4 hours, 2 minutes'
      #   logged '3d, 4.5h'
      #   Logged '1.5 weeks'
      time_logged_regex = /logged\s'([\w\s,.-]+)'/i

      duration_match = description.match(time_logged_regex)
      duration_match = content.inner_text.match(time_logged_regex) unless duration_match || content.nil?

      total_hours = 0
      if duration_match
        if hours_match = duration_match[0].match(duration_per_unit_regex('h'))
          total_hours += hours_match[0].to_f
        end
        if minutes_match = duration_match[0].match(duration_per_unit_regex('m'))
          mins = minutes_match[0].to_f
          total_hours += mins / 60
        end
        if days_match = duration_match[0].match(duration_per_unit_regex('d'))
          days = days_match[0].to_f
          # assuming 8h days for now
          total_hours += days * 8
        end
        if weeks_match = duration_match[0].match(duration_per_unit_regex('w'))
          weeks = weeks_match[0].to_f
          # assuming 8h days, 5 day weeks for now
          total_hours += weeks * 8 * 5
        end

      end

      return total_hours == 0 ? nil : ((total_hours * 100).round).to_f/100

    end

  end
end
