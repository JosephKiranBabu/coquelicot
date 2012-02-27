# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2012 potager.org <jardiniers@potager.org>
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

require 'sinatra/base'
require 'rack/utils'
require 'rack/rewindable_input'
require 'tempfile'

module Coquelicot::Rack
  # a Request class that leaves applications to deal with POST data
  class Request < Sinatra::Request
    def POST
      {}
    end
  end

  class Upload < Sinatra::Base
    set :logging, true

    def call(env)
      if handle_request?(env)
        input = env['rack.input']
        input = input.input if input.is_a? Upr::InputWrapper
        if !@warned_of_rewind && input.respond_to?(:rewind)
          env['rack.logger'].warn <<-MESSAGE.gsub(/\n */m, ' ').strip
            It looks like the input stream is "rewindable". This means that
            somewhere along the process, the input request is probably buffered,
            either into memory or in a temporary file. In both case Coquelicot
            will not scale to big files, and in the later one, it might be a
            breach of privacy: the temporary file might be written to disk.
            Please use Rainbows! to serve web request for Coquelicot, which
            has been tested to provide and work with a fully streamed input.
          MESSAGE
          @warned_of_rewind = true
        end
        dup.call!(env)
      else
        unless env['rack.input'].respond_to? :rewind
          env['rack.input'] = Rack::RewindableInput.new(env['rack.input'])
        end
        @app.call(env)
      end
    end

  protected

    def handle_request?(env)
      env['REQUEST_METHOD'] == 'POST' && env['PATH_INFO'] == '/upload'
    end

    # This acts much like Sinatra's, but without request parsing,
    # as we have our own method here.
    def call!(env)
      @env = env
      @request = Request.new(env)
      @response = Sinatra::Response.new

      @response['Content-Type'] = nil
      invoke { dispatch! }
      invoke { error_block!(response.status) }

      unless @response['Content-Type']
        if Array === body and body[0].respond_to? :content_type
          content_type body[0].content_type
        else
          content_type :html
        end
      end

      @response.finish
    end

    def dispatch!
      catch(:pass) do
        return process!
      end
      forward
    end

    def process!
      # Stop users right now if input has already said the file is too big.
      length = @env['CONTENT_LENGTH']
      unless length.nil?
        length = length.to_i
        error_for_max_length(length) if length > Coquelicot.settings.max_file_size
      end

      MultipartParser.parse(@env) do |p|
        p.start do
          @expire = Coquelicot.settings.default_expire
          @file_key = ''
          @pass = Coquelicot.gen_random_pass
        end
        p.many_fields do |params|
          @auth_params = params
          begin
            @authenticated = Coquelicot.settings.authenticator.authenticate(@auth_params)
          rescue Coquelicot::Auth::Error => ex
            error 503, ex.message
          end
        end
        p.field :expire do |value|
          if value.to_i > Coquelicot.settings.maximum_expire
            error 403, 'Forbidden: expiration time too big'
          end
          @expire = value
        end
        p.field :one_time do |value|
          @one_time_only = value && value == 'true'
        end
        p.field :file_key do |value|
          @pass = @file_key = value unless value.empty?
        end
        p.file :file do |filename, type, reader|
          error 403, 'Forbidden' unless @authenticated

          max_length = Coquelicot.settings.max_file_size
          # We still compute the length of the received data manually, in case
          # input was lying.
          length = 0
          @link = Coquelicot.depot.add_file(
                    @pass,
                    'Expire-at' => Time.now + 60 * @expire.to_i,
                    'One-time-only' => @one_time_only,
                    'Filename' => filename,
                    'Content-Type' => type) do
            data = reader.call
            unless data.nil?
              length += data.bytesize
              error_for_max_length if length > max_length
            else
              error_for_empty if length == 0
            end
            data
          end
        end
        p.field :submit
        p.finish do
          unless @link.nil?
            redirect to(@file_key.empty? ? "/ready/#{@link}-#{@pass}" : "/ready/#{@link}")
          else
            params = @auth_params || {}
            params['expire'] = @expire
            params['one_time'] = 'true' if @one_time_only

            rewrite_input! params
            pass # will forward to the next Rack middlware
          end
        end
      end
    rescue EOFError => e
      raise unless e.message.start_with?('Unexpected part')
      error 400, 'Bad Request: fields in unacceptable order'
    end

    def forward
      # The following is to authenticate the request arriving
      # in Coquelicot::Application
      @env['X_COQUELICOT_FORWARD'] = 'Yes'
      super
    end

    def error_for_max_length(length = nil)
      # XXX: i18nize
      if length
        message = <<-MESSAGE.gsub(/\n */m, ' ').strip
          File is bigger than maximum allowed size:
          #{length.as_size} would exceed the
          maximum allowed #{Coquelicot.settings.max_file_size.as_size}.
        MESSAGE
      else
        message = <<-MESSAGE.gsub(/\n */m, ' ').strip
          File is bigger than maximum allowed size
          (#{Coquelicot.settings.max_file_size.as_size}).
        MESSAGE
      end
      error 413, message
    end

    def error_for_empty
      # XXX: i18nize
      error 403, 'File has no content'
    end

    # This will create a new (rewindable) input with the given params
    def rewrite_input!(params)
      @env['CONTENT_TYPE'] = 'application/x-www-form-urlencoded'
      data = Rack::Utils.build_nested_query(params)
      env['rack.input'] = StringIO.new(data)
    end
  end
end
