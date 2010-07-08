$:.unshift File.join(File.dirname(__FILE__), '../rack-test/lib')

require 'coquelicot'
require 'spec'
require 'rack/test'
require 'hpricot'

set :environment, :test

describe 'Coquelicot' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  it "should offer an upload form" do
    get '/'
    last_response.should be_ok
    doc = Hpricot(last_response.body)
    (doc/"form#upload").should have(1).items
  end

  it "should accept an uploaded file" do
    post '/upload', 'file' => Rack::Test::UploadedFile.new(__FILE__, 'text/x-script.ruby')
    last_response.redirect?.should be_true
    last_response['Location'].should eql("ready/#{File.basename(__FILE__)}")
  end

  it "should allow retrieval of an uploaded file" do
    post '/upload', 'file' => Rack::Test::UploadedFile.new(__FILE__, 'text/x-script.ruby')
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

  it "should prevent upload without a password"

  it "should not store an uploaded file in cleartext"

  it "should generate a random URL to retrieve a file"

  it "should store files with a different name than then one in URL"

  it "should encode the encryption key in URL when no password has been specified"

  it "should not encode the encryption key in URL when no password has been specified"

  it "should give a random password when asked"

  it "should allow retrieval of a password protected file"

  it "should not allow retrieval of a password protected file without the password"

  it "should not allow retrieval after the time limit has expired"

  it "should cleanup expired files"
end
