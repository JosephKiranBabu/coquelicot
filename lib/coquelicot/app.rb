# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2010-2012 potager.org <jardiniers@potager.org>
#           © 2011 mh / immerda.ch <mh+coquelicot@immerda.ch>
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

require 'lockfile'
require 'sinatra/base'
require 'sinatra/config_file'
require 'haml'
require 'haml/magic_translations'
require 'sass'
require 'digest/sha1'
require 'fast_gettext'

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
    use Coquelicot::Rack::Upload

    register Sinatra::ConfigFile
    register Coquelicot::Auth::Extension

    set :root, Proc.new { app_file && File.expand_path('../../..', app_file) }
    set :depot_path, Proc.new { File.join(root, 'files') }
    set :max_file_size, 5 * 1024 * 1024 # 5 MiB
    set :default_expire, 60
    set :maximum_expire, 60 * 24 * 30 # 1 month
    set :gone_period, 60 * 24 * 7 # 1 week
    set :filename_length, 20
    set :random_pass_length, 16
    set :about_text, ''
    set :additional_css, ''
    set :authentication_method, :name => :simplepass,
                                :upload_password => 'a94a8fe5ccb19ba61c4c0873d391e987982fbbd3'

    config_file File.expand_path('../../../conf/settings.yml', __FILE__)

    FastGettext.add_text_domain 'coquelicot', :path => 'po', :type => 'po'
    FastGettext.available_locales = [ 'en', 'fr', 'de' ]
    Haml::MagicTranslations.enable(:fast_gettext)
    before do
      FastGettext.text_domain = 'coquelicot'
      FastGettext.locale = params[:lang] || request.env['HTTP_ACCEPT_LANGUAGE'] || 'en'
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

    get '/README' do
      haml(":markdown\n" +
           File.read(File.join(settings.root, 'README')).gsub(/^/, '  '))
    end

    get '/random_pass' do
      "#{Coquelicot.gen_random_pass}"
    end

    get '/ready/:link' do |link|
      not_found if link.nil?

      link, pass = link.split '-' if link.include? '-'
      file = Coquelicot.depot.get_file(link, nil)

      not_found if file.nil?

      @expire_at = file.expire_at
      @name = "#{link}"
      unless pass.nil?
        @name << "-#{pass}"
        @unprotected = true
      end
      @url = uri(@name)
      haml :ready
    end

    post '/authenticate' do
      pass unless request.xhr?
      begin
        unless authenticate(params)
          error 403, "Forbidden"
        end
        'OK'
      rescue Coquelicot::Auth::Error => ex
        error 503, ex.message
      end
    end

    post '/upload' do
      # Normally handled by Coquelicot::Rack::Upload, only failures
      # will arrive here.
      error 500, 'Rack::Coquelicot::Upload failed' if @env['X_COQUELICOT_FORWARD'].nil?

      if params[:file].nil? then
        @error = "No file selected"
        return haml(:index)
      end

      error 500, 'Something went wrong: this code should never be executed'
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
      begin
        not_found unless send_link(link, pass)
      rescue Coquelicot::BadKey
        not_found
      end
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
      def clone_url
        settings.respond_to?(:clone_url) ? settings.clone_url : uri('coquelicot.git')
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
