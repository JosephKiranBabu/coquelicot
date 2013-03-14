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

$:.push File.expand_path("../lib", __FILE__)
require "coquelicot/version"

Gem::Specification.new do |s|
  s.name        = 'coquelicot'
  s.version     = Coquelicot::VERSION
  s.authors     = ['potager.org', 'mh / immerda.ch']
  s.email       = ['jardiniers@potager.org']
  s.homepage    = 'https://coquelicot.potager.org/'
  s.summary     = %q{"one-click" file sharing web application focusing on privacy}
  s.description = <<-DESCRIPTION.gsub(/^ */, '')
    Coquelicot is a "one-click" file sharing web application with a
    focus on protecting users' privacy.

    Basic principle: users can upload a file to the server, in return they
    get a unique URL which can be shared with others in order to download
    the file.

    Coquelicot aims to protect, to some extent, users and system
    administrators from disclosure of the files exchanged from passive and
    not so active attackers.
  DESCRIPTION

  s.files         = `git ls-files`.split("\n").
      select { |p| !['.gitignore', '.placeholder', 'coquelicot.git'].include?(File.basename(p)) }
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ['lib']

  s.add_development_dependency 'rake'
  s.add_development_dependency 'rspec', '~>2.6'
  s.add_development_dependency 'hpricot'
  s.add_development_dependency 'timecop'
  s.add_development_dependency 'rack-test'
  s.add_development_dependency 'capybara'
  s.add_development_dependency 'active_support'
  s.add_development_dependency 'gettext'

  s.add_runtime_dependency 'sinatra', '~>1.3'
  s.add_runtime_dependency 'sinatra-contrib', '~>1.3'
  s.add_runtime_dependency 'rack', '~>1.1'
  s.add_runtime_dependency 'haml', '~>3.1'
  s.add_runtime_dependency 'haml-magic-translations', '~>0.3'
  s.add_runtime_dependency 'sass'
  s.add_runtime_dependency 'maruku'
  s.add_runtime_dependency 'fast_gettext'
  s.add_runtime_dependency 'lockfile', '~>2.0'
  s.add_runtime_dependency 'json'
  s.add_runtime_dependency 'rainbows'
  s.add_runtime_dependency 'multipart-parser'
  s.add_runtime_dependency 'upr'
  s.add_runtime_dependency 'moneta', '~>0.7'
end
