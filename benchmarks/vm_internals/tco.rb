#!/usr/bin/env ruby

def tco(number)
  if number == 0
    return
  end
  tco(number - 1)
end

if ARGV.length != 1
  puts "Usage: #{__FILE__} <number>"
else
  before = Time.now
  puts "#{File.basename(__FILE__)}: #{tco(ARGV[0].to_i)}"
  puts "Used time: #{Time.now - before}"
end
