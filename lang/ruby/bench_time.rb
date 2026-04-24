#!/usr/bin/env ruby
$LOAD_PATH.unshift File.join(__dir__, 'cxlib', 'lib')
require 'cxlib'

medium = File.read(File.join(__dir__, '..', '..', 'fixtures', 'bench', 'bench_medium.cx'))

def time_median(n, warmup, &block)
  warmup.times { block.call }
  times = Array.new(n) do
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    block.call
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000
  end
  times.sort[n / 2]
end

parse_med  = time_median(100, 20) { CXLib.parse(medium) }
stream_med = time_median(100, 20) { CXLib.stream(medium) }
puts "parse=#{parse_med.round(3)} stream=#{stream_med.round(3)}"
