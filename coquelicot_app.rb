$:.unshift File.join(File.dirname(__FILE__), 'lib')

require 'sinatra'
require 'haml'
require 'digest/sha1'
require 'gettext'
require 'coquelicot'
require 'haml_gettext'

set :upload_password, '0e5f7d398e6f9cd1f6bac5cc823e363aec636495'

def password_match?(password)
  return TRUE if settings.upload_password.nil?
  (not password.nil?) && Digest::SHA1.hexdigest(password) == settings.upload_password
end

GetText::bindtextdomain('coquelicot')
before do
  GetText::set_current_locale(params[:lang] || request.env['HTTP_ACCEPT_LANGUAGE'] || 'en')
end

get '/style.css' do
  content_type 'text/css', :charset => 'utf-8'
  sass :style
end

get '/' do
  haml :index
end

get '/random_pass' do
  "#{Coquelicot.gen_random_pass}"
end

get '/ready/:link' do |link|
  link, pass = link.split '-' if link.include? '-'
  begin
    file = Coquelicot.depot.get_file(link, nil)
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
    params[:expire] = Coquelicot.settings.default_expire
  end
  expire_at = Time.now + 60 * params[:expire].to_i
  one_time_only = params[:one_time] and params[:one_time] == 'true'
  if params[:file_key].nil? or params[:file_key].empty?then
    pass = Coquelicot.gen_random_pass
  else
    pass = params[:file_key]
  end
  src = params[:file][:tempfile]
  link = Coquelicot.depot.add_file(
     src, pass,
     { "Expire-at" => expire_at.to_i,
       "One-time-only" => one_time_only,
       "Filename" => params[:file][:filename],
       "Length" => src.stat.size,
       "Content-Type" => params[:file][:type],
     })
  redirect "ready/#{link}-#{pass}" if params[:file_key].nil? or params[:file_key].empty?
  redirect "ready/#{link}"
end

def expired
  throw :halt, [410, haml(:expired)]
end

def send_stored_file(file)
  last_modified file.created_at.httpdate
  attachment file.meta['Filename']
  response['Content-Length'] = "#{file.meta['Length']}"
  response['Content-Type'] = file.meta['Content-Type'] || 'application/octet-stream'
  throw :halt, [200, file]
end

def send_link(link, pass)
  file = Coquelicot.depot.get_file(link, pass)
  return false if file.nil?
  return expired if file.expired?

  return send_stored_file(file) unless file.one_time_only?

  file.exclusively do
    begin  send_stored_file(file)
    ensure file.empty!            end
  end
end

get '/:link-:pass' do |link, pass|
  link = Coquelicot.remap_base32_extra_characters(link)
  pass = Coquelicot.remap_base32_extra_characters(pass)
  not_found unless send_link(link, pass)
end

get '/:link' do |link|
  link = Coquelicot.remap_base32_extra_characters(link)
  not_found unless Coquelicot.depot.file_exists? link
  @link = link
  haml :enter_file_key
end

post '/:link' do |link|
  pass = params[:file_key]
  return 403 if pass.nil? or pass.empty?
  begin
    # send Forbidden even if file is not found
    return 403 unless send_link(link, pass)
  rescue Coquelicot::BadKey => ex
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
