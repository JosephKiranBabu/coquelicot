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

Given(/^the upload password is set to "([^"]*)"$/) do |upload_password|
  allow(Coquelicot.settings).to receive(:upload_password).and_return(Digest::SHA1.hexdigest(upload_password))
end

When(/^I try to upload a file without an upload password$/) do
  visit '/'
  attach_file 'file', __FILE__
  click_button 'Share!'
end

Given(/^I have entered "([^"]*)" as the upload password$/) do |password|
  visit '/'
  fill_in 'upload_password', :with => password
end
