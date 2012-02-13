require 'sinatra/base'
require 'haml'
require 'sass'
require 'digest/sha1'
require 'gettext'
require 'haml_gettext'

module Coquelicot
  class << self
    def settings
      (class << self; Application; end)
    end
    def depot
      @depot = Depot.new(settings.depot_path) if @depot.nil? || settings.depot_path != @depot.path
      @depot
    end
  end

  class Application < Sinatra::Base
    set :root, Proc.new { app_file && File.expand_path('../../..', app_file) }
    include Coquelicot::Configure

    GetText::bindtextdomain('coquelicot')
    before do
      GetText::set_current_locale(params[:lang] || request.env['HTTP_ACCEPT_LANGUAGE'] || 'en')
    end

    not_found do
      'Not found'
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
      not_found if link.nil?

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

    post '/authenticate' do
      pass unless request.xhr?
      unless authenticate(params) then
        error 403, "Forbidden"
      end
      'OK'
    end

    post '/upload' do
      # if JS is disabled upload_token might be nil
      params['upload_token'] = JSON.parse(params['upload_token']) unless params['upload_token'].nil?
      unless authenticate(params) then
        error 403, "Forbidden"
      end
      if params[:file] then
        tmpfile = params[:file][:tempfile]
        name = params[:file][:filename]
      end
      if tmpfile.nil? || name.nil? then
        @error = "No file selected"
        return haml(:index)
      end
      if tmpfile.lstat.size == 0 then
        @error = "#{name} is empty"
        return haml(:index)
      end
      if params[:expire].nil? or params[:expire].to_i == 0 then
        params[:expire] = settings.default_expire
      elsif params[:expire].to_i > settings.maximum_expire then
        error 403
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

      if file.one_time_only?
        begin
          # unlocking done in file.close
          file.lockfile.lock
        rescue Lockfile::TimeoutLockError
          error 409, "Download currently in progress"
        end
      end
      send_stored_file(file)
    end

    get '/:link-:pass' do |link, pass|
      not_found if link.nil? || pass.nil?

      link = Coquelicot.remap_base32_extra_characters(link)
      pass = Coquelicot.remap_base32_extra_characters(pass)
      not_found unless send_link(link, pass)
    end

    get '/:link' do |link|
      not_found if link.nil?

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

      def clone_url
        settings.respond_to?(:clone_url) ? settings.clone_url : "#{base_href}coquelicot.git"
      end

      def authenticate(params)
        Coquelicot.settings.authenticator.authenticate(params)
      end

      def auth_method
        Coquelicot.settings.authenticator.class.name.gsub(/Coquelicot::Auth::([A-z0-9]+)Authenticator$/, '\1').downcase
      end
    end
  end
end

Coquelicot::Application.run! if __FILE__ == $0
