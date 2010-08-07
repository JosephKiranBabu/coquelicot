$:.unshift File.join(File.dirname(__FILE__), '../rack-test/lib')
$:.unshift File.join(File.dirname(__FILE__), '../timecop/lib')

require 'sinatra'
require 'coquelicot'
require 'spec'
require 'rack/test'
require 'timecop'
require 'hpricot'
require 'tmpdir'

UPLOAD_PASSWORD = 'secret'

set :environment, :test
set :upload_password, Digest::SHA1.hexdigest(UPLOAD_PASSWORD)

describe 'Coquelicot' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

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

  before do
    Depot.instance.path = Dir.mktmpdir('coquelicot') #"#{Time.now.to_f}"
  end

  after do
    FileUtils.remove_entry_secure Depot.instance.path
  end

  it "should offer an upload form" do
    get '/'
    last_response.should be_ok
    doc = Hpricot(last_response.body)
    (doc/"form#upload").should have(1).items
  end

  it "should allow retrieval of an uploaded file" do
    url = upload
    get url
    last_response.should be_ok
    last_response['Content-Type'].should eql('text/x-script.ruby')
    last_response.body.should eql(File.new(__FILE__).read)
  end

  it "should correctly set Last-Modified header when downloading" do
    url = upload
    get url
    last_modified = last_response['Last-Modified']
    last_modified.should_not be_nil
    get url
    last_response['Last-Modified'].should eql(last_modified)
  end

  it "should prevent upload without a password" do
    url = upload :upload_password => ''
    url.should be_nil
    last_response.status.should eql(403)
  end

  it "should prevent upload with a wrong password" do
    url = upload :upload_password => "bad"
    url.should be_nil
    last_response.status.should eql(403)
  end

  it "should not store an uploaded file in cleartext" do
    upload
    files = Dir.glob("#{Depot.instance.path}/*")
    files.should have(1).items
    File.new(files[0]).read().should_not include('should not store an uploaded file')
  end

  it "should generate a random URL to retrieve a file" do
    url = upload
    url.should_not include(File.basename(__FILE__))
  end

  it "should store files with a different name than then one in URL" do
    url = upload
    url_name = url.split('/')[-1]
    files = Dir.glob("#{Depot.instance.path}/*")
    files.should have(1).items
    url_name.should_not eql(File.basename(files[0]))
  end

  it "should encode the encryption key in URL when no password has been specified" do
    url = upload
    url_name = url.split('/')[-1]
    url_name.split('-').should have(2).items
  end

  it "should not encode the encryption key in URL when a password has been specified" do
    url = upload :file_key => 'somethingSecret'
    url_name = url.split('/')[-1]
    url_name.split('-').should have(1).items
  end

  it "should only allow one time download to be retrieved once" do
    url = upload :one_time => true
    get url
    last_response.should be_ok
    last_response['Content-Type'].should eql('text/x-script.ruby')
    last_response.body.should eql(File.new(__FILE__).read)
    get url
    last_response.status.should eql(410)
  end

  it "should allow retrieval of a password protected file" do
    url = upload :file_key => 'somethingSecret'
    get url
    last_response.should be_ok
    doc = Hpricot(last_response.body)
    (doc/'input#file_key').should have(1).items
    url = (doc/'form')[0].attributes['action']
    post url, :file_key => 'somethingSecret'
    last_response.should be_ok
    last_response['Content-Type'].should eql('text/x-script.ruby')
    last_response.body.should eql(File.new(__FILE__).read)
  end

  it "should not allow retrieval of a password protected file without the password" do
    url = upload :file_key => 'somethingSecret'
    get url
    last_response.should be_ok
    last_response['Content-Type'].should_not eql('text/x-script.ruby')
    post url
    last_response.status.should eql(403)
  end

  it "should not allow retrieval of a password protected file with a wrong password" do
    url = upload :file_key => 'somethingSecret'
    post url, :file_key => 'BAD'
    last_response.status.should eql(403)
  end

  it "should not allow retrieval after the time limit has expired" do
    url = upload :expire => 60 # 1 hour
    # let's be tomorrow
    Timecop.travel(Date.today + 1) do
      get url
      last_response.status.should eql(410)
    end
  end

  it "should cleanup expired files" do
    url = upload :expire => 60, :file_key => 'test' # 1 hour
    url_name = url.split('/')[-1]
    Dir.glob("#{Depot.instance.path}/*").should have(1).items
    # let's be tomorrow
    Timecop.travel(Date.today + 1) do
      Depot.instance.gc!
      files = Dir.glob("#{Depot.instance.path}/*")
      files.should have(1).items
      File.lstat(files[0]).size.should eql(0)
      Depot.instance.get_file(url_name).expired?.should be_true
    end
    # let's be after 'gone' period
    Timecop.travel(Time.now + (Depot.instance.gone_period * 60)) do
      Depot.instance.gc!
      Dir.glob("#{Depot.instance.path}/*").should have(0).items
      Depot.instance.get_file(url_name).should be_nil
    end
  end

  it "should map extra base32 characters to filenames" do
    url = upload :expire => 60 # 1 hour
    splitted = url.split('/')
    name = splitted[-1].upcase.gsub(/O/, '0').gsub(/L/, '1')
    get "#{splitted[0..-2].join '/'}/#{name}"
    last_response.should be_ok
    last_response['Content-Type'].should eql('text/x-script.ruby')
  end
end
