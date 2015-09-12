# -*- coding: UTF-8 -*-
# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2015 potager.org <jardiniers@potager.org>
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

require File.expand_path('../../../spec/spec_helper', __FILE__)
require 'timecop'
require 'capybara/cucumber'
require 'cucumber/rspec/doubles'

def default_upload_password
  'secret'
end

class CoquelicotWorld
  include RSpec::Expectations
  include RSpec::Matchers
  include Capybara::DSL
  Capybara.app = Coquelicot::Application

  Capybara.app.set :environment, :test

  def upload(path, options={})
    visit '/'
    fill_in 'upload_password', :with => default_upload_password
    options.each_pair do |field, value|
      fill_in field, :with => value
    end
    attach_file 'file', path
    click_button 'Share!'
    @uploaded_file = path
    @upload_time = Time.now
  end
end

World do
  CoquelicotWorld.new
end
