# -*- coding: UTF-8 -*-
# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2010-2013 potager.org <jardiniers@potager.org>
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

require 'timecop'
require 'hpricot'
require 'tmpdir'
require 'active_support'

# The specs in this file are written like what should have been Cucumber
# features and without much knowledge of best practices with RSpec. Most of
# them should be improved, rewritten and moved to `spec/coquelicot/app_spec.rb`.
#
# Once down, we could remove the dependency on Hpricot for the much better
# Capybara (which is used in `spec/coquelicot/app_spec.rb`).

describe 'Coquelicot' do
  include Rack::Test::Methods

  include_context 'with Coquelicot::Application'

  def upload_password
    'secret'
  end

  def upload(opts={})
    # We need the request to be in the right order
    params = ActiveSupport::OrderedHash.new
    params[:upload_password] = upload_password
    params[:expire] = 5
    params[:one_time] = ''
    params[:file_key] = ''
    params[:file] = Rack::Test::UploadedFile.new(__FILE__, 'text/x-script.ruby')
    params.merge!(opts)
    data = build_multipart(params)
    post '/upload', {}, { :input           => data,
                          'CONTENT_LENGTH' => data.length.to_s,
                          'CONTENT_TYPE'   => "multipart/form-data; boundary=#{Rack::Multipart::MULTIPART_BOUNDARY}"
                        }
    return nil unless last_response.redirect?
    follow_redirect!
    expect(last_response).to be_ok
    doc = Hpricot(last_response.body)
    return (doc/'.ready')[0].inner_text
  end

  def build_multipart(params)
    params.map do |name, value|
      if value.is_a? Rack::Test::UploadedFile
        <<-PART
--#{Rack::Multipart::MULTIPART_BOUNDARY}\r
Content-Disposition: form-data; name="#{name}"; filename="#{Rack::Utils.escape(value.original_filename)}"\r
Content-Type: #{value.content_type}\r
Content-Length: #{::File.stat(value.path).size}\r
\r
#{slurp(value.path)}\r
PART
      else
        <<-PART
--#{Rack::Multipart::MULTIPART_BOUNDARY}\r
Content-Disposition: form-data; name="#{name}"\r
\r
#{value}\r
PART
      end
    end.join + "--#{Rack::Multipart::MULTIPART_BOUNDARY}--\r"
  end

  it "should offer an upload form" do
    get '/'
    expect(last_response).to be_ok
    doc = Hpricot(last_response.body)
    expect(doc/"form#upload").to have(1).items
  end

  context "when I explicitely ask for french" do
    it "should offer an upload form in french" do
      get '/', :lang => 'fr'
      expect(last_response).to be_ok
      doc = Hpricot(last_response.body)
      expect((doc/"#submit").attr('value')).to be == 'Partager !'
    end
  end

  context "when using 'simpleauth' authentication mechanism" do
    before(:each) do
      app.set :authentication_method, :name => :simplepass,
                                      :upload_password => Digest::SHA1.hexdigest(upload_password)
    end

    context "after a successful upload" do
      before(:each) do
        @url = upload
      end

      it "should not store the file in cleartext" do
        files = Dir.glob("#{Coquelicot.depot.path}/*")
        expect(files).to have(2).items
        expect(File.new(files[0]).read()).to_not include('should not store an uploaded file')
      end

      it "should generate a random URL to download the file" do
        expect(@url).to_not include(File.basename(__FILE__))
      end

      it "should store the file with a different name than the one in URL" do
        url_name = @url.split('/')[-1]
        files = Dir.glob("#{Coquelicot.depot.path}/*")
        expect(files).to have(2).items
        expect(url_name).to_not eql(File.basename(files[0]))
      end

      it "should encode the encryption key in URL as no password has been specified" do
        url_name = @url.split('/')[-1]
        expect(url_name.split('-')).to have(2).items
      end

      it "should say 'not found' is password in URL is wrong" do
        get "#{@url}wrong"
        expect(last_response.status).to be == 404
      end

      it "should download when using extra Base32 characters in URL" do
        splitted = @url.split('/')
        name = splitted[-1].upcase.gsub(/O/, '0').gsub(/L/, '1')
        get "#{splitted[0..-2].join '/'}/#{name}"
        expect(last_response).to be_ok
        expect(last_response['Content-Type']).to eql('text/x-script.ruby')
      end

      context "when the file has been downloaded" do
        before(:each) do
          get @url
        end

        it "should be the same file as the uploaded" do
          expect(last_response).to be_ok
          expect(last_response['Content-Type']).to eql('text/x-script.ruby')
          expect(last_response.body).to be == slurp(__FILE__)
        end

        it "should have sent the right Content-Length" do
          expect(last_response).to be_ok
          expect(last_response['Content-Length'].to_i).to be == File.stat(__FILE__).size
        end

        it "should always has the same Last-Modified header" do
          last_modified = last_response['Last-Modified']
          expect(last_modified).to_not be_nil
          get @url
          expect(last_response['Last-Modified']).to eql(last_modified)
        end
      end
    end

    context "given an empty file" do
      before do
        @empty_file = Tempfile.new('empty')
      end
      it "should not be accepted when uploaded" do
        url = upload :file => Rack::Test::UploadedFile.new(@empty_file.path, 'text/plain')
        expect(url).to be_nil
        expect(last_response).to_not be_redirect
      end
      after do
        @empty_file.close true
      end
    end

    it "should prevent upload without a password" do
      url = upload :upload_password => ''
      expect(url).to be_nil
      expect(last_response.status).to eql(403)
    end

    it "should prevent upload with a wrong password" do
      url = upload :upload_password => 'bad'
      expect(url).to be_nil
      expect(last_response.status).to eql(403)
    end

    context "when using AJAX to verify upload password" do
      context "when sending the right password" do
        before do
          request "/authenticate", :method => "POST", :xhr => true,
                                   :params => { :upload_password => upload_password }
        end
        subject { last_response }
        it { should be_ok }
      end
      context "when sending no password" do
        before do
          request "/authenticate", :method => "POST", :xhr => true,
                                   :params => { :upload_password => '' }
        end
        subject { last_response.status }
        it { should == 403 }
      end
      context "when sending a JSON dump of the wrong password" do
        before do
          request "/authenticate", :method => "POST", :xhr => true,
                                   :params => { :upload_password => 'wrong'}
        end
        subject { last_response.status }
        it { should == 403 }
      end
    end

    context "when a 'one time download' has been retrieved" do
      before(:each) do
        @url = upload :one_time => true
        get @url
      end

      it "should be the same as the uploaded file" do
        expect(last_response).to be_ok
        expect(last_response['Content-Type']).to eql('text/x-script.ruby')
        expect(last_response.body).to be == slurp(__FILE__)
      end

      it "should not be downloadable any more" do
        get @url
        expect(last_response.status).to eql(410)
      end

      it "should have zero'ed the file on the server" do
        files = Dir.glob("#{Coquelicot.depot.path}/*")
        expect(files).to have(2).items
        expect(File.lstat(files[0]).size).to eql(0)
      end
    end

    context "after a password protected upload" do
      before(:each) do
        @url = upload :file_key => 'somethingSecret'
      end

      it "should not return an URL with the encryption key" do
        url_name = @url.split('/')[-1]
        expect(url_name.split('-')).to have(1).items
      end

      it "should offer a password form before download" do
        get @url
        expect(last_response).to be_ok
        expect(last_response['Content-Type']).to be == 'text/html;charset=utf-8'
        doc = Hpricot(last_response.body)
        expect(doc/'input#file_key').to have(1).items
      end

      context "when given the correct password" do
        it "should download the same file" do
          post @url, :file_key => 'somethingSecret'
          expect(last_response).to be_ok
          expect(last_response['Content-Type']).to be == 'text/x-script.ruby'
          expect(last_response.body).to be == slurp(__FILE__)
        end
      end

      it "should prevent download without a password" do
        post @url
        expect(last_response.status).to eql(403)
      end

      it "should prevent download with a wrong password" do
        post @url, :file_key => 'BAD'
        expect(last_response.status).to eql(403)
      end
    end

    context "after an upload with a time limit" do
      before(:each) do
        @url = upload :expire => 60 # 1 hour
      end

      it "should prevent download after the time limit has expired" do
        # let's be the day after tomorrow
        Timecop.travel(Date.today + 2) do
          get @url
          expect(last_response.status).to eql(410)
        end
      end
    end

    it "should refuse an expiration time longer than the maximum" do
      upload :expire => 60 * 24 * 31 * 12 # 1 year
      expect(last_response.status).to eql(403)
    end

    it "should cleanup expired files" do
      url = upload :expire => 60, :file_key => 'test' # 1 hour
      url_name = url.split('/')[-1]
      expect(Dir.glob("#{Coquelicot.depot.path}/*")).to have(2).items
      # let's be the day after tomorrow
      Timecop.travel(Date.today + 2) do
        Coquelicot.depot.gc!
        files = Dir.glob("#{Coquelicot.depot.path}/*")
        expect(files).to have(2).items
        expect(File.lstat(files[0]).size).to eql(0)
        expect(Coquelicot.depot.get_file(url_name)).to be_expired
      end
      # let's be after 'gone' period
      Timecop.travel(Time.now + (Coquelicot.settings.gone_period * 60)) do
        Coquelicot.depot.gc!
        expect(Dir.glob("#{Coquelicot.depot.path}/*")).to be_empty
        expect(Coquelicot.depot.get_file(url_name)).to be_nil
      end
    end
  end

  context "when using 'imap' authentication mechanism" do
    before(:each) do
      app.set :authentication_method, :name => 'imap',
                                      :imap_server => 'example.org',
                                      :imap_port => 993
    end

    it "should try to login to the IMAP server when using AJAX" do
      imap = double('Net::Imap').as_null_object
      expect(imap).to receive(:login).with('user', 'password')
      expect(Net::IMAP).to receive(:new).with('example.org', 993, true).and_return(imap)

      request "/authenticate", :method => "POST", :xhr => true,
                               :params => { :imap_user     => 'user',
                                            :imap_password => 'password' }
      expect(last_response).to be_ok
    end
  end
end
