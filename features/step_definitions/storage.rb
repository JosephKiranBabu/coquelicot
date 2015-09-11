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

Then(/^the file is stored encrypted on the server$/) do
  original_excerpt = File.open(@uploaded_file, :encoding => 'binary') { |f| f.read(32) }
  files_in_depot = Dir.glob("#{@depot_path}/*")
  expect(files_in_depot.size).to be > 1
  files_in_depot.each do |path|
    content = File.open(path, :encoding => 'binary').read
    expect(content).to_not include(original_excerpt)
  end
end

Then(/^the file name on the server is different from the name in the URL$/) do
  url = find('textarea.ready').value
  name_in_url = File.basename(url).split('-')[0]
  expect(name_in_url).to match(/[0-9a-z]/) # sanity check for the following test
  files_in_depot = Dir.glob("#{@depot_path}/*")
  expect(files_in_depot.size).to be > 1
  files_in_depot.each do |path|
    expect(path).to_not include(name_in_url)
  end
end

When(/^two days have past$/) do
  Timecop.travel(Date.today + 2) do
    Coquelicot.run!(%w{gc})
  end
end

Then(/^the file has been removed from the server$/) do
  files_in_depot = Dir.glob("#{@depot_path}/*")
  expect(files_in_depot.size).to eql(2)
  files_in_depot.each do |path|
    expect(File.size(path)).to eql(0)
  end
end
