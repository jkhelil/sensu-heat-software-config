#!/usr/bin/env ruby

require 'rubygems'
require 'json'
require 'sensu-handler'

class HandlerFile < Sensu::Handler

def handle
# Write the event data to a file
file_name = "/tmp/sensu_#{@event['client']['name']}_#{@event['check']['name']}"
File.open(file_name, 'w') do |file|
  file.write(JSON.pretty_generate(@event))
end
end
end
