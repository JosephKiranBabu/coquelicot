# -*- coding: UTF-8 -*-
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

  describe 'get /' do
    context 'using the default language' do
      before do
        visit '/'
      end
      it 'should display the maximum file size' do
        find(:xpath, '//label[@for="file"]/following::*[@class="note"]').
            should have_content("Max. size: #{Coquelicot.settings.max_file_size.as_size}")
      end
      context 'when I explicitly request french' do
        before do
          click_link 'fr'
        end
        it 'should display a page in french' do
          page.should have_content('Partager')
        end
      end
    end
    context 'when my browser prefers french' do
      around do |example|
        begin
          page.driver.header 'Accept-Language',  'fr-fr;q=1.0, en-gb;q=0.8, en;q=0.7'
          example.run
        ensure
          page.driver.header 'Accept-Language', nil
        end
      end
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

describe Coquelicot, '.collect_garbage!' do
  context 'when given no option' do
    include_context 'with Coquelicot::Application'

    it 'should use the default depot path' do
      Coquelicot::Depot.should_receive(:new).
        with(@depot_path).
        and_return(double.as_null_object)
      Coquelicot.collect_garbage!
    end
    it 'should call gc!' do
      depot = double('Depot').as_null_object
      depot.should_receive(:gc!)
      Coquelicot::Depot.stub(:new).and_return(depot)
      Coquelicot.collect_garbage!
    end
  end
  context 'when using "-c <settings.yml>"' do
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
      Coquelicot::Depot.should_receive(:new).
        with('/nonexistent').
        and_return(double.as_null_object)
      Coquelicot.collect_garbage! ['-c', @settings_path]
    end
    it 'should call gc!' do
      depot = double('Depot').as_null_object
      depot.should_receive(:gc!)
      Coquelicot::Depot.stub(:new).and_return(depot)
      Coquelicot.collect_garbage! ['-c', @settings_path]
    end
  end
  context 'when using "-h"' do
    it 'should display help and exit' do
      stderr = capture(:stderr) do
        expect { Coquelicot.collect_garbage! ['-h'] }.to raise_error(SystemExit)
      end
      stderr.should =~ /Usage:/
    end
    it 'should not call gc!' do
      depot = double('Depot').as_null_object
      depot.should_not_receive(:gc!)
      Coquelicot::Depot.stub(:new).and_return(depot)
      capture(:stderr) do
        expect { Coquelicot.collect_garbage! ['-h'] }.to raise_error(SystemExit)
      end
    end
  end
end

describe Coquelicot, '.migrate_jyraphe!' do
  it 'should call the migrator' do
    args = ['whatever']
    Coquelicot::JyrapheMigrator.should_receive(:run!).with(args)
    Coquelicot.migrate_jyraphe! args
  end
end
