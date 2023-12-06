#!/usr/bin/env ruby

def fibonacci(number)
  if number < 2
    number
  else
    fibonacci(number - 1) + fibonacci(number - 2)
  end
end

if ARGV.length != 1
  puts "Usage: #{__FILE__} <number>"
else
  before = Time.now
  puts "#{File.basename(__FILE__)}: #{fibonacci(ARGV[0].to_i)}"
  puts "Used time: #{Time.now - before}"
end
