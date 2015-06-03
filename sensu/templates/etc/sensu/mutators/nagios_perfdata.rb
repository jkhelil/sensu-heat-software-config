#!/usr/bin/env ruby
#
# Nagios_perfdata
# ===
#
# DESCRIPTION:
#   Nagios perfadata mutator.
#
# OUTPUT:
#   event 
#
# PLATFORM:
#   all
#
# DEPENDENCIES:
#
#   json Ruby gem
#
# Copyright 2015 - VSCT
# Author : Jawed khelil - 04/02/2015
# 
require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'json'

# parse event
event = JSON.parse(STDIN.read, symbolize_names: true)

client = event[:client]
check  = event[:check]

if check[:output_format] == "nagios_perfdata"
  
  if check[:output].include? "|"
    
    nagios_data = check[:output].split('|').last.strip
    nagios_data.include?("#") ? perfdata = nagios_data.split('#',2).first.strip : perfdata =  nagios_data
    result = []

    perfdata.split(/;/).each do |data|
      label, value = data.split('=')
      name = label.strip.gsub(/\W/, '_')
      measure = value.match(/[0-9]*\.[0-9]+|[0-9]+/i)[0] unless value.match(/[0-9]*\.[0-9]+|[0-9]+/i) == nil
      metric_path = ['sensu', client[:name], check[:name], name].join('.')
      result << [metric_path, measure, check[:executed]].join(" ") unless measure.to_s.empty?
    end

    event[:check][:output] = result.join("\n") + "\n"

  end

  puts event[:check][:output]
  
end