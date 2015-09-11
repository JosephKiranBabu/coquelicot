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

Then(/^the downloaded file is named "([^"]*)"$/) do |file_name|
  expect(page.driver.response.headers['Content-Disposition']).to start_with('attachment')
  expect(page.driver.response.headers['Content-Disposition']).to match(/filename=(['"]?)#{Regexp.escape(file_name)}\1/)
end

Then(/^(?:the downloaded file has the same content as the uploaded file|I should get the original file|I have downloaded the file)$/) do
  original_content = File.open(@uploaded_file, :encoding => 'binary').read
  expect(page.driver.response.body).to eql(original_content)
end

Then(/^the downloaded file has the same size as the uploaded file$/) do
  original_size = File.size(@uploaded_file)
  expect(page.driver.response.headers['Content-Length'].to_i).to eql(original_size)
end

Then(/^the Last\-Modified header is set to the upload time$/) do
  last_modified = Time.parse(page.driver.response.headers['Last-Modified'])
  expect(@upload_time - last_modified).to be <= 1 # less than a second
end

Given(/^it has been downloaded once$/) do
  expect(@download_url).to be_truthy
  visit @download_url
end
