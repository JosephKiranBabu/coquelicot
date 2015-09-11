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
require 'coquelicot/jyraphe_migrator'
require 'capybara/dsl'
require 'tempfile'
require 'timecop'

describe Coquelicot::Application do
  include Rack::Test::Methods
  include Capybara::DSL
  Capybara.app = Coquelicot::Application

  include_context 'with Coquelicot::Application'

  def upload_password
    'secret'
  end

  before(:each) do
    app.set :authentication_method, :name => :simplepass,
                                    :upload_password => Digest::SHA1.hexdigest(upload_password)
  end

  shared_context 'browser prefers french' do
    around do |example|
      begin
        page.driver.header 'Accept-Language',  'fr-fr;q=1.0, en-gb;q=0.8, en;q=0.7'
        example.run
      ensure
        page.driver.header 'Accept-Language', nil
        reset_session!
      end
    end
  end

  describe 'get /' do
    context 'using the default language' do
      it 'should display the maximum file size' do
        visit '/'
        expect(find(:xpath, '//label[@for="file"]')).
            to have_content("max. size: #{Coquelicot.settings.max_file_size.as_size}")
      end
      context 'when I explicitly request french' do
        it 'should display a page in french' do
          visit '/'
          click_link 'fr'
          expect(page).to have_content('Partager')
          reset_session!
        end
        context 'when I upload an empty file' do
          around do |example|
            file = Tempfile.new('coquelicot')
            begin
              visit '/'
              click_link 'fr'
              fill_in 'upload_password', :with => upload_password
              attach_file 'file', file.path
              click_button 'submit'
              example.run
            ensure
              file.close!
              reset_session!
            end
          end
          it 'should display an error in french' do
            expect(page).to have_content('Le fichier est vide')
          end
        end
      end
    end
    context 'when my browser prefers french' do
      include_context 'browser prefers french'
      context 'when I do nothing special' do
        it 'should display a page in french' do
          visit '/'
          expect(page).to have_content('Partager')
        end
        context 'when the max upload size is 1 KiB' do
          around do |example|
            begin
              max_file_size = app.max_file_size
              app.set :max_file_size, 1024
              example.run
            ensure
              app.set :max_file_size, max_file_size
            end
          end
          it 'should display "1 Kio" as the max upload size' do
            visit '/'
            expect(page).to have_content('1 Kio')
          end
          context 'when I upload something bigger' do
            before do
              visit '/'
              fill_in 'upload_password', :with => upload_password
              attach_file 'file', __FILE__
              click_button 'submit'
            end
            it 'should display an error in french' do
              expect(page).to have_content('plus gros que la taille maximale')
            end
          end
        end
        # will fail without ordered Hash, see:
        # <https://github.com/jnicklas/capybara/issues/670>
        context 'when I upload an empty file' do
          around do |example|
            file = Tempfile.new('coquelicot')
            begin
              visit '/'
              fill_in 'upload_password', :with => upload_password
              attach_file 'file', file.path
              click_button 'submit'
              example.run
            ensure
              file.close!
            end
          end
          it 'should display an error in french' do
            expect(page).to have_content('Le fichier est vide')
          end
        end
      end
      context 'when I explicitly request german' do
        around(:each) do |example|
          visit '/'
          click_link 'de'
          example.run
          reset_session!
        end
        it 'should display a page in german' do
          expect(page).to have_content('Verteile')
        end
	# will fail without ordered Hash, see:
	# <https://github.com/jnicklas/capybara/issues/670>
        context 'after an upload' do
          before do
            fill_in 'upload_password', :with => upload_password
            attach_file 'file', __FILE__
            click_button 'submit'
          end
          it 'should display a page in german' do
            expect(page).to have_content('Verteile eine weitere Datei')
          end
        end
      end
    end
    context 'when an "about text" is set for English and French"' do
      before(:each) do
        app.set :about_text, 'en' => 'This is an about text',
                             'fr' => 'Ceci est un texte'
      end
      context 'using the default language' do
        it 'should display the "about text" in English' do
          visit '/'
          expect(find('.about').text).to be == 'This is an about text'
        end
      end
      context 'when I explicitly request French' do
        it 'should display the "about text" in French' do
          visit '/'
          click_link 'fr'
          expect(find('.about').text).to be == 'Ceci est un texte'
          reset_session!
        end
      end
      context 'when my browser prefers french' do
        include_context 'browser prefers french'
        it 'should display the "about text" in French' do
          visit '/'
          expect(find('.about').text).to be == 'Ceci est un texte'
        end
      end
    end
    context 'when a local Git repository is usable' do
      before(:each) do
        # Might be pretty brittle… but will do for now
        Coquelicot::Helpers.module_eval('remove_class_variable :@@can_provide_git_repository if defined? @@can_provide_git_repository')
        allow(File).to receive(:readable?).and_return(true)
      end
      it 'should offer a "git clone" to the local URI' do
        visit '/'
        expect(find('#footer')).to have_content('git clone http://www.example.com/coquelicot.git')
      end
    end
    context 'when a local Git repository is not usable' do
      before(:each) do
        # Might be pretty brittle… but will do for now
        Coquelicot::Helpers.module_eval('remove_class_variable :@@can_provide_git_repository')
        allow(File).to receive(:readable?) { |p| p.end_with?('.git') }
      end
      it 'should offer a link to retrieve the source' do
        visit '/'
        expect(find('#footer').text).to match /curl.*gem unpack.*\.gem$/
      end
      it 'should log a warning' do
        logger = double('Logger')
        expect(logger).to receive(:warn).with(/Unable to provide access to local Git repository/)
        allow_any_instance_of(app).to receive(:logger).and_return(logger)
        visit '/'
      end
      it 'should log a warning only on the first request' do
        logger = double('Logger')
        expect(logger).to receive(:warn).once
        allow_any_instance_of(app).to receive(:logger).and_return(logger)
        visit '/'
        visit '/'
      end
    end
    context 'when there is no local Git repository' do
      before(:each) do
        # Might be pretty brittle… but will do for now
        Coquelicot::Helpers.module_eval('remove_class_variable :@@can_provide_git_repository')
        allow(File).to receive(:readable?).and_return(false)
      end
      it 'should offer a link to retrieve the source' do
        visit '/'
        expect(find('#footer').text).to match /curl.*gem unpack.*\.gem$/
      end
    end
  end

  describe 'get /README' do
    before do
      visit '/README'
    end
    it 'should display the README file' do
      title = File.open(File.expand_path('../../../README', __FILE__)) { |f| f.readline.strip }
      expect(find('h1')).to have_content(title)
    end
  end

  describe 'get /about-your-data' do
    it 'should display some info about data retention' do
      visit '/about-your-data'
      expect(find('h1')).to have_content('About your data…')
    end
    context 'when using SSL' do
      it 'should notice the connection is encrypted' do
        visit 'https://example.com/about-your-data'
        expect(page).to have_content('Exchanges between your computer and example.com are encrypted.')
      end
    end
    context 'when not using SSL' do
      it 'should notice the connection is encrypted' do
        visit 'http://example.com/about-your-data'
        expect(page).to_not have_content('Exchanges between your computer and example.org are encrypted.')
      end
    end
  end

  describe 'get /source' do
    context 'when the server hostname is one-cool-hostname' do
      before(:each) do
        Coquelicot::Helpers.module_eval('remove_class_variable :@@hostname if defined? @@hostname')
        allow(Socket).to receive(:gethostname).and_return('one-cool-hostname')
        visit '/source'
      end
      it 'should send a file to be saved' do
        expect(page.response_headers['Content-Type']).to be == 'application/octet-stream'
        expect(page.response_headers['Content-Disposition']).to match /^attachment;/
      end
      it 'should send a file with a proposed name correct for coquelicot gem' do
        expect(page.response_headers['Content-Disposition']).to match /filename="coquelicot-.*\.gem"/
      end
      if defined? Gem::Package.new
        context 'the downloaded gem' do
          around(:each) do |example|
            Tempfile.open('coquelicot-downloaded-gem') do |gem_file|
              gem_file.write(page.driver.response.body)
              @gem = Gem::Package.new(gem_file.path)
              example.run
              gem_file.unlink
            end
          end
          it 'should be named "coquelicot"' do
            expect(@gem.spec.name).to be == 'coquelicot'
          end
          it "should have a version containing 'onecoolhostname' for the hostname" do
            expect(@gem.spec.version.to_s).to match /\.onecoolhostname\./
          end
          it "should have a version containing today's date" do
            Timecop.freeze(Time.now) do
              date_str = Date.today.strftime('%Y%m%d')
              expect(@gem.spec.version.to_s).to match /\.#{date_str}$/
            end
          end
          it 'should at least contain this spec file' do
            this_file = __FILE__.gsub(/^.*\/spec/, 'spec')
            content = nil
            @gem.spec.files.each do |file|
              content = File.read(file, :encoding => 'binary') if file.end_with?(this_file)
            end
            expect(content).to be == File.read(__FILE__, :encoding => 'binary')
          end
        end
      else
        context 'the downloaded gem' do
          around(:each) do |example|
            Gem::Package.open(StringIO.new(page.driver.response.body)) do |gem|
              @gem = gem
              example.run
            end
          end
          it 'should be named "coquelicot"' do
            expect(@gem.metadata.name).to be == 'coquelicot'
          end
          it "should have a version containing 'onecoolhostname' for the hostname" do
            expect(@gem.metadata.version.to_s).to match /\.onecoolhostname\./
          end
          it "should have a version containing today's date" do
            Timecop.freeze(Time.now) do
              date_str = Date.today.strftime('%Y%m%d')
              expect(@gem.metadata.version.to_s).to match /\.#{date_str}$/
            end
          end
          it 'should at least contain this spec file' do
            this_file = __FILE__.gsub(/^.*\/spec/, 'spec')
            content = nil
            @gem.each do |file|
              content = file.read if file.full_name.end_with?(this_file)
            end
            expect(content).to be == File.open(__FILE__, 'rb').read
          end
        end
      end
    end
  end

  describe 'post /authenticate' do
    context 'when given a request with too much input' do
      before do
        # background image is bigger than 5 kiB
        path = File.expand_path('../../../public/images/background.jpg', __FILE__)
        post '/authenticate', :file => Rack::Test::UploadedFile.new(path, 'text/plain')
      end
      it 'should get status 413 (Request entity too large)' do
        expect(last_response.status).to be == 413
      end
    end
  end
end

describe Coquelicot, '.run!' do
  include_context 'with Coquelicot::Application'

  context 'when given no option' do
    it 'should display help and exit' do
      stderr = capture(:stderr) do
        expect { Coquelicot.run! %w{} }.to raise_error(SystemExit)
      end
      expect(stderr).to match /Usage:/
    end
  end
  context 'when using "-h"' do
    it 'should display help and exit' do
      stderr = capture(:stderr) do
        expect { Coquelicot.run! %w{-h} }.to raise_error(SystemExit)
      end
      expect(stderr).to match /Usage:/
    end
  end
  context 'when using "-c <settings.yml>"' do
    it 'should use the given setting file' do
      settings_file = File.expand_path('../../../conf/settings-default.yml', __FILE__)
      expect(Coquelicot::Application).to receive(:config_file).with(settings_file)
      stderr = capture(:stderr) do
        expect { Coquelicot.run! ['-c', settings_file] }.to raise_error(SystemExit)
      end
    end
    context 'when the given settings file exists' do
      around(:each) do |example|
        settings = Tempfile.new('coquelicot')
        begin
          settings.write(YAML.dump({ 'depot_path' => '/nonexistent' }))
          settings.close
          @settings_path = settings.path
          example.run
        ensure
          settings.unlink
        end
      end
      it 'should use the depot path defined in the given settings' do
        # We don't give a command, so exit is expected
        stderr = capture(:stderr) do
          expect { Coquelicot.run! ['-c', @settings_path] }.to raise_error(SystemExit)
        end
        expect(Coquelicot.settings.depot_path).to be == '/nonexistent'
      end
    end
    context 'when the given settings file does not exist' do
      it 'should display an error' do
        stderr = capture(:stderr) do
          expect { Coquelicot.run! %w{-c non-existent.yml} }.to raise_error(SystemExit)
        end
        expect(stderr).to match /cannot access/
      end
    end
  end
  context 'when given an invalid option' do
    it 'should display an error' do
      stderr = capture(:stderr) do
        expect { Coquelicot.run! %w{--invalid-option} }.to raise_error(SystemExit)
      end
      expect(stderr).to match /not a valid option/
    end
  end
  context 'when given "whatever"' do
    it 'should display an error' do
      stderr = capture(:stderr) do
        expect { Coquelicot.run! %w{whatever} }.to raise_error(SystemExit)
      end
      expect(stderr).to match /not a valid command/
    end
  end
  shared_context 'command accepts options' do
    context 'when given "--help" option' do
      it 'should display help and exit' do
        stderr = capture(:stderr) do
          expect { Coquelicot.run!([command, '--help']) }.to raise_error(SystemExit)
        end
        expect(stderr).to match /Usage:/
      end
    end
    context 'when given an invalid option' do
      it 'should display an error' do
        stderr = capture(:stderr) do
          expect { Coquelicot.run!([command, '--invalid-option']) }.to raise_error(SystemExit)
        end
        expect(stderr).to match /not a valid option/
      end
    end
  end
  context 'when given "start"' do
    let(:command) { 'start' }
    include_context 'command accepts options'

    before(:each) do
      # :stdout_path and :stderr_path should not be set, otherwise RSpec will break!
      app.set :log, nil
    end
    context 'with default options' do
      it 'should daemonize' do
        expect(::Unicorn::Launcher).to receive(:daemonize!)
        allow(::Rainbows::HttpServer).to receive(:new).and_return(double('HttpServer').as_null_object)
        Coquelicot.run! %w{start}
      end
      it 'should start the web server' do
        allow(::Unicorn::Launcher).to receive(:daemonize!)
        server = double('HttpServer')
        expect(server).to receive(:start).and_return(double('Thread').as_null_object)
        allow(::Rainbows::HttpServer).to receive(:new).and_return(server)
        Coquelicot.run! %w{start}
      end
    end
    context 'when given the --no-daemon option' do
      it 'should not daemonize' do
        expect(::Unicorn::Launcher).to receive(:daemonize!).never
        allow(::Rainbows::HttpServer).to receive(:new).and_return(double('HttpServer').as_null_object)
        Coquelicot.run! %w{start --no-daemon}
      end
      it 'should set the default configuration' do
        app.set :pid, @depot_path
        app.set :listen, ['127.0.0.1:42']
        allow_any_instance_of(::Rainbows::HttpServer).to receive(:start) do
          server = ::Rainbows.server
          expect(server.config.set[:pid]).to be == @depot_path
          expect(server.config.set[:listeners]).to be == ['127.0.0.1:42']
          double('Thread').as_null_object
        end
        Coquelicot.run! %w{start --no-daemon}
      end
      it 'should start the web server' do
        server = double('HttpServer')
        expect(server).to receive(:start).and_return(double('Thread').as_null_object)
        allow(::Rainbows::HttpServer).to receive(:new).and_return(server)
        Coquelicot.run! %w{start --no-daemon}
      end
    end
    context 'when the path setting is set to /coquelicot' do
      before(:each) do
        app.set :log, nil
        $stderr = StringIO.new
        app.set :path, '/coquelicot'
      end
      it 'should map the application to /coquelicot' do
        allow(::Unicorn::Launcher).to receive(:daemonize!)
        allow(Coquelicot).to receive(:monkeypatch_half_close)
        allow(::Rainbows::HttpServer).to receive(:new) do |app, opts|
          session = Rack::Test::Session.new(app.call)
          session.get('/coquelicot/')
          expect(session.last_response).to be_ok
          expect(session.last_response.body).to match /Coquelicot/
          session.get('/')
          expect(session.last_response.status).to eql(404)
          double('HttpServer').as_null_object
        end
        Coquelicot.run! %w{start}
      end
    end
  end
  context 'when given "stop"' do
    let(:command) { 'stop' }
    include_context 'command accepts options'

    context 'when the pid file is correct' do
      let(:pid) { 42 }
      before(:each) do
        File.open("#{@depot_path}/pid", 'w') do |f|
          f.write(pid.to_s)
        end
        app.set :pid, "#{@depot_path}/pid"
      end
      it 'should stop the web server' do
        expect(Process).to receive(:kill).with(:TERM, pid)
        Coquelicot.run! %w{stop}
      end
    end
    context 'when the pid file does not exist' do
      it 'should error out' do
        app.set :pid, '/nonexistent'
        stderr = capture(:stderr) do
          expect { Coquelicot.run! %w{stop} }.to raise_error(SystemExit)
        end
        expect(stderr).to match /Unable to read/
      end
    end
    context 'when the pid file contains garbage' do
      before(:each) do
        File.open("#{@depot_path}/pid", 'w') do |f|
          f.write('The queerest of the queer')
        end
        app.set :pid, "#{@depot_path}/pid"
      end
      it 'should errour out' do
        stderr = capture(:stderr) do
          expect { Coquelicot.run! %w{stop} }.to raise_error(SystemExit)
        end
        expect(stderr).to match /Bad PID file/
      end
    end
  end
  context 'when given "gc"' do
    let(:command) { 'gc' }
    include_context 'command accepts options'

    it 'should call gc!' do
      expect(Coquelicot.depot).to receive(:gc!).once
      Coquelicot.run! %w{gc}
    end
  end
  context 'when given "migrate-jyraphe"' do
    let(:args) { %w{all args} }
    it 'should call the migrator' do
      expect(Coquelicot::JyrapheMigrator).to receive(:run!).with(args)
      Coquelicot.run!(%w{migrate-jyraphe} + args)
    end
  end
end
