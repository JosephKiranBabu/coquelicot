#!/usr/bin/env ruby1.8

$:.unshift File.join(File.dirname(__FILE__), '../lib')

require 'coquelicot'

module Coquelicot
  class Options
    def random_pass_length
      16
    end
  end
  class << self
    def options
      Options.new
    end
  end
end

class JyrapheMigrator
  def initialize(jyraphe_var)
    @var = jyraphe_var
    @redirects = {}
  end

  def process
    process_links
    puts "RewriteEngine on"
    @redirects.each_pair do |jyraphe, coquelicot|
      puts "RewriteRule ^file-#{jyraphe}$ #{coquelicot} [L,R=301]"
    end
  end

  def process_links
    Dir.glob("#{@var}/links/*").each do |link_path|
      link_name = File.basename(link_path)
      one_time_only = link_name.slice(0, 1) == 'O'
      File.open(link_path) do |link_file|
        filename = link_file.readline.strip
        mime_type = link_file.readline.strip
        length = link_file.readline.strip.to_i
        next if length > 10 * 1024 * 1024
        file_key = link_file.readline.strip
        if file_key.empty? then
          random_pass = Coquelicot::gen_random_pass
        end
        expire_at = link_file.readline.strip.to_i
        expire_at = (Time.now + 60 * 24 * 30).to_i if expire_at <= 0 #XXX: replace with config
        begin
          coquelicot_link = File.open("#{@var}/files/#{filename}") do |src|
            Coquelicot::depot.add_file(
              src, file_key || random_pass,
              { "Expire-at" => expire_at,
                "One-time-only" => one_time_only,
                "Filename" => filename,
                "Length" => length,
                "Content-Type" => mime_type
              })
          end
          @redirects[link_name] = "#{coquelicot_link}"
          @redirects[link_name] << "-#{random_pass}" if file_key.empty?
        rescue Errno::ENOENT => ex
          STDERR.puts "#{ex}"
        end
      end
    end
  end
end

def usage
  STDERR.puts "Usage: #{$0} </path/to/jyraphe/var> </path/to/coquelicot/depot>"
  exit 1
end

def main
  usage unless ARGV.length == 2
  jyraphe_var = ARGV[0]
  coquelicot_depot = ARGV[1]

  unless File.directory? "#{jyraphe_var}/files" and
         File.directory? "#{jyraphe_var}/links" then
    STDERR.puts "#{jyraphe_var} is not a Jyraphe 'var' directory."
    exit 1
  end
  unless File.exists? "#{coquelicot_depot}/.links" then
    STDERR.puts "#{coquelicot_depot} is not a Coquelicot depot."
    exit 1
  end

  Coquelicot.setup :depot_path => coquelicot_depot
  JyrapheMigrator.new(jyraphe_var).process
end

main
