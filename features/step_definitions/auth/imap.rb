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

require 'net/imap'

Given(/^the IMAP server knows "([^"]*)" identified with "([^"]*)"$/) do |user, password|
  allow(Coquelicot.settings).to receive(:imap_server).and_return('example.org')
  allow(Coquelicot.settings).to receive(:imap_port).and_return(993)
  imap = double('Net::Imap').as_null_object
  allow(imap).to receive(:login) do |u, p|
    raise Net::IMAP::NoResponseError.new(Net::IMAP::TaggedResponse.new(nil, nil, Net::IMAP::ResponseText.new(nil, :text => 'Login failed.'))) unless u == user && p == password
  end
  allow(Net::IMAP).to receive(:new).and_return(imap)
end

When(/^I try to upload a file without a login$/) do
  visit '/'
  attach_file 'file', __FILE__
  click_button 'Share!'
end

Given(/^I have entered "([^"]*)" as IMAP login$/) do |login|
  visit '/'
  fill_in :imap_user, :with => login
end

Given(/^I have entered "([^"]*)" as IMAP password$/) do |password|
  fill_in :imap_password, :with => password
end
