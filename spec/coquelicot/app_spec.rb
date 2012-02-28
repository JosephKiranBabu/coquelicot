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
require 'capybara/dsl'

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
