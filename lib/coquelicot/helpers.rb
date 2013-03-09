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

module Coquelicot
  module Helpers
    def clone_url
      settings.respond_to?(:clone_url) ? settings.clone_url : uri('coquelicot.git')
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
