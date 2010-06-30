require 'sinatra'
require 'haml'

enable :inline_templates

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
