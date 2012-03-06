# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2010-2012 potager.org <jardiniers@potager.org>
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

UPLOAD_PASSWORD = 'secret'

# The specs in this file are written like what should have been Cucumber
# features and without much knowledge of best practices with RSpec. Most of
# them should be improved, rewritten and moved to `spec/coquelicot/app_spec.rb`.
#
# Once down, we could remove the dependency on Hpricot for the much better
# Capybara (which is used in `spec/coquelicot/app_spec.rb`).

describe 'Coquelicot' do
  include Rack::Test::Methods

  include_context 'with Coquelicot::Application'

  def upload(opts={})
    opts = { :file => Rack::Test::UploadedFile.new(__FILE__, 'text/x-script.ruby'),
             :upload_password => UPLOAD_PASSWORD
           }.merge(opts)
    post '/upload', opts
    return nil unless last_response.redirect?
    follow_redirect!
    last_response.should be_ok
    doc = Hpricot(last_response.body)
    return (doc/'a').collect { |a| a.attributes['href'] }.
             select { |h| h.start_with? "http://#{last_request.host}/" }[0]
  end

  it "should offer an upload form" do
    get '/'
    last_response.should be_ok
    doc = Hpricot(last_response.body)
    (doc/"form#upload").should have(1).items
  end

  context "when I explicitely ask for french" do
    it "should offer an upload form in french" do
      get '/', :lang => 'fr'
      last_response.should be_ok
      doc = Hpricot(last_response.body)
      (doc/"input.submit").attr('value').should == 'Partager !'
    end
  end

  context "when using 'simpleauth' authentication mechanism" do
    before(:each) do
      app.set :authentication_method, :name => :simplepass,
                                      :upload_password => Digest::SHA1.hexdigest(UPLOAD_PASSWORD)
    end

    context "after a successful upload" do
      before(:each) do
        @url = upload
      end

      it "should not store the file in cleartext" do
        files = Dir.glob("#{Coquelicot.depot.path}/*")
        files.should have(2).items
        File.new(files[0]).read().should_not include('should not store an uploaded file')
      end

      it "should generate a random URL to download the file" do
        @url.should_not include(File.basename(__FILE__))
      end

      it "should store the file with a different name than the one in URL" do
        url_name = @url.split('/')[-1]
        files = Dir.glob("#{Coquelicot.depot.path}/*")
        files.should have(2).items
        url_name.should_not eql(File.basename(files[0]))
      end

      it "should encode the encryption key in URL as no password has been specified" do
        url_name = @url.split('/')[-1]
        url_name.split('-').should have(2).items
      end

      it "should say 'not found' is password in URL is wrong" do
        get "#{@url}wrong"
        last_response.status.should == 404
      end

      it "should download when using extra Base32 characters in URL" do
        splitted = @url.split('/')
        name = splitted[-1].upcase.gsub(/O/, '0').gsub(/L/, '1')
        get "#{splitted[0..-2].join '/'}/#{name}"
        last_response.should be_ok
        last_response['Content-Type'].should eql('text/x-script.ruby')
      end

      context "when the file has been downloaded" do
        before(:each) do
          get @url
        end

        it "should be the same file as the uploaded" do
          last_response.should be_ok
          last_response['Content-Type'].should eql('text/x-script.ruby')
          last_response.body.should eql(File.new(__FILE__).read)
        end

        it "should always has the same Last-Modified header" do
          last_modified = last_response['Last-Modified']
          last_modified.should_not be_nil
          get @url
          last_response['Last-Modified'].should eql(last_modified)
        end
      end
    end

    context "given an empty file" do
      before do
        @empty_file = Tempfile.new('empty')
      end
      it "should not be accepted when uploaded" do
        url = upload :file => Rack::Test::UploadedFile.new(@empty_file.path, 'text/plain')
        url.should be_nil
        last_response.should_not be_redirect
      end
      after do
        @empty_file.close true
      end
    end

    it "should prevent upload without a password" do
      url = upload :upload_password => ''
      url.should be_nil
      last_response.status.should eql(403)
    end

    it "should prevent upload with a wrong password" do
      url = upload :upload_password => 'bad'
      url.should be_nil
      last_response.status.should eql(403)
    end

    context "when using AJAX to verify upload password" do
      context "when sending the right password" do
        before do
          request "/authenticate", :method => "POST", :xhr => true,
                                   :params => { :upload_password => UPLOAD_PASSWORD }
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
        last_response.should be_ok
        last_response['Content-Type'].should eql('text/x-script.ruby')
        last_response.body.should eql(File.new(__FILE__).read)
      end

      it "should not be downloadable any more" do
        get @url
        last_response.status.should eql(410)
      end

      it "should have zero'ed the file on the server" do
        files = Dir.glob("#{Coquelicot.depot.path}/*")
        files.should have(2).items
        File.lstat(files[0]).size.should eql(0)
      end
    end

    context "after a password protected upload" do
      before(:each) do
        @url = upload :file_key => 'somethingSecret'
      end

      it "should not return an URL with the encryption key" do
        url_name = @url.split('/')[-1]
        url_name.split('-').should have(1).items
      end

      it "should offer a password form before download" do
        get @url
        last_response.should be_ok
        last_response['Content-Type'].should eql('text/html;charset=utf-8')
        doc = Hpricot(last_response.body)
        (doc/'input#file_key').should have(1).items
      end

      context "when given the correct password" do
        it "should download the same file" do
          post @url, :file_key => 'somethingSecret'
          last_response.should be_ok
          last_response['Content-Type'].should eql('text/x-script.ruby')
          last_response.body.should eql(File.new(__FILE__).read)
        end
      end

      it "should prevent download without a password" do
        post @url
        last_response.status.should eql(403)
      end

      it "should prevent download with a wrong password" do
        post @url, :file_key => 'BAD'
        last_response.status.should eql(403)
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
          last_response.status.should eql(410)
        end
      end
    end

    it "should refuse an expiration time longer than the maximum" do
      upload :expire => 60 * 24 * 31 * 12 # 1 year
      last_response.status.should eql(403)
    end

    it "should cleanup expired files" do
      url = upload :expire => 60, :file_key => 'test' # 1 hour
      url_name = url.split('/')[-1]
      Dir.glob("#{Coquelicot.depot.path}/*").should have(2).items
      # let's be the day after tomorrow
      Timecop.travel(Date.today + 2) do
        Coquelicot.depot.gc!
        files = Dir.glob("#{Coquelicot.depot.path}/*")
        files.should have(2).items
        File.lstat(files[0]).size.should eql(0)
        Coquelicot.depot.get_file(url_name).expired?.should be_true
      end
      # let's be after 'gone' period
      Timecop.travel(Time.now + (Coquelicot.settings.gone_period * 60)) do
        Coquelicot.depot.gc!
        Dir.glob("#{Coquelicot.depot.path}/*").should have(0).items
        Coquelicot.depot.get_file(url_name).should be_nil
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
      imap = stub('Net::Imap').as_null_object
      imap.should_receive(:login).with('user', 'password')
      Net::IMAP.should_receive(:new).with('example.org', 993, true).and_return(imap)

      request "/authenticate", :method => "POST", :xhr => true,
                               :params => { :imap_user     => 'user',
                                            :imap_password => 'password' }
      last_response.should be_ok
    end
  end
end
