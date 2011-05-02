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
      @meta['One-time-only'] && @meta['One-time-only'] == 'true'
    end

    def self.create(src, pass, meta)
      salt = gen_salt
      clear_meta = { "Coquelicot" => COQUELICOT_VERSION,
                     "Salt" => Base64.encode64(salt).strip,
                     "Expire-at" => meta.delete('Expire-at'),
                   }
      yield YAML.dump(clear_meta) + YAML_START

      cipher = get_cipher(pass, salt, :encrypt)
      yield cipher.update(YAML.dump(meta.merge("Created-at" => Time.now.to_i)) +
                          YAML_START)
      src.rewind
      while not (buf = src.read(BUFFER_LEN)).nil?
        yield cipher.update(buf)
      end
      yield cipher.final
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

  private

    YAML_START = "--- \n"
    CIPHER = 'AES-256-CBC'
    SALT_LEN = 8
    COQUELICOT_VERSION = "1.0"

    def self.get_cipher(pass, salt, method)
      hmac = OpenSSL::PKCS5.pbkdf2_hmac_sha1(pass, salt, 2000, 48)
      cipher = OpenSSL::Cipher.new CIPHER
      cipher.method(method).call
      cipher.key = hmac[0..31]
      cipher.iv = hmac[32..-1]
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
      parse_meta
    end

    def parse_clear_meta
      meta = ''
      until YAML_START == (line = @file.readline) do
        meta += line
      end
      @meta = YAML.load(meta)
      if @meta["Coquelicot"].nil? or @meta["Coquelicot"] != COQUELICOT_VERSION then
        raise "unknown file"
      end
      @expire_at = Time.at(@meta['Expire-at'])
    end

    def init_decrypt_cipher(pass)
      salt = Base64.decode64(@meta["Salt"])
      @cipher = StoredFile::get_cipher(pass, salt, :decrypt)
    end

    def parse_meta
      yaml = ''
      buf = @file.read(BUFFER_LEN)
      content = @cipher.update(buf)
      raise BadKey unless content.start_with? YAML_START
      yaml << YAML_START
      block = content.split(YAML_START, 3)
      yaml << block[1]
      if block.length == 3 then
        @initial_content = block[2]
        @meta.merge! YAML.load(yaml)
        return
      end

      until (buf = @file.read(BUFFER_LEN)).nil? do
        block = @cipher.update(buf).split(YAML_START, 3)
        yaml << block[0]
        break if block.length == 2
      end
      @initial_content = block[1]
      @meta.merge! YAML.load(yaml)
    end
  end

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
