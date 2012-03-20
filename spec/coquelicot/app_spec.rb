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

  describe 'get /' do
    before do
      visit '/'
    end
    it 'should display the maximum file size' do
      find(:xpath, '//label[@for="file"]/following::*[@class="note"]').
          should have_content("Max. size: #{Coquelicot.settings.max_file_size.as_size}")
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
