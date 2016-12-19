# -*- coding: UTF-8 -*-
# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2016 potager.org <jardiniers@potager.org>
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

require 'bcrypt'

Given(/^the config file describes an account "([^"]*)" identified with "([^"]*)"$/) do |user, password|
  @credentials = {} if @credentials.nil?

  allow(Coquelicot.settings).to receive_messages(
      :credentials => { user => BCrypt::Password.create(password).to_s })
end

Given(/^I have entered "([^"]*)" as user login$/) do |login|
  visit '/'
  fill_in :upload_user, :with => login
end

Given(/^I have entered "([^"]*)" as user password$/) do |password|
  fill_in :upload_password, :with => password
end
