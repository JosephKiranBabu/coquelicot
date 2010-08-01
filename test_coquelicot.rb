$:.unshift File.join(File.dirname(__FILE__), '../rack-test/lib')

require 'sinatra'
require 'coquelicot'
require 'spec'
require 'rack/test'
require 'hpricot'
require 'tmpdir'

UPLOAD_PASSWORD = 'secret'

set :environment, :test
set :upload_password, Digest::SHA1.hexdigest(UPLOAD_PASSWORD)

module Depot
  def Depot.path=(path) @@path = path end
  def Depot.path()      @@path        end
end
set :depot_path, Proc.new { Depot.path }

describe 'Coquelicot' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  before do
    Depot.path = Dir.mktmpdir('coquelicot')
  end

  after do
    FileUtils.remove_entry_secure Depot.path
  end

  it "should offer an upload form" do
    get '/'
    last_response.should be_ok
    doc = Hpricot(last_response.body)
    (doc/"form#upload").should have(1).items
  end

  it "should accept an uploaded file" do
    post '/upload', 'file' => Rack::Test::UploadedFile.new(__FILE__, 'text/x-script.ruby'),
                    'upload_password' => UPLOAD_PASSWORD
    last_response.redirect?.should be_true
    last_response['Location'].start_with?('ready/').should be_true
  end

  it "should allow retrieval of an uploaded file" do
    post '/upload', 'file' => Rack::Test::UploadedFile.new(__FILE__, 'text/x-script.ruby'),
                    'upload_password' => UPLOAD_PASSWORD
    follow_redirect!
    last_response.should be_ok
    doc = Hpricot(last_response.body)
    url = (doc/'a').collect { |a| a.attributes['href'] }.
      select { |h| h.start_with? "http://#{last_request.host}/" }[0]
    get url
    last_response.should be_ok
    last_response['Content-Type'].should eql('text/x-script.ruby')
    last_response.body.should eql(File.new(__FILE__).read)
  end

  it "should prevent upload without a password" do
    post '/upload', 'file' => Rack::Test::UploadedFile.new(__FILE__, 'text/x-script.ruby')
    last_response.status.should eql(403)
  end

  it "should prevent upload with a wrong password" do
    post '/upload', 'file' => Rack::Test::UploadedFile.new(__FILE__, 'text/x-script.ruby'),
                    'upload_password' => "bad"
    last_response.status.should eql(403)
  end

  it "should not store an uploaded file in cleartext" do
    post '/upload', 'file' => Rack::Test::UploadedFile.new(__FILE__, 'text/x-script.ruby'),
                    'upload_password' => UPLOAD_PASSWORD
    last_response.redirect?.should be_true
    files = Dir.glob("#{Depot.path}/*")
    files.should have(1).items
    File.new(files[0]).read().should_not include('should not store an uploaded file')
  end

  it "should generate a random URL to retrieve a file" do
    post '/upload', 'file' => Rack::Test::UploadedFile.new(__FILE__, 'text/x-script.ruby'),
                    'upload_password' => UPLOAD_PASSWORD
    last_response.redirect?.should be_true
    last_response['Location'].should_not include(File.basename(__FILE__))
  end

  it "should store files with a different name than then one in URL"

  it "should encode the encryption key in URL when no password has been specified"

  it "should not encode the encryption key in URL when no password has been specified"

  it "should give a random password when asked"

  it "should allow retrieval of a password protected file"

  it "should not allow retrieval of a password protected file without the password"

  it "should not allow retrieval after the time limit has expired"

  it "should cleanup expired files"
end
