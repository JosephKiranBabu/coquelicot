# -*- coding: UTF-8 -*-
# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2010-2013 potager.org <jardiniers@potager.org>
#           © 2011 mh / immerda.ch <mh+coquelicot@immerda.ch>
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

module Coquelicot
  module Helpers
    def can_provide_git_repository?
      return @@can_provide_git_repository if defined?(@@can_provide_git_repository)

      # Test if `git update-server-info` was executed in the local repository
      @@can_provide_git_repository =
         File.readable?(File.expand_path('coquelicot.git/info/refs', settings.public_folder)) &&
         File.readable?(File.expand_path('coquelicot.git/objects/info/packs', settings.public_folder))

      if File.readable?(File.expand_path('coquelicot.git', settings.public_folder)) &&
         !@@can_provide_git_repository
        logger.warn <<-MESSAGE.gsub(/\n */m, ' ').strip
          Unable to provide access to local Git repository. Please ensure that
          you have run `git update-server-info` in the Coquelicot directory,
          and that the symlink `public/coquelicot.git` is properly set.
        MESSAGE
      end
      @@can_provide_git_repository
    end

    def gem_hostname
      # We need to mangle the hostname to fits Gem::Version constraints
      @@hostname ||= Socket.gethostname.gsub(/[^0-9a-zA-Z]/, '')
    end

    def gem_version
      spec = Gem::loaded_specs['coquelicot']
      current_version = spec.version.to_s.gsub(/\.[0-9a-zA-Z]+\.[0-9]{8}/, '')
      Gem::Version.new("#{current_version}.#{gem_hostname}.#{Date.today.strftime('%Y%m%d')}")
    end

    def clone_command
      if can_provide_git_repository?
        "git clone #{uri('coquelicot.git')}"
      else
        "curl -OJ #{uri('source')} && gem unpack coqueliot-#{gem_version}.gem"
      end
    end

    def authenticate(params)
      Coquelicot.settings.authenticator.authenticate(params)
    end

    def auth_method
      Coquelicot.settings.authenticator.class.name.gsub(/Coquelicot::Auth::([A-z0-9]+)Authenticator$/, '\1').downcase
    end

    def about_text
      settings.about_text[FastGettext.locale] || settings.about_text['en'] || ''
    end
  end
end
