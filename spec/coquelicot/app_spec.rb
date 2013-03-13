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
        find(:xpath, '//label[@for="file"]').
            should have_content("max. size: #{Coquelicot.settings.max_file_size.as_size}")
      end
      context 'when I explicitly request french' do
        it 'should display a page in french' do
          visit '/'
          click_link 'fr'
          page.should have_content('Partager')
          reset_session!
        end
        # will fail without ordered Hash, see:
        # <https://github.com/jnicklas/capybara/issues/670>
        context 'when I upload an empty file', :if => RUBY_VERSION >= '1.9' do
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
            page.should have_content('Le fichier est vide')
          end
        end
      end
    end
    context 'when my browser prefers french' do
      include_context 'browser prefers french'
      context 'when I do nothing special' do
        it 'should display a page in french' do
          visit '/'
          page.should have_content('Partager')
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
            page.should have_content('1 Kio')
          end
          # will fail without ordered Hash, see:
          # <https://github.com/jnicklas/capybara/issues/670>
          context 'when I upload something bigger', :if => RUBY_VERSION >= '1.9' do
            before do
              visit '/'
              fill_in 'upload_password', :with => upload_password
              attach_file 'file', __FILE__
              click_button 'submit'
            end
            it 'should display an error in french' do
              page.should have_content('plus gros que la taille maximale')
            end
          end
        end
        # will fail without ordered Hash, see:
        # <https://github.com/jnicklas/capybara/issues/670>
        context 'when I upload an empty file', :if => RUBY_VERSION >= '1.9' do
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
            page.should have_content('Le fichier est vide')
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
          page.should have_content('Verteile')
        end
	# will fail without ordered Hash, see:
	# <https://github.com/jnicklas/capybara/issues/670>
        context 'after an upload', :if => RUBY_VERSION >= '1.9' do
          before do
            fill_in 'upload_password', :with => upload_password
            attach_file 'file', __FILE__
            click_button 'submit'
          end
          it 'should display a page in german' do
            page.should have_content('Verteile eine weitere Datei')
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
          find('.about').text.should == 'This is an about text'
        end
      end
      context 'when I explicitly request French' do
        it 'should display the "about text" in French' do
          visit '/'
          click_link 'fr'
          find('.about').text.should == 'Ceci est un texte'
          reset_session!
        end
      end
      context 'when my browser prefers french' do
        include_context 'browser prefers french'
        it 'should display the "about text" in French' do
          visit '/'
          find('.about').text.should == 'Ceci est un texte'
        end
      end
    end
    context 'when a local Git repository is usable' do
      before(:each) do
        # Might be pretty brittle… but will do for now
        Coquelicot::Helpers.module_eval('remove_class_variable :@@can_provide_git_repository if defined? @@can_provide_git_repository')
        File.stub(:readable?).and_return(true)
      end
      it 'should offer a "git clone" to the local URI' do
        visit '/'
        find('#footer').should have_content('git clone http://www.example.com/coquelicot.git')
      end
    end
    context 'when a local Git repository is not usable' do
      before(:each) do
        # Might be pretty brittle… but will do for now
        Coquelicot::Helpers.module_eval('remove_class_variable :@@can_provide_git_repository')
        File.stub(:readable?) do |p|
          p.end_with?('.git')
        end
      end
      it 'should offer a link to retrieve the source' do
        visit '/'
        find('#footer').text.should =~ /curl.*gem unpack.*\.gem$/
      end
      it 'should log a warning' do
        logger = double('Logger')
        logger.should_receive(:warn).with(/Unable to provide access to local Git repository/)
        app.any_instance.stub(:logger).and_return(logger)
        visit '/'
      end
      it 'should log a warning only on the first request' do
        logger = double('Logger')
        logger.should_receive(:warn).once
        app.any_instance.stub(:logger).and_return(logger)
        visit '/'
        visit '/'
      end
    end
    context 'when there is no local Git repository' do
      before(:each) do
        # Might be pretty brittle… but will do for now
        Coquelicot::Helpers.module_eval('remove_class_variable :@@can_provide_git_repository')
        File.stub(:readable?).and_return(false)
      end
      it 'should offer a link to retrieve the source' do
        visit '/'
        find('#footer').text.should =~ /curl.*gem unpack.*\.gem$/
      end
    end
  end

  describe 'get /README' do
    before do
      visit '/README'
    end
    it 'should display the README file' do
      title = File.open(File.expand_path('../../../README', __FILE__)) { |f| f.readline.strip }
      find('h1').should have_content(title)
    end
  end

  describe 'get /about-your-data' do
    it 'should display some info about data retention' do
      visit '/about-your-data'
      find('h1').should have_content('About your data…')
    end
    context 'when using SSL' do
      it 'should notice the connection is encrypted' do
        visit 'https://example.com/about-your-data'
        page.should have_content('Exchanges between your computer and example.com are encrypted.')
      end
    end
    context 'when not using SSL' do
      it 'should notice the connection is encrypted' do
        visit 'http://example.com/about-your-data'
        page.should_not have_content('Exchanges between your computer and example.org are encrypted.')
      end
    end
  end

  describe 'get /source' do
    context 'when the server hostname is one-cool-hostname' do
      before(:each) do
        Coquelicot::Helpers.module_eval('remove_class_variable :@@hostname if defined? @@hostname')
        Socket.stub(:gethostname).and_return('one-cool-hostname')
        visit '/source'
      end
      it 'should send a file to be saved' do
        page.response_headers['Content-Type'].should == 'application/octet-stream'
        page.response_headers['Content-Disposition'].should =~ /^attachment;/
      end
      it 'should send a file with a proposed name correct for coquelicot gem' do
        page.response_headers['Content-Disposition'].should =~ /filename="coquelicot-.*\.gem"/
      end
      context 'the downloaded gem' do
        around(:each) do |example|
          Gem::Package.open(StringIO.new(page.driver.response.body)) do |gem|
            @gem = gem
            example.run
          end
        end
        it 'should be named "coquelicot"' do
          @gem.metadata.name.should == 'coquelicot'
        end
        it "should have a version containing 'onecoolhostname' for the hostname" do
          @gem.metadata.version.to_s.should =~ /\.onecoolhostname\./
        end
        it "should have a version containing today's date" do
          Timecop.freeze(Time.now) do
            date_str = Date.today.strftime('%Y%m%d')
            @gem.metadata.version.to_s.should =~ /\.#{date_str}$/
          end
        end
        it 'should at least contain this spec file' do
          this_file = __FILE__.gsub(/^.*\/spec/, 'spec')
          content = nil
          @gem.each do |file|
            content = file.read if file.full_name.end_with?(this_file)
          end
          content.should == File.open(__FILE__, 'rb').read
        end
      end
    end
  end

  describe 'post /authenticate' do
    context 'when given a request with too much input' do
      before do
        # README is bigger than 5 kiB
        path = File.expand_path('../../../README', __FILE__)
        post '/authenticate', :file => Rack::Test::UploadedFile.new(path, 'text/plain')
      end
      it 'should get status 413 (Request entity too large)' do
        last_response.status.should == 413
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
      stderr.should =~ /Usage:/
    end
  end
  context 'when using "-h"' do
    it 'should display help and exit' do
      stderr = capture(:stderr) do
        expect { Coquelicot.run! %w{-h} }.to raise_error(SystemExit)
      end
      stderr.should =~ /Usage:/
    end
  end
  context 'when using "-c <settings.yml>"' do
    it 'should use the given setting file' do
      settings_file = File.expand_path('../../../conf/settings-default.yml', __FILE__)
      Coquelicot::Application.should_receive(:config_file).with(settings_file)
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
        Coquelicot.settings.depot_path.should == '/nonexistent'
      end
    end
    context 'when the given settings file does not exist' do
      it 'should display an error' do
        stderr = capture(:stderr) do
          expect { Coquelicot.run! %w{-c non-existent.yml} }.to raise_error(SystemExit)
        end
        stderr.should =~ /cannot access/
      end
    end
  end
  context 'when given an invalid option' do
    it 'should display an error' do
      stderr = capture(:stderr) do
        expect { Coquelicot.run! %w{--invalid-option} }.to raise_error(SystemExit)
      end
      stderr.should =~ /not a valid option/
    end
  end
  context 'when given "whatever"' do
    it 'should display an error' do
      stderr = capture(:stderr) do
        expect { Coquelicot.run! %w{whatever} }.to raise_error(SystemExit)
      end
      stderr.should =~ /not a valid command/
    end
  end
  shared_context 'command accepts options' do
    context 'when given "--help" option' do
      it 'should display help and exit' do
        stderr = capture(:stderr) do
          expect { Coquelicot.run!([command, '--help']) }.to raise_error(SystemExit)
        end
        stderr.should =~ /Usage:/
      end
    end
    context 'when given an invalid option' do
      it 'should display an error' do
        stderr = capture(:stderr) do
          expect { Coquelicot.run!([command, '--invalid-option']) }.to raise_error(SystemExit)
        end
        stderr.should =~ /not a valid option/
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
        ::Unicorn::Launcher.should_receive(:daemonize!)
        ::Rainbows::HttpServer.stub(:new).and_return(double('HttpServer').as_null_object)
        Coquelicot.run! %w{start}
      end
      it 'should start the web server' do
        ::Unicorn::Launcher.stub(:daemonize!)
        server = double('HttpServer')
        server.should_receive(:start).and_return(double('Thread').as_null_object)
        ::Rainbows::HttpServer.stub(:new).and_return(server)
        Coquelicot.run! %w{start}
      end
    end
    context 'when given the --no-daemon option' do
      it 'should not daemonize' do
        ::Unicorn::Launcher.should_receive(:daemonize!).never
        ::Rainbows::HttpServer.stub(:new).and_return(double('HttpServer').as_null_object)
        Coquelicot.run! %w{start --no-daemon}
      end
      it 'should set the default configuration' do
        app.set :pid, @depot_path
        app.set :listen, ['127.0.0.1:42']
        ::Rainbows::HttpServer.any_instance.stub(:start) do
          server = ::Rainbows.server
          server.config.set[:pid].should == @depot_path
          server.config.set[:listeners].should == ['127.0.0.1:42']
          double('Thread').as_null_object
        end
        Coquelicot.run! %w{start --no-daemon}
      end
      it 'should start the web server' do
        server = double('HttpServer')
        server.should_receive(:start).and_return(double('Thread').as_null_object)
        ::Rainbows::HttpServer.stub(:new).and_return(server)
        Coquelicot.run! %w{start --no-daemon}
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
        Process.should_receive(:kill).with(:TERM, pid)
        Coquelicot.run! %w{stop}
      end
    end
    context 'when the pid file does not exist' do
      it 'should error out' do
        app.set :pid, '/nonexistent'
        stderr = capture(:stderr) do
          expect { Coquelicot.run! %w{stop} }.to raise_error(SystemExit)
        end
        stderr.should =~ /Unable to read/
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
        stderr.should =~ /Bad PID file/
      end
    end
  end
  context 'when given "gc"' do
    let(:command) { 'gc' }
    include_context 'command accepts options'

    it 'should call gc!' do
      Coquelicot.depot.should_receive(:gc!).once
      Coquelicot.run! %w{gc}
    end
  end
  context 'when given "migrate-jyraphe"' do
    let(:args) { %w{all args} }
    it 'should call the migrator' do
      Coquelicot::JyrapheMigrator.should_receive(:run!).with(args)
      Coquelicot.run!(%w{migrate-jyraphe} + args)
    end
  end
end
