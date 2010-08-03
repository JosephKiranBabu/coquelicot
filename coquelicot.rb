require 'sinatra'
require 'haml'
require 'digest/sha1'
require 'base64'
require 'openssl'
require 'yaml'
require 'lockfile'
require 'singleton'

set :upload_password, '0e5f7d398e6f9cd1f6bac5cc823e363aec636495'
set :default_expire, 60 # 1 hour
set :filename_length, 20
set :random_pass_length, 16
set :lockfile_options, { :timeout => 60,
                         :max_age => 8,
                         :refresh => 2,
                         :debug   => false }

class BadKey < StandardError; end

class StoredFile
  BUFFER_LEN = 4096

  attr_reader :meta, :expire_at

  def self.open(path, pass = nil)
    StoredFile.new(path, pass)
  end

  def each
    # output content
    yield @initial_content
    @initial_content = nil
    until (buf = @file.read(BUFFER_LEN)).nil?
      yield @cipher.update(buf)
    end
    yield @cipher.final
    @cipher.reset
    @cipher = nil
  end

  def mtime
    @file.mtime
  end

  def self.create(src, pass, meta)
    salt = gen_salt
    clear_meta = { "Coquelicot" => COQUELICOT_VERSION,
                   "Salt" => Base64.encode64(salt).strip,
                   "Expire-at" => meta.delete('Expire-at') }
    yield YAML.dump(clear_meta) + YAML_START

    cipher = get_cipher(pass, salt, :encrypt)
    yield cipher.update(YAML.dump(meta) + YAML_START)
    src.rewind
    while not (buf = src.read(BUFFER_LEN)).nil?
      yield cipher.update(buf)
    end
    yield cipher.final
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
    @file = File.open(path)
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

  def close
    @cipher.reset unless @cipher.nil?
    @file.close
  end
end

class Depot
  include Singleton

  attr_accessor :path, :lockfile_options, :filename_length

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

  def get_file(link, pass)
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
      remove_file(name) if Time.now > StoredFile::open(full_path(name)).expire_at
    end
  end

private

  def lockfile
    Lockfile.new "#{@path}/.lock", @lockfile_options
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
          line = f.readline
          if line.start_with? "#{src} " then
            dst = line.split[1]
            break
          end
        end until line.empty?
      end
    end
    dst
  end

  def remove_file(name)
    # zero the content before unlinking
    File.open(full_path(name), 'r+') do |f|
      f.seek 0, IO::SEEK_END
      length = f.tell
      f.rewind
      while length > 0 do
        write_len = [StoredFile::BUFFER_LEN, length].min
        length -= f.write("\0" * write_len)
      end
    end
    File.unlink full_path(name)
    remove_from_links { |l| l.end_with? " #{name}" }
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
      name = gen_random_base32(@filename_length)
    end while File.exists?(full_path(name))
    name
  end

  def full_path(name)
    raise "Wrong name" unless name.each_char.collect { |c| FILENAME_CHARS.include? c }.all?
    "#{@path}/#{name}"
  end
end
def depot
  @depot unless @depot.nil?

  @depot = Depot.instance
  @depot.path = options.depot_path if @depot.path.nil?
  @depot.lockfile_options = options.lockfile_options if @depot.lockfile_options.nil?
  @depot.filename_length = options.filename_length if @depot.filename_length.nil?
  @depot
end

# Like RFC 4648 (Base32)
FILENAME_CHARS = %w(a b c d e f g h i j k l m n o p q r s t u v w x y z 2 3 4 5 6 7)
def gen_random_base32(length)
  name = ''
  OpenSSL::Random::random_bytes(length).each_byte do |i|
    name << FILENAME_CHARS[i % FILENAME_CHARS.length]
  end
  name
end
def gen_random_pass
  gen_random_base32(options.random_pass_length)
end
def remap_base32_extra_characters(str)
  map = {}
  FILENAME_CHARS.each { |c| map[c] = c; map[c.upcase] = c }
  map.merge!({ '1' => 'l', '0' => 'o' })
  result = ''
  str.each_char { |c| result << map[c] }
  result
end

def password_match?(password)
  return TRUE if settings.upload_password.nil?
  (not password.nil?) && Digest::SHA1.hexdigest(password) == settings.upload_password
end

get '/style.css' do
  content_type 'text/css', :charset => 'utf-8'
  sass :style
end

get '/' do
  haml :index
end

get '/random_pass' do
  "#{gen_random_pass}"
end

get '/ready/:link' do |link|
  link, pass = link.split '-' if link.include? '-'
  begin
    file = depot.get_file(link, nil)
  rescue Errno::ENOENT => ex
    not_found
  end
  @expire_at = file.expire_at
  @base = request.url.gsub(/\/ready\/[^\/]*$/, '')
  @name = "#{link}"
  unless pass.nil?
    @name << "-#{pass}"
    @unprotected = true
  end 
  @url = "#{@base}/#{@name}"
  haml :ready
end

post '/upload' do
  unless password_match? params[:upload_password] then
    error 403
  end
  if params[:file] then
    tmpfile = params[:file][:tempfile]
    name = params[:file][:filename]
  end
  if tmpfile.nil? || name.nil? then
    @error = "No file selected"
    return haml(:index)
  end
  if params[:expire].nil? or params[:expire].to_i == 0 then
    params[:expire] = options.default_expire
  end
  expire_at = Time.now + 60 * params[:expire].to_i
  if params[:file_key].nil? or params[:file_key].empty?then
    pass = gen_random_pass
  else
    pass = params[:file_key]
  end
  src = params[:file][:tempfile]
  link = depot.add_file(
     src, pass,
     { "Expire-at" => expire_at.to_i,
       "Filename" => params[:file][:filename],
       "Length" => src.stat.size,
       "Content-Type" => params[:file][:type]
     })
  redirect "ready/#{link}-#{pass}" if params[:file_key].nil? or params[:file_key].empty?
  redirect "ready/#{link}"
end

def expired
  throw :halt, [410, haml(:expired)]
end

def send_stored_file(link, pass)
  file = depot.get_file(link, pass)
  return false if file.nil?
  return expired if Time.now > file.expire_at

  last_modified file.mtime.httpdate
  attachment file.meta['Filename']
  response['Content-Length'] = "#{file.meta['Length']}"
  response['Content-Type'] = file.meta['Content-Type'] || 'application/octet-stream'
  throw :halt, [200, file]
end

get '/:link-:pass' do |link, pass|
  link = remap_base32_extra_characters(link)
  pass = remap_base32_extra_characters(pass)
  not_found unless send_stored_file(link, pass)
end

get '/:link' do |link|
  link = remap_base32_extra_characters(link)
  not_found unless depot.file_exists? link
  @link = link
  haml :enter_file_key
end

post '/:link' do |link|
  pass = params[:file_key]
  return 403 if pass.nil? or pass.empty?
  begin
    return 403 unless send_stored_file(link, pass)
  rescue BadKey => ex
    403
  end
end

helpers do
  def base_href
    url = request.scheme + "://"
    url << request.host
    if request.scheme == "https" && request.port != 443 ||
        request.scheme == "http" && request.port != 80
      url << ":#{request.port}"
    end
    url << request.script_name
    "#{url}/"
  end
end
