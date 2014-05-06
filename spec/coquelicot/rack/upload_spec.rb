# -*- coding: UTF-8 -*-
# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2012-2013 potager.org <jardiniers@potager.org>
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

require 'spec_helper'
require 'multipart_parser/reader'

module Coquelicot::Rack
  # Helpers method to have more readable code to test Rack responses
  module RackResponse
    def status; self[0]; end
    def headers; self[1]; end
    def body; buf = ''; self[2].each { |l| buf << l }; buf; end
  end

  describe Upload do

    include_context 'with Coquelicot::Application'

    let(:lower_app) { lambda { |env| [200, {'Content-Type' => 'text/plain'}, ['Lower']] } }
    let(:upload) { Upload.new(lower_app) }
    describe '#call' do
      subject { upload.call(env).extend(RackResponse) }
      context 'when receiving GET /' do
        let(:env) { { 'REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/' } }
        it 'should pass the request to the lower app' do
          expect(subject.body).to be == 'Lower'
        end
        it 'should ensure the forwarded rack.input is rewindable' do
          spec_app = double
          expect(spec_app).to receive(:call) do |env|
            expect(env['rack.input']).to respond_to(:rewind)
            [200, {'Content-Type' => 'text/plain'}, ['mock']]
          end
          input = StringIO.new('foo=bar&quux=blabb')
          class << input; undef_method(:rewind); end
          env['rack.input'] = input
          Upload.new(spec_app).call(env)
        end
      end
      context 'when called for GET /upload' do
        let(:env) { { 'REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/upload' } }
        it 'should pass the request to the lower app' do
          expect(subject.body).to be == 'Lower'
        end
      end
      context 'when called for POST /upload' do
        let(:env) { { 'SERVER_NAME' => 'example.org',
                      'SERVER_PORT' => 80,
                      'REQUEST_METHOD' => 'POST',
                      'PATH_INFO' => '/upload',
                      'CONTENT_TYPE' => "multipart/form-data; boundary=#{Rack::Multipart::MULTIPART_BOUNDARY}",
                      'CONTENT_LENGTH' => "#{input.size}",
                      'rack.input' => StringIO.new(input)
                    } }
        context 'when rack.input is rewindable' do
          let(:input) { '' }
          it 'should log a warning during the first request' do
            logger = double('Logger')
            expect(logger).to receive(:warn).with(/rewindable/).once
            env['rack.logger'] = logger
            # set it to nil to stop Sinatra from messing up
            upload = Class.new(Upload) { set :logging, nil }.new(lower_app)
            upload.call(env.dup)
            # second request, to be sure the warning will show up only once
            upload.call(env)
          end
        end
        context 'when receiving a request which is not multipart' do
          let(:input) { 'foo=bar&quux=blabb' }
          it 'should raise an error' do
            env['CONTENT_TYPE'] = 'application/x-www-form-urlencoded'
            expect { subject }.to raise_exception(::MultipartParser::NotMultipartError)
          end
        end

        shared_context 'correct POST data' do
          let(:file) { File.expand_path('../../../spec_helper.rb', __FILE__) }
          let(:file_content) { File.read(file) }
          let(:file_key) { 'secret' }
          let(:input) do <<MULTIPART_DATA.gsub(/\n/, "\r\n") % file_content
--AaB03x
Content-Disposition: form-data; name="upload_password"

whatever
--AaB03x
Content-Disposition: form-data; name="expire"

60
--AaB03x
Content-Disposition: form-data; name="file_key"

#{file_key}
--AaB03x
Content-Disposition: form-data; name="file"; filename="#{File.basename(file)}"
Content-Type: text/plain

%s
--AaB03x
Content-Disposition: form-data; name="submit"

submit
--AaB03x--
MULTIPART_DATA
          end
        end

        context 'when options are correct' do
          include_context 'correct POST data'
          before(:each) do
            Coquelicot.settings.authenticator.stub(:authenticate).and_return(true)
          end
          it 'should issue a temporary redirect' do
            expect(subject.status).to satisfy{|s| [302,303].include?(s) }
          end
          it 'should redirect to the ready page' do
            expect(subject.headers['Location']).to match %r{http://example\.org/ready/}
          end
          it 'should add a file to the depot' do
            filename = File.basename(file)
            expect(Coquelicot.depot).to receive(:add_file).
                with(file_key, hash_including('Filename' => filename)).
                and_yield.and_yield
            subject
          end
          it 'should increment the depot size' do
            expect { subject }.to change { Coquelicot.depot.size }.by(1)
          end
        end
        context 'when file is bigger than limit' do
          include_context 'correct POST data'
          before(:each) do
            Coquelicot.settings.authenticator.stub(:authenticate).and_return(true)
            Coquelicot.settings.stub(:max_file_size).and_return(100)
          end
          context 'when there is a request Content-Length header' do
            it 'should bail out with 413 (Request Entity Too Large)' do
              expect(subject.status).to be == 413
            end
            it 'should display "File is bigger than maximum allowed size"' do
              expect(subject.body).to include('File is bigger than maximum allowed size')
            end
            it 'should display the maximum file size' do
              expect(subject.body).to include('100 B')
            end
          end
          context 'when there is no request Content-Length header' do
            before(:each) do
              env['CONTENT_LENGTH'] = nil
            end
            it 'should bail out with 413 (Request Entity Too Large)' do
              expect(subject.status).to be == 413
            end
            it 'should display "File is bigger than maximum allowed size"' do
              expect(subject.body).to include('File is bigger than maximum allowed size')
            end
            it 'should display the maximum file size' do
              expect(subject.body).to include('100 B')
            end
          end
          context 'when the request Content-Length header is lying to us' do
            before(:each) do
              env['CONTENT_LENGTH'] = 99
            end
            it 'should bail out with 413 (Request Entity Too Large)' do
              expect(subject.status).to be == 413
            end
            it 'should display "File is bigger than maximum allowed size"' do
              expect(subject.body).to include('File is bigger than maximum allowed size')
            end
            it 'should display the maximum file size' do
              expect(subject.body).to include('100 B')
            end
          end
        end
        context 'when receiving a request with other fields after file' do
          before(:each) do
            Coquelicot.settings.authenticator.stub(:authenticate).and_return(true)
          end
          let(:file) { File.expand_path('../../../spec_helper.rb', __FILE__) }
          let(:file_content) { File.read(file) }
          let(:file_key) { 'secret' }
          let(:input) do <<MULTIPART_DATA.gsub(/\n/, "\r\n") % file_content
--AaB03x
Content-Disposition: form-data; name="upload_password"

whatever
--AaB03x
Content-Disposition: form-data; name="file_key"

#{file_key}
--AaB03x
Content-Disposition: form-data; name="file"; filename="#{File.basename(file)}"
Content-Type: text/plain

%s
--AaB03x
Content-Disposition: form-data; name="submit"

submit
--AaB03x
Content-Disposition: form-data; name="i_should_not_appear_here"

whatever
--AaB03x--
MULTIPART_DATA
          end
          it 'should bail out with code 400 (Bad Request)' do
            subject.status == 400
          end
          it 'should display "Bad Request: fields in unacceptable order"' do
            expect(subject.body).to include('Bad Request: fields in unacceptable order')
          end
        end
        context 'when authentication fails' do
          include_context 'correct POST data'
          before(:each) do
            Coquelicot.settings.authenticator.stub(:authenticate).and_return(false)
          end
          it 'should bail out with code 403 (Forbidden)' do
            subject.status == 403
          end
          it 'should display "Forbidden"' do
            expect(subject.body).to include('Forbidden')
          end
          it 'should not add a file' do
            expect { subject }.to_not change { Coquelicot.depot.size }
          end
        end
        context 'when authentication is impossible' do
          include_context 'correct POST data'
          before(:each) do
            Coquelicot.settings.authenticator.stub(:authenticate).and_raise(
              Coquelicot::Auth::Error.new('Something bad happened!'))
          end
          it 'should bail out with code 503 (Service Unavailable)' do
            subject.status == 503
          end
          it 'should display the error message' do
            expect(subject.body).to include('Something bad happened!')
          end
          it 'should not add a file' do
            expect { subject }.to_not change { Coquelicot.depot.size }
          end
        end
        context 'when no file has been submitted' do
          let(:input) do <<MULTIPART_DATA.gsub(/\n/, "\r\n")
--AaB03x
Content-Disposition: form-data; name="upload_password"

whatever
--AaB03x
Content-Disposition: form-data; name="expire"

60
--AaB03x
Content-Disposition: form-data; name="one_time"

true
--AaB03x
Content-Disposition: form-data; name="submit"

submit
--AaB03x--
MULTIPART_DATA
          end
          before(:each) do
            Coquelicot.settings.authenticator.stub(:authenticate).and_return(true)
          end
          it 'should pass to the lower app' do
            expect(subject.body).to be == 'Lower'
          end
          it 'should set X_COQUELICOT_FORWARD in env' do
            mock_app = double
            expect(mock_app).to receive(:call).
                with(hash_including('X_COQUELICOT_FORWARD')).
                and_return([200, {'Content-Type' => 'text/plain'}, ['forward mock']])
            Upload.new(mock_app).call(env)
          end
          it 'should forward interesting params' do
            mock_app = double
            expect(mock_app).to receive(:call) do
              request = Sinatra::Request.new(env)
              expect(request.params['upload_password']).to be == 'whatever'
              expect(request.params['expire']).to be == '60'
              expect(request.params['one_time']).to be == 'true'
              [200, {'Content-Type' => 'text/plain'}, ['forward mock']]
            end
            Upload.new(mock_app).call(env)
          end
          it 'should not add a file' do
            expect { subject }.to_not change { Coquelicot.depot.size }
          end
        end
        context 'when the expiration time is bigger than allowed' do
          include_context 'correct POST data'
          before(:each) do
            Coquelicot.settings.authenticator.stub(:authenticate).and_return(true)
            Coquelicot.settings.stub(:maximum_expire).and_return(5)
          end
          it 'should bail out with 403 (Forbidden)' do
            subject.status == 403
          end
          it 'should display "Forbidden: expiration time too big"' do
            expect(subject.body).to include('Forbidden: expiration time too big')
          end
          it 'should not add a file' do
            expect { subject }.to_not change { Coquelicot.depot.size }
          end
        end
      end
    end
  end
end
