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

# reset authentication method
Before do
  Capybara.app.set :authentication_method, :name => :simplepass,
                   :upload_password => Digest::SHA1.hexdigest(default_upload_password)
end

Around do |scenario, block|
  path = Dir.mktmpdir('coquelicot')
  begin
    @tempdir = path
    @depot_path = File.join(path, 'depot')
    Dir.mkdir(@depot_path)
    Capybara.app.set :depot_path, @depot_path
    block.call
  ensure
    FileUtils.remove_entry_secure path
  end
end
