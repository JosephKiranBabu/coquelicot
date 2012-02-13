require 'base64'
require 'lockfile'
require 'openssl'
require 'yaml'

require 'coquelicot/auth'
require 'coquelicot/stored_file'
require 'coquelicot/configure'
require 'coquelicot/app'

module Coquelicot
  class Depot
    attr_reader :path

    def initialize(path)
      @path = path
    end

    def add_file(src, pass, options)
      dst = nil
      lockfile.lock do
        dst = gen_random_file_name
        File.open(full_path(dst), 'w').close
      end
      begin
        File.open(full_path(dst), 'w') do |dest|
          StoredFile.create(src, pass, options) { |data| dest.write data }
        end
      rescue
        File.unlink full_path(dst)
        raise
      end
      link = gen_random_file_name
      add_link(link, dst)
      link
    end

    def get_file(link, pass=nil)
      name = read_link(link)
      return nil if name.nil?
      StoredFile::open(full_path(name), pass)
    end

    def file_exists?(link)
      name = read_link(link)
      return !name.nil?
    end

    def gc!
      files.each do |name|
        path = full_path(name)
        if File.lstat(path).size > 0
          file = StoredFile::open path
          file.empty! if file.expired?
        elsif Time.now - File.lstat(path).mtime > (Coquelicot.settings.gone_period * 60)
          remove_from_links { |l| l.strip.end_with? " #{name}" }
          File.unlink path
        end
      end
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
        File.open(links_path, 'a') do |f|
          f.write("#{src} #{dst}\n")
        end
      end
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
      dst = nil
      lockfile.lock do
        File.open(links_path) do |f|
          begin
            line = f.readline rescue break
            if line.start_with? "#{src} " then
              dst = line.split[1]
              break
            end
          end until line.empty?
        end if File.exists?(links_path)
      end
      dst
    end

    def files
      lockfile.lock do
        File.open(links_path) do |f|
          f.readlines.collect { |l| l.split[1] }
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
