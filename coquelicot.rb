require 'sinatra'
require 'haml'
require 'digest/sha1'
require 'base64'
require 'openssl'
require 'yaml'
require 'lockfile'

enable :inline_templates

set :upload_password, '0e5f7d398e6f9cd1f6bac5cc823e363aec636495'
set :filename_length, 20
set :lockfile, Proc.new { Lockfile.new "#{depot_path}/.lock", 
                                       :timeout => 60,
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

# Like RFC 4648 (Base32)
FILENAME_CHARS = %w(a b c d e f g h i j k l m n o p q r s t u v w x y z 2 3 4 5 6 7)
def gen_random_file_name
  name = nil
  options.lockfile.lock do
    begin
      name = ''
      OpenSSL::Random::random_bytes(options.filename_length).each_byte do |i|
        name << FILENAME_CHARS[i % FILENAME_CHARS.length]
      end
    end while name.empty? or File.exists?(uploaded_file(name))
  end
  name
end

def password_match?(password)
  return TRUE if settings.upload_password.nil?
  (not password.nil?) && Digest::SHA1.hexdigest(password) == settings.upload_password
end

def uploaded_file(file)
  "#{options.depot_path}/#{file}"
end

get '/style.css' do
  content_type 'text/css', :charset => 'utf-8'
  sass :style
end

get '/' do
  haml :index
end

get '/ready/:name' do |name|
  path = uploaded_file(name)
  unless File.exists? path then
    not_found
  end
  base = request.url.gsub(/\/ready\/[^\/]*$/, '')
  @url = "#{base}/#{name}"
  haml :ready
end

get '/:name' do |name|
  path = uploaded_file(name)
  unless File.exists? path then
    not_found
  end
  file = StoredFile.open(path, 'XXXsecret')
  last_modified File.mtime(path).httpdate
  attachment file.meta['Filename']
  response['Content-Length'] = "#{file.meta['Length']}"
  response['Content-Type'] = file.meta['Content-Type'] || 'application/octet-stream'
  throw :halt, [200, file]
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
  src = params[:file][:tempfile]
  dst = gen_random_file_name
  File.open(uploaded_file(dst), 'w') do |dest|
    StoredFile.create(
     src,
     'XXXsecret',
     { "Filename" => params[:file][:filename],
       "Length" => src.stat.size,
       "Content-Type" => params[:file][:type]
     }) { |data| dest.write data }
  end
  redirect "ready/#{dst}"
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
