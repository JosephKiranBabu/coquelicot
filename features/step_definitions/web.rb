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

When(/^I visit the (?:main|upload) page$/) do
  visit '/'
end

Then(/^I should see a link to the French version$/) do
  expect(page).to have_link('fr')
end

Given(/^I am on the main page$/) do
  visit '/'
end

When(/^I follow the link to the French version$/) do
  click_link 'fr'
end

Then(/^the page should be in French$/) do
  expect(find_button('submit').value).to eql('Partager !')
end

Then(/^I see an URL to give to downloaders$/) do
  expect(find('textarea.ready').value).to start_with('http')
end

When(/^I download the file$/) do
  expect(@download_url).to be_truthy
  visit @download_url
end

When(/^I follow the download link$/) do
  visit(@download_url || find('textarea.ready').value)
end

When(/^I enter the link mixing up '(.)' and '(.)'$/) do |from, to|
  new_url = @download_url.gsub(from, to)
  visit new_url
end

When(/^I try to access a non\-existing file$/) do
  visit '/dhut7f73u2hiwwifwyrs-gs5wj3ixjheg6dg7'
end

Then(/^I should get a (\d+) error$/) do |code|
  expect(page.driver.response.status).to eql(code.to_i)
end

When(/^I enter the link with a bad decryption key$/) do
  name, key = File.basename(@download_url).split('-')
  visit "/#{name}-#{key.reverse}"
end

Then(/^I see a field to select how long the file will stay on the server$/) do
  expect(page).to have_field('expire')
end

When(/^I follow the download link two days later$/) do
  download_url = find('textarea.ready').value
  Timecop.travel(Date.today + 2) do
    Coquelicot.run!(%w{gc})
    visit download_url
  end
end

When(/^I follow the download link a month later$/) do
  download_url = find('textarea.ready').value
  Timecop.travel(Date.today + 31) do
    Coquelicot.run!(%w{gc})
    Coquelicot.run!(%w{gc}) # think "a couple of days"
    visit download_url
  end
end

Then(/^I'm told the file is gone$/) do
  expect(page.driver.response.status).to eql(410)
  expect(page).to have_content('expired')
end

Then(/^I'm told the file does not exist$/) do
  expect(page.driver.response.status).to eql(404)
  expect(page).to have_content('not found')
end

Then(/^the download URL does not contain the decryption key$/) do
  expect(find('textarea.ready').value).to_not include('-')
end

Then(/^I see a form to enter the download password$/) do
  expect(page).to have_content('Password:')
end

When(/^I enter "([^"]*)" as the download password$/) do |password|
  fill_in :file_key, :with => password
  click_on 'Get file'
end

Then(/^I'm told the password is wrong$/) do
  expect(page).to have_content('does not allow access')
  expect(page.driver.response.status).to eql(403)
end

Then(/^I see a checkbox labeled "([^"]*)"$/) do |label|
  label = find('label', :text => label)
  expect(page).to have_selector("##{label[:for]}")
end

Then(/^the upload is refused as empty$/) do
  expect(page.driver.response.status).to eql(403)
  expect(page).to have_content('no content')
end

Then(/^the upload is refused as too big$/) do
  expect(page.driver.response.status).to eql(413)
  expect(page).to have_content('bigger')
end

Then(/^I'm denied the upload$/) do
  expect(page.driver.response.status).to eql(403)
end
