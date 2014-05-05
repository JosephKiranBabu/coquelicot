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

require 'base64'
require 'lockfile'
require 'openssl'
require 'yaml'

module Coquelicot
  class BadKey < StandardError; end

  class StoredFile
    BUFFER_LEN = 4096

    attr_reader :path, :meta, :expire_at

    def self.open(path, pass = nil)
      StoredFile.new(path, pass)
    end

    def created_at
      Time.at(@meta['Created-at'])
    end

    def expired?
      @expire_at < Time.now
    end

    def one_time_only?
      @meta['One-time-only']
    end

    def self.create(path, pass, meta)
      salt = gen_salt
      clear_meta = { "Coquelicot" => COQUELICOT_VERSION,
                     "Salt" => Base64.encode64(salt).strip,
                     "Expire-at" => meta.delete('Expire-at'),
                   }
      cipher = get_cipher(pass, salt, :encrypt)
      length = 0
      File.open("#{path}.content", File::WRONLY|File::EXCL|File::CREAT) do |dest|
        until (buf = yield).nil?
          length += buf.bytesize
          dest.write(cipher.update(buf))
        end
        dest.write(cipher.final)
      end
      cipher.reset
      File.open(path, File::WRONLY|File::EXCL|File::CREAT) do |dest|
        dest.write(YAML.dump(clear_meta) + YAML_START)
        dest.write(cipher.update(
            YAML.dump(meta.merge('Created-at' => Time.now.to_i,
                                 'Length' => length))))
        dest.write(cipher.final)
      end
    rescue Errno::EEXIST
      # do not remove the file if it already existed before!
      raise
    rescue
      FileUtils.rm path, :force => true
      FileUtils.rm "#{path}.content", :force => true
      raise
    end

    def empty!
      # XXX: probably this should be locked
      paths = [@path]
      paths.unshift "#{@path}.content" unless @features.include? :meta_include_content
      paths.each do |path|
        # zero the content before truncating
        File.open(path, 'r+') do |f|
          f.seek 0, IO::SEEK_END
          length = f.tell
          f.rewind
          while length > 0 do
            write_len = [StoredFile::BUFFER_LEN, length].min
            length -= f.write("\0" * write_len)
          end
          f.fsync
        end
        File.truncate(path, 0)
      end
    end

    def lockfile
      @lockfile ||= Lockfile.new "#{File.expand_path(@path)}.lock", :timeout => 4
    end

    # used by Rack streaming mechanism
    def each
      raise BadKey.new if @cipher.nil?

      # output content
      if @features.include? :meta_include_content
        yield @initial_content
        @initial_content = nil
        file = @file
      else
        file = File.open("#{path}.content")
        @cipher.reset
      end
      unless file.eof?
        until (buf = file.read(BUFFER_LEN)).nil?
          yield @cipher.update(buf)
        end
        yield @cipher.final
      end
      @fully_sent = true
    end

    def close
      if @cipher
        @cipher.reset
        @cipher = nil
      end
      @file.close
      if one_time_only?
        empty! if @fully_sent
        lockfile.unlock
      end
    end

  private

    YAML_START = "--- \n"
    YAML_START_RE = /^---( |\n)/
    CIPHER = 'AES-256-CBC'
    SALT_LEN = 8
    COQUELICOT_VERSION = '2.0'
    COQUELICOT_FEATURES = {               '1.0' => [:meta_include_content],
                             COQUELICOT_VERSION => [:current]
                          }

    def self.get_cipher(pass, salt, method)
      cipher = OpenSSL::Cipher.new CIPHER
      hmac = OpenSSL::PKCS5.pbkdf2_hmac_sha1(
          pass, salt, 2000, cipher.key_len + cipher.iv_len)
      cipher.method(method).call
      cipher.key = hmac.slice!(0, cipher.key_len)
      cipher.iv = hmac
      cipher
    end

    def self.gen_salt
      OpenSSL::Random::random_bytes(SALT_LEN)
    end

    def initialize(path, pass)
      @path = path
      @file = File.open(@path)
      if @file.lstat.size == 0 then
        @expire_at = Time.now - 1
        return
      end

      unless YAML_START_RE =~ (buf = @file.readline)
        raise ArgumentError.new("unknown file, read #{buf.inspect}")
      end
      parse_clear_meta
      return if pass.nil?

      init_decrypt_cipher pass

      yaml = find_meta
      @meta.merge! YAML.load(yaml)
    end

    def parse_clear_meta
      meta = ''
      until YAML_START_RE =~ (line = @file.readline) do
        meta += line
      end
      @meta = YAML.load(meta)
      @features = COQUELICOT_FEATURES[@meta['Coquelicot']]
      unless @features
        raise ArgumentError.new('unknown file')
      end
      if @meta['Expire-at'].respond_to? :to_time
        @expire_at = @meta['Expire-at'].to_time
      else
        @expire_at = Time.at(@meta['Expire-at'])
      end
    end

    def init_decrypt_cipher(pass)
      salt = Base64.decode64(@meta["Salt"])
      @cipher = StoredFile::get_cipher(pass, salt, :decrypt)
    end

    def find_meta
      return find_meta_in_meta_and_content if @features.include? :meta_include_content

      begin
        content = @cipher.update(@file.read)
        content << @cipher.final
        raise BadKey.new unless content =~ YAML_START_RE
        content
      rescue OpenSSL::Cipher::CipherError
        raise BadKey.new
      end
    end

    def find_meta_in_meta_and_content
      yaml = ''
      buf = @file.read(BUFFER_LEN)
      begin
        content = @cipher.update(buf)
        content << @cipher.final if @file.eof?
        raise BadKey.new unless content =~ YAML_START_RE
      rescue OpenSSL::Cipher::CipherError
        raise BadKey.new
      end
      yaml << YAML_START
      block = content.split(YAML_START, 3)
      yaml << block[1]
      if block.length == 3 then
        @initial_content = block[2]
        return yaml
      end

      until (buf = @file.read(BUFFER_LEN)).nil? do
        content = @cipher.update(buf)
        block = content.split(YAML_START, 3)
        yaml << block[0]
        break if block.length == 2
      end
      @initial_content = block[1]
      yaml
    end
  end
end
