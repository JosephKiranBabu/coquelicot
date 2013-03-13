# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2010-2013 potager.org <jardiniers@potager.org>
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

require 'rubygems'
require 'bundler'
Bundler.require(:default, :development)
Bundler.setup

require 'bundler/gem_tasks'
require 'haml/magic_translations/tasks'

Haml::MagicTranslations::Tasks::UpdatePoFiles.new(:updatepo) do |t|
  t.text_domain = 'coquelicot'
  t.files = Dir.glob('views/**/*.{rb,haml}') + Dir.glob('lib/coquelicot/**/*.rb')
  spec = Gem::Specification.load('coquelicot.gemspec')
  t.app_version = "coquelicot #{spec.version}"
end

task :create_archive do
  spec = Gem::Specification.load('coquelicot.gemspec')

  filename = "coquelicot-#{spec.version}.tar.gz"

  File.open(filename, 'wb') do |archive|
    Zlib::GzipWriter.wrap(archive) do |gzipped|
      Gem::Package::TarWriter.new(gzipped) do |writer|
        spec.files.each do |file|
          next if File.directory? file
          stat = File.stat(file)
          mode = stat.mode & 0777
          size = stat.size
          writer.add_file_simple(file, mode, size) do |tar_io|
            tar_io.write(open(file, 'rb') { |f| f.read })
          end
        end
        # Add empty directories where there is place holders
        Dir.glob('**/.placeholder') do |placeholder|
          writer.mkdir File.dirname(placeholder), 0700
        end
      end
    end
  end
end
