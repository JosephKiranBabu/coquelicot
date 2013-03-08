# -*- coding: UTF-8 -*-
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
require 'sinatra/config_file'
require 'sass'
require 'digest/sha1'
require 'fast_gettext'
require 'upr'
require 'moneta'
require 'unicorn/launcher'
require 'rainbows'
require 'optparse'

module Coquelicot
  class << self
    def settings
      (class << self; Application; end)
    end
    def depot
      @depot = Depot.new(settings.depot_path) if @depot.nil? || settings.depot_path != @depot.path
      @depot
    end
    # Called by the +coquelicot+ script.
    def run!(args = [])
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: #{opts.program_name} [options] COMMAND [command options]"

        opts.separator ""
        opts.separator "Common options:"

        opts.on "-c", "--config FILE", "read settings from FILE" do |file|
          if File.readable? file
            settings.config_file file
          else
            $stderr.puts "#{opts.program_name}: cannot access configuration file '#{file}'."
            exit 1
          end
        end
        opts.on("-h", "--help", "show this message") do
          $stderr.puts opts.to_s
          exit
        end
        opts.separator ""
        opts.separator "Available commands:"
        opts.separator "    start             Start web server"
        opts.separator "    stop              Stop web server"
        opts.separator "    gc                Run garbage collection"
        opts.separator "    migrate-jyraphe   Migrate a Jyraphe repository"
        opts.separator ""
        opts.separator "See '#{opts.program_name} COMMAND --help' for more information on a specific command."
      end
      begin
        parser.order!(args) do |command|
          if %w{start stop gc migrate-jyraphe}.include? command
            return self.send("#{command.gsub(/-/, '_')}!", args)
          else
            $stderr.puts("#{parser.program_name}: '#{command}' is not a valid command. " +
                         "See '#{parser.program_name} --help'.")
            exit 1
          end
        end
      rescue OptionParser::InvalidOption => ex
        $stderr.puts("#{parser.program_name}: '#{ex.args[0]}' is not a valid option. " +
                     "See '#{parser.program_name} --help'.")
        exit 1
      end
      # if we reach here, no command was given
      $stderr.puts parser.to_s
      exit
    end
    def start!(args)
      options = {}
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: #{opts.program_name} [options] start [command options]"
        opts.separator ""
        opts.separator "'#{opts.program_name} start' will start the web server in background."
        opts.separator "Use '#{opts.program_name} stop' to stop it when done serving."
        opts.separator ""
        opts.separator "Command options:"
        opts.on_tail("-n", "--no-daemon", "do not daemonize (stay in foreground)") do
          options[:no_daemon] = true
        end
        opts.on_tail("-h", "--help", "show this message") do
          $stderr.puts opts.to_s
          exit
        end
      end
      parser.parse!(args)

      Unicorn::Configurator::DEFAULTS.merge!({
        :pid => settings.pid,
        :listeners => settings.listen,
        :use => :ThreadSpawn,
        :rewindable_input => false,
        :client_max_body_size => nil
      })
      unless options[:no_daemon]
        if settings.log
          Unicorn::Configurator::DEFAULTS.merge!({
            :stdout_path => settings.log,
            :stderr_path => settings.log
          })
        end
      end

      # daemonize! and start pass data around through rainbows_opts
      rainbows_opts = {}
      ::Unicorn::Launcher.daemonize!(rainbows_opts) unless options[:no_daemon]

      app = lambda do
          ::Rack::Builder.new do
            # This implements the behaviour outlined in Section 8 of
            # <http://ftp.ics.uci.edu/pub/ietf/http/draft-ietf-http-connection-00.txt>.
            #
            # Half-closing the write part first and draining our input makes sure the
            # client will properly receive an error message instead of TCP RST (a.k.a.
            # "Connection reset by peer") when we interrupt it in the middle of a POST
            # request.
            #
            # Thanks Eric Wong for these few lines. See
            # <http://rubyforge.org/pipermail/rainbows-talk/2012-February/000328.html> for
            # the discussion that lead him to propose what follows.
            Rainbows::Client.class_eval <<-END_OF_METHOD
              def close
                close_write
                buf = ""
                loop do
                  kgio_wait_readable(2)
                  break unless kgio_tryread(512, buf)
                end
              ensure
                super
              end
            END_OF_METHOD

            use ::Rack::ContentLength
            use ::Rack::Chunked
            use ::Rack::CommonLogger, $stderr
            run Application
          end.to_app
        end

      server = ::Rainbows::HttpServer.new(app, rainbows_opts)
      server.start.join
    end
    def stop!(args)
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: #{opts.program_name} [options] stop [command options]"
        opts.separator ""
        opts.separator "'#{opts.program_name} stop' will stop the web server."
        opts.separator ""
        opts.separator "Command options:"
        opts.on_tail("-h", "--help", "show this message") do
          $stderr.puts opts.to_s
          exit
        end
      end
      parser.parse!(args)

      unless File.readable? settings.pid
        $stderr.puts "Unable to read #{settings.pid}. Are you sure Coquelicot is started?"
        exit 1
      end

      pid = File.read(settings.pid).to_i
      if pid == 0
        $stderr.puts "Bad PID file #{settings.pid}."
        exit 1
      end

      Process.kill(:TERM, pid)
    end
    def gc!(args)
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: #{opts.program_name} [options] gc [command options]"
        opts.separator ""
        opts.separator "'#{opts.program_name} gc' will clean up expired files from the current depot."
        opts.separator "Depot is currently set to '#{Coquelicot.depot.path}'"
        opts.separator ""
        opts.separator "Command options:"
        opts.on_tail("-h", "--help", "show this message") do
          $stderr.puts opts.to_s
          exit
        end
      end
      parser.parse!(args)
      depot.gc!
    end
    def migrate_jyraphe!(args = [])
      require 'coquelicot/jyraphe_migrator'
      Coquelicot::JyrapheMigrator.run! args
    end
  end

  class Application < Coquelicot::BaseApp
    register Sinatra::ConfigFile
    register Coquelicot::Auth::Extension

    enable :sessions
    # When sessions are enabled, Rack::Protection (added by Sinatra)
    # will choke on our lack of rewind method on our input. Let's
    # deactivate the protections which needs to parse parameters, then.
    set :protection, :except => [:session_hijacking, :remote_token]

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
    set :pid, Proc.new { File.join(root, 'tmp/coquelicot.pid') }
    set :log, Proc.new { File.join(root, 'tmp/coquelicot.log') }
    set :listen, [ "127.0.0.1:51161" ]
    set :show_exceptions, false
    set :authentication_method, :name => :simplepass,
                                :upload_password => 'a94a8fe5ccb19ba61c4c0873d391e987982fbbd3'

    config_file File.expand_path('../../../conf/settings.yml', __FILE__)

    set :upr_backend, Upr::Monitor.new(Moneta.new(:Memory))
    if defined?(Rainbows) && !Rainbows.server.nil? && !Rainbows.server.rewindable_input
      use Upr, :backend => upr_backend, :path_info => %q{/upload}
    end
    use Coquelicot::Rack::Upload
    # limit requests other than upload to an input body of 5 kiB max
    use Rainbows::MaxBody, 5 * 1024

    not_found do
      @uri = env['REQUEST_URI']
      haml :not_found
    end

    error 403 do
      haml :forbidden
    end

    error 409 do
      haml :download_in_progress
    end

    error 500..510 do
      @error = env['sinatra.error'] || response.body.join
      haml :error
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

    get '/about-your-data' do
      haml :about_your_data
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

    get '/progress' do
      response.headers.update(Upr::JSON::RESPONSE_HEADERS)
      data = Upr::JSON.new(:env => request.env,
                           :backend => settings.upr_backend,
                           :upload_id => params['X-Progress-ID'])._once
      halt 200, { 'Content-Type' => 'application/json' }, data
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
  end
end

Coquelicot::Application.run! if __FILE__ == $0
