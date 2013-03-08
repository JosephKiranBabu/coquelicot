# -*- coding: UTF-8 -*-
# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2010-2012 potager.org <jardiniers@potager.org>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

module Coquelicot
  class JyrapheMigrator
    class << self
      def run!(args)
        parser.parse!(args)
        usage_and_exit if args.empty?

        jyraphe_var = args.shift

        migrator = nil
        begin
          migrator = JyrapheMigrator.new(jyraphe_var)
        rescue ArgumentError
          usage_and_exit "#{jyraphe_var} is not a Jyraphe 'var' directory"
        end

        migrator.migrate!

        $stdout.puts migrator.apache_rewrites(options[:rewrite_prefix])
      end
    private
      def usage_and_exit(message = nil)
        unless message.nil?
          $stderr.puts message
          $stderr.puts
        end
        $stderr.puts parser.banner
        $stderr.puts "Run #{$0} --help for more details."
        exit 1
      end

      def options
        @options ||= {}
      end

      def parser
        @parser ||= OptionParser.new do |opts|
          opts.banner = "Usage: #{opts.program_name} [options] migrate-jyraphe [command options] JYRAPHE_VAR > REWRITE_RULES"

          opts.separator ""
          opts.separator "Command options:"

          opts.on "-p", "--rewrite-prefix PREFIX", "prefix URL in rewrite rules" do |prefix|
            options[:rewrite_prefix] = prefix
          end
          opts.on_tail("-h", "--help", "show this message") do
            $stderr.puts opts.to_s
            exit
          end
        end
      end
    end

    attr_reader :files_path, :links_path, :migrated

    def initialize(jyraphe_var, output = $stderr)
      @files_path = File.expand_path('files', jyraphe_var)
      @links_path = File.expand_path('links', jyraphe_var)
      unless File.directory?(@files_path) && File.directory?(@links_path)
        raise ArgumentError.new("#{jyraphe_var} is not a Jyraphe 'var' directory.")
      end
      @output = output
    end

    def warn(str)
      @output.puts "W: #{str}"
    end

    def info(str)
      @output.puts "I: #{str}"
    end

    def migrate!
      max_expire_at = (Time.now + Coquelicot.settings.maximum_expire * 60).to_i
      migrated = {}
      get_links.each do |link|
        begin
          file = JyrapheFile.new(self, link)
        rescue Errno::ENOENT
          warn "#{link} refers to a non-existent file. Skipping."
          next
        rescue SizeMismatch
          warn "#{link} refers to a file with mismatching size. Skipping."
          next
        end

        pass = file.file_key || Coquelicot.gen_random_pass

        if file.expire_at == -1 || file.expire_at > max_expire_at
          expire_at = max_expire_at
          warn "#{link} expiration time has been reduced."
          info "#{link} will expire on #{Time.at(max_expire_at).strftime '%c'}."
        elsif file.expire_at == 0
          warn "#{link} has an unparseable expiration time. Skipping."
          next
        else
          expire_at = file.expire_at
        end

        options = { 'Expire-at'     => expire_at,
                    'One-time-only' => file.one_time_only,
                    'Filename'      => file.filename,
                    'Length'        => file.length,
                    'Content-type'  => file.mime_type }

        coquelicot_name = file.open do |f|
          Coquelicot.depot.add_file(pass, options) do
            f.eof ? nil : f.read
          end
        end

        coquelicot_link = coquelicot_name
        coquelicot_link << "-#{pass}" unless file.file_key
        migrated[link] = coquelicot_link
      end
      @migrated = migrated
    end

   def apache_rewrites(prefix = '')
     return '' if @migrated.empty?

     rewrites = []
     rewrites << 'RewriteEngine on'
     migrated.each_pair do |jyraphe, coquelicot|
       rewrites << "RewriteRule ^#{prefix}file-#{jyraphe}$ #{prefix}#{coquelicot} [L,R=301]"
     end
     rewrites.join "\n"
   end

   private

    def get_links
      Dir.entries(@links_path).select { |n| n =~ /^[RO][0-9a-z]{32}$/ }
    end

    class SizeMismatch < StandardError; end

    class JyrapheFile
      attr_reader :filename, :one_time_only, :mime_type, :length, :file_key, :expire_at

      def initialize(migrator, link)
        @migrator = migrator

        @one_time_only = link[0] == ?O
        File.open(File.expand_path(link, migrator.links_path)) do |f|
          @filename = f.readline.strip
          @mime_type = f.readline.strip
          @length = f.readline.strip.to_i
          if File.stat(file_path).size != length
            raise SizeMismatch.new("#{filename} size does not match what is in #{link}.")
          end
          key = f.readline.strip
          @file_key = key.empty? ? nil : key
          @expire_at = f.readline.strip.to_i
        end
      end

      def file_path
        File.expand_path(filename, @migrator.files_path)
      end

      def open(*args, &block)
        File.open(file_path, *args, &block)
      end
    end
  end
end
