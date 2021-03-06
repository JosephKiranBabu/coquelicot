# -*- coding: UTF-8 -*-
# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2010-2013 potager.org <jardiniers@potager.org>
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

require 'lockfile'
require 'openssl'

module Coquelicot
  class Depot
    attr_reader :path

    def initialize(path)
      @path = path
    end

    def add_file(pass, options, &block)
      dst = nil

      # Ensure that the generated name is not already used
      loop do
        dst = gen_random_file_name
        begin
          StoredFile.create(full_path(dst), pass, options, &block)
          break
        rescue Errno::EEXIST => e
          raise unless e.message =~ /(?:^|\s)#{Regexp.escape(full_path(dst))}(?:\s|$)/
          next # let's try again
        end
      end

      # retry to add the link until a free name is generated
      loop do
        link = gen_random_file_name
        return link if add_link(link, dst)
      end
    end

    def get_file(link, pass=nil)
      name = nil
      lockfile.lock do
        name = read_link(link)
      end
      return nil if name.nil?
      begin
        StoredFile::open(full_path(name), pass)
      rescue Errno::ENOENT
        nil
      end
    end

    def file_exists?(link)
      lockfile.lock do
        name = read_link(link)
        return name && File.exists?(full_path(name))
      end
    end

    def gc!
      files.each do |name|
        path = full_path(name)
        unless File.exists?(path)
          remove_from_links { |l| l.strip.end_with? " #{name}" }
          next
        end
        if File.lstat(path).size > 0
          begin
            file = StoredFile::open path
          rescue ArgumentError
            $stderr.puts "W: #{path} is not a Coquelicot file. Skipping."
            next
          end
          file.empty! if file.expired?
        elsif Time.now - File.lstat(path).mtime > (Coquelicot.settings.gone_period * 60)
          remove_from_links { |l| l.strip.end_with? " #{name}" }
          FileUtils.rm "#{path}.content", :force => true
          FileUtils.rm path
        end
      end
    end

    def size
      files.count
    end

  private

    LOCKFILE_OPTIONS = { :timeout => 60,
                         :max_age => 8,
                         :refresh => 2,
                         :debug   => false }

    def lockfile
      Lockfile.new "#{@path}/.lock", LOCKFILE_OPTIONS
    end

    def links_path
      "#{@path}/.links"
    end

    def add_link(src, dst)
      lockfile.lock do
        return false unless read_link(src).nil?

        File.open(links_path, 'a') do |f|
          f.write("#{src} #{dst}\n")
        end
      end
      true
    end

    def remove_from_links(&block)
      lockfile.lock do
        links = []
        File.open(links_path, 'r+') do |f|
          f.readlines.each do |l|
            links << l unless yield l
          end
          f.rewind
          f.truncate(0)
          f.write links.join
        end
      end
    end

    def remove_link(src)
      remove_from_links { |l| l.start_with? "#{src} " }
    end

    def read_link(src)
      File.open(links_path) do |f|
        until f.eof?
          return $1 if f.readline =~ /^#{Regexp.escape(src)}\s+(.+)$/
        end
      end
      nil
    rescue Errno::ENOENT
      nil
    end

    def files
      lockfile.lock do
        begin
          File.open(links_path) do |f|
            f.readlines.collect { |l| l.split[1] }
          end
        rescue Errno::ENOENT # if links file has not been created yet
          []
        end
      end
    end

    def gen_random_file_name
      begin
        name = Coquelicot.gen_random_base32(Coquelicot.settings.filename_length)
      end while File.exists?(full_path(name))
      name
    end

    def full_path(name)
      raise "Wrong name" unless name.each_char.collect { |c| Coquelicot::FILENAME_CHARS.include? c }.all?
      "#{@path}/#{name}"
    end
  end

  # Like RFC 4648 (Base32)
  FILENAME_CHARS = %w(a b c d e f g h i j k l m n o p q r s t u v w x y z 2 3 4 5 6 7)

  class << self
    def gen_random_base32(length)
      name = ''
      OpenSSL::Random::random_bytes(length).each_byte do |i|
        name << FILENAME_CHARS[i % FILENAME_CHARS.length]
      end
      name
    end
    def gen_random_pass
      gen_random_base32(settings.random_pass_length)
    end
    def remap_base32_extra_characters(str)
      map = {}
      FILENAME_CHARS.each { |c| map[c] = c; map[c.upcase] = c }
      map.merge!({ '1' => 'l', '0' => 'o' })
      result = ''
      str.each_char { |c| result << map[c] if map[c] }
      result
    end
  end
end
