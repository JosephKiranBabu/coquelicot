require 'sinatra'
require 'haml'
require 'digest/sha1'
require 'base64'
require 'openssl'
require 'yaml'
require 'lockfile'
require 'singleton'

enable :inline_templates

set :upload_password, '0e5f7d398e6f9cd1f6bac5cc823e363aec636495'
set :filename_length, 20
set :random_pass_length, 16
set :lockfile_options, { :timeout => 60,
                         :max_age => 8,
                         :refresh => 2,
                         :debug   => false }

class StoredFile
  attr_reader :meta

  def self.open(path, pass)
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
                   "Salt" => Base64.encode64(salt).strip }
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
  BUFFER_LEN = 4096
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
  end

  def init_decrypt_cipher(pass)
    salt = Base64.decode64(@meta["Salt"])
    @cipher = StoredFile::get_cipher(pass, salt, :decrypt)
  end

  def parse_meta
    yaml = ''
    buf = @file.read(BUFFER_LEN)
    content = @cipher.update(buf)
    raise "bad key" unless content.start_with? YAML_START
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

  def remove_link(src)
    lockfile.lock do
      links = []
      File.open(links_path, 'r+') do |f|
        f.readlines.each do |l|
          links << l unless l.start_with? "#{src} "
        end
        f.rewind
        f.truncate(0)
        f.write links.join
      end
    end
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

get '/ready/:link' do |link|
  link, pass = link.split '-' if link.include? '-'
  unless depot.file_exists? link then
    not_found
  end
  base = request.url.gsub(/\/ready\/[^\/]*$/, '')
  @url = "#{base}/#{link}-#{pass}" unless pass.nil?
  @url ||= "#{base}/#{link}"
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
  if params[:file_key].nil? or params[:file_key].empty?then
    pass = gen_random_pass
  else
    pass = params[:file_key]
  end
  src = params[:file][:tempfile]
  link = depot.add_file(
     src, pass,
     { "Filename" => params[:file][:filename],
       "Length" => src.stat.size,
       "Content-Type" => params[:file][:type]
     })
  redirect "ready/#{link}-#{pass}" if params[:file_key].nil? or params[:file_key].empty?
  redirect "ready/#{link}"
end

def send_stored_file(link, pass)
  file = depot.get_file(link, pass)
  return false if file.nil?

  last_modified file.mtime.httpdate
  attachment file.meta['Filename']
  response['Content-Length'] = "#{file.meta['Length']}"
  response['Content-Type'] = file.meta['Content-Type'] || 'application/octet-stream'
  throw :halt, [200, file]
end

get '/:link' do |link|
  if link.include? '-'
    link, pass = link.split '-'
    not_found unless send_stored_file(link, pass)
  end
  not_found unless depot.file_exists? link
  @link = link
  haml :enter_file_key
end

post '/:link' do |link|
  pass = params[:file_key]
  return 403 if pass.nil? or pass.empty?
  return 403 unless send_stored_file(link, pass)
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

__END__

@@ layout
%html
  %head
    %title coquelicot
    %base{ :href => base_href }
    %link{ :rel => 'stylesheet', :href => "style.css", :type => 'text/css',
           :media => "screen, projection" }
    %script{ :type => 'text/javascript', :src => 'javascripts/jquery.min.js' }
    %script{ :type => 'text/javascript', :src => 'javascripts/jquery.lightBoxFu.js' }
    %script{ :type => 'text/javascript', :src => 'javascripts/jquery.uploadProgress.js' }
    %script{ :type => 'text/javascript', :src => 'javascripts/coquelicot.js' }
  %body
    #container
      = yield

@@ index
%h1 Upload!
- unless @error.nil?
  .error= @error
%form#upload{ :enctype => 'multipart/form-data',
              :action  => 'upload', :method => 'post' }
  .field
    %input{ :type => 'file', :name => 'file' }
  .field
    %input{ :type => 'submit', :value => 'Send file' }

@@ ready
%h1 Pass this on!
.url
  %a{ :href => @url }= @url

@@ enter_file_key
%h1 Enter file key…
%form{ :action => @link, :method => 'post' }
  .field
    %input{ :type => 'text', :id => 'file_key', :name => 'file_key' }
  .field
    %input{ :type => 'submit', :value => 'Get file' }

@@ style
$green: #00ff26

body
  background-color: $green
  font-family: Georgia
  color: darkgreen

a, a:visited
  text-decoration: underline
  color: white

.error
  background-color: red
  color: white
  border: black solid 1px

#progress
  margin: 8px
  width: 220px
  height: 19px

#progressbar
  background: url('images/ajax-loader.gif') no-repeat
  width: 0px
  height: 19px
