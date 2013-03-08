# -*- coding: UTF-8 -*-
# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2012-2013 potager.org <jardiniers@potager.org>
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
  module Auth
    module Extension
      def authentication_method=(options)
        method = options.delete('name') || options.delete(:name)
        method = method.to_s if method.is_a? Symbol

        require "coquelicot/auth/#{method}"
        set :authenticator, Coquelicot::Auth.
           const_get("#{method.to_s.capitalize}Authenticator").new(self)

        options.each{|k,v| set k,v }
      end
    end

    class Error < StandardError; end

    class AbstractAuthenticator
      def initialize(app)
        @app = app
      end

      def settings
        @app
      end

      def authenticate(params)
        raise NotImplementedError.new('Authenticator needs to override the `authenticate` method!')
      end
    end
  end
end
