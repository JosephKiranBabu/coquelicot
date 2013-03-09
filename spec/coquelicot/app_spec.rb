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
      context 'when an "about text" is set"' do
        before(:each) do
          app.set :about_text, 'This is an about text'
        end
        it 'should display the "about text"' do
          visit '/'
          page.should have_content('This is an about text')
        end
      end
      context 'when I explicitly request french' do
        it 'should display a page in french' do
          visit '/'
          click_link 'fr'
          page.should have_content('Partager')
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
        before do
          visit '/'
          click_link 'de'
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
