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

Given(/^the LDAP server knows "([^"]*)" identified with "([^"]*)"$/) do |user, password|
  allow(Coquelicot.settings).to receive_messages(
    :ldap_server => 'example.org', :ldap_port => 389, :ldap_base => 'dc=example,dc=com')
  ldap = double('Net::LDAP').as_null_object
  allow(ldap).to receive(:bind_as) do |options|
    double('Net::LDAP::PDU') if options[:filter] == "(uid=#{Net::LDAP::Filter.escape(user)})" && options[:password] == password
  end
  allow(Net::LDAP).to receive(:new).and_return(ldap)
end

Given(/^I have entered "([^"]*)" as LDAP login$/) do |login|
  visit '/'
  fill_in :ldap_user, :with => login
end

Given(/^I have entered "([^"]*)" as LDAP password$/) do |password|
  fill_in :ldap_password, :with => password
end

