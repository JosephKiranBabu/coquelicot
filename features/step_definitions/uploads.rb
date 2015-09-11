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

When(/^I upload a file$/) do
  upload(__FILE__)
end

Given(/^a file has been uploaded$/) do
  upload(__FILE__)
  @download_url = find('textarea.ready').value
end

Given(/^a file named "([^"]*)" has been uploaded$/) do |file_name|
  expect(Dir.entries(@tempdir)).to_not include(file_name) # sanity check

  dest = File.join(@tempdir, file_name)
  FileUtils.cp __FILE__, dest
  upload(dest)
  @download_url = find('textarea.ready').value
end

Given(/^a file has been uploaded that will expire the next day$/) do
  visit '/'
  fill_in 'upload_password', :with => default_upload_password
  select '1 day', :from => 'expire'
  attach_file 'file', __FILE__
  click_button 'Share!'
end

When(/^I upload a file with "([^"]*)" as the download password$/) do |password|
  upload(__FILE__, :file_key => password)
end

Given(/^a file has been uploaded with a download password$/) do
  upload(__FILE__, :file_key => 'downloadpassword')
end

Given(/^a file has been uploaded with "([^"]*)" as the download password$/) do |password|
  upload(__FILE__, :file_key => password)
end

Given(/^a file has been uploaded and set to be removed after a single upload$/) do
  visit '/'
  fill_in 'upload_password', :with => default_upload_password
  find('#one_time').set(true) # XXX: there's probably a nicer way to tick the box
  attach_file 'file', __FILE__
  click_button 'Share!'
  @uploaded_file = __FILE__
  @download_url = find('textarea.ready').value
end

Given(/^I have an empty file$/) do
  @file_to_upload = File.join(@tempdir, 'empty')
  FileUtils.touch(@file_to_upload)
end

When(/^I try to upload it$/) do
  upload(@file_to_upload)
end

Given(/^I have a file bigger than the limit$/) do
  @file_to_upload = File.join(@tempdir, 'bigger')
  File.open(@file_to_upload, 'w', :encoding => 'binary') do |f|
    f.write('-' * (Coquelicot.settings.max_file_size + 1))
  end
end

When(/^I try to upload a file$/) do
  attach_file 'file', __FILE__
  click_button 'Share!'
end

Then(/^the upload is accepted$/) do
  expect(page).to have_content('Share this!')
end
