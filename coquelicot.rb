require 'sinatra'
require 'haml'
require 'digest/sha1'
require 'base64'
require 'openssl'
require 'singleton'

enable :inline_templates

set :upload_password, '0e5f7d398e6f9cd1f6bac5cc823e363aec636495'

class StoredFile
  def self.open(path, pass)
    StoredFile.new(path, pass)
  end

  def each
    # output content
    yield @initial_content
    @initial_content = nil
    while "" != (buf = @file.read(BUFFER_LEN))
      yield @cipher.update(buf)
    end
    yield @cipher.final
    @cipher.reset
    @cipher = nil
  end

  def self.create(path, pass, meta, content)
    File.new(path, 'w') do |file|
      salt = gen_salt
      clear_meta = { "Coquelicot" => COQUELICOT_VERSION,
                     "Salt" => Base64.encode64(salt).strip }
      YAML.dump(clear_meta, file)
      file.write YAML_START

      cipher = get_cipher(pass, salt, :encrypt)
      file << cipher.update(YAML.dump(meta) + YAML_START)
      while '' != (buf = content.read(BUFFER_LEN)) do
        file << cipher.update(buf)
      end
      file << cipher.final
    end
  end

private

  YAML_START = "---\n"
  CIPHER = 'AES-256-CBC'
  BUFFER_LEN = 4096
  COQUELICOT_VERSION = "1.0"

  def self.get_cipher(pass, salt, method)
    hmac = PKCS5.pbkdf2_hmac_sha1(pass, salt, 2000, 48)
    cipher = OpenSSL::Cipher.new CIPHER
    cipher.call(method)
    cipher.key = hmac[0..31]
    cipher.iv = hmac[32..-1]
    cipher
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
    while YAML_START != (line = @file.readline) do
      meta += line
    end
    @meta = YAML.load(meta)
    if @meta["Coquelicot"].nil? or @meta["Coquelicot"] != COQUELICOT_VERSION then
      raise "unknown file"
    end
  end

  def init_decrypt_cipher(pass)
    salt = Base64.decode(@meta["Salt"])
    @cipher = get_cipher(pass, salt, :decrypt)
  end

  def parse_meta
    buf = @file.read(BUFFER_LEN)
    yaml = ''
    yaml << @cipher.update(buf)
    unless yaml.start_with? YAML_START
      raise "bad key"
    end
    while "" != (buf = @file.read(BUFFER_LEN))
      block = @cipher.update(buf).split(/^---$/, 2)
      yaml << block[0]
      loop unless block.length == 2
      @meta.merge(YAML.load(yaml))
      @initial_content = block[1]
    end
  end

  def close
    @cipher.reset unless @cipher.nil?
    @file.close
  end
end

def password_match?(password)
  return TRUE if settings.upload_password.nil?
  (not password.nil?) && Digest::SHA1.hexdigest(password) == settings.upload_password
end

def uploaded_file(file)
  "#{options.root}/files/#{file}"
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
    return 404
  end
  base = request.url.gsub(/\/ready\/[^\/]*$/, '')
  @url = "#{base}/#{name}"
  haml :ready
end

get '/:name' do |name|
  path = uploaded_file(name)
  unless File.exists? path then
    return 404
  end
  send_file path
end

post '/upload' do
  unless password_match? params[:upload_password] then
    return 403
  end
  if params[:file] then
    tmpfile = params[:file][:tempfile]
    name = params[:file][:filename]
  end
  if tmpfile.nil? || name.nil? then
    @error = "No file selected"
    return haml(:index)
  end
  FileUtils::cp(tmpfile.path, uploaded_file(name))
  redirect "ready/#{name}"
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
