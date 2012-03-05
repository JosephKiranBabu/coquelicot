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

    def self.create(dest, pass, meta)
      salt = gen_salt
      clear_meta = { "Coquelicot" => COQUELICOT_VERSION,
                     "Salt" => Base64.encode64(salt).strip,
                     "Expire-at" => meta.delete('Expire-at'),
                   }
      File.open(dest, File::WRONLY|File::EXCL|File::CREAT) do |dest|
        dest.write(YAML.dump(clear_meta) + YAML_START)

        cipher = get_cipher(pass, salt, :encrypt)
        dest.write(cipher.update(
            YAML.dump(meta.merge("Created-at" => Time.now.to_i)) +
            YAML_START))
        while not (buf = yield).nil?
          dest.write(cipher.update(buf))
        end
        dest.write(cipher.final)
      end
    end

    def empty!
      # zero the content before truncating
      File.open(@path, 'r+') do |f|
        f.seek 0, IO::SEEK_END
        length = f.tell
        f.rewind
        while length > 0 do
          write_len = [StoredFile::BUFFER_LEN, length].min
          length -= f.write("\0" * write_len)
        end
        f.fsync
      end
      File.truncate(@path, 0)
    end

    def lockfile
      @lockfile ||= Lockfile.new "#{File.expand_path(@path)}.lock", :timeout => 4
    end

    # used by Rack streaming mechanism
    def each
      # output content
      yield @initial_content
      @initial_content = nil
      until (buf = @file.read(BUFFER_LEN)).nil?
        yield @cipher.update(buf)
      end
      yield @cipher.final
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
    CIPHER = 'AES-256-CBC'
    SALT_LEN = 8
    COQUELICOT_VERSION = '1.0'

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

      if YAML_START != (buf = @file.read(YAML_START.length)) then
        raise "unknown file, read #{buf.inspect}"
      end
      parse_clear_meta
      return if pass.nil?

      init_decrypt_cipher pass

      yaml = find_meta
      @meta.merge! YAML.load(yaml)
    end

    def parse_clear_meta
      meta = ''
      until YAML_START == (line = @file.readline) do
        meta += line
      end
      @meta = YAML.load(meta)
      unless @meta["Coquelicot"] == COQUELICOT_VERSION
        raise 'unknown file'
      end
      @expire_at = Time.at(@meta['Expire-at'])
    end

    def init_decrypt_cipher(pass)
      salt = Base64.decode64(@meta["Salt"])
      @cipher = StoredFile::get_cipher(pass, salt, :decrypt)
    end

    def find_meta
      yaml = ''
      buf = @file.read(BUFFER_LEN)
      content = @cipher.update(buf)
      content << @cipher.final if @file.eof?
      raise BadKey.new unless content.start_with? YAML_START
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
