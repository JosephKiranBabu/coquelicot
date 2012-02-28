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
  include Capybara::DSL
  Capybara.app = Coquelicot::Application

  include_context 'with Coquelicot::Application'

  describe 'get /README' do
    before do
      visit '/README'
    end
    it 'should display the README file' do
      title = File.open(File.expand_path('../../../README', __FILE__)) { |f| f.readline.strip }
      find('h1').should have_content(title)
    end
  end
end
