# -*- coding: UTF-8 -*-
# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2012-2016 potager.org <jardiniers@potager.org>
#           ©      2016 Rowan Thorpe <rowan@rowanthorpe.com>
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

require 'bcrypt'

module Coquelicot
  module Auth
    class UserpassAuthenticator < AbstractAuthenticator
      EMPTY_PASSWORD = BCrypt::Password.create('')

      def authenticate(params)
        upload_user = params[:upload_user] || ''
        upload_password = params[:upload_password] || ''
        return false if upload_user.empty? || upload_password.empty?

	# Use the empty password—we just disallowed it—for unknown users
        # in order to get constant time.
        reference_password = settings.credentials.fetch(upload_user, EMPTY_PASSWORD)
        return BCrypt::Password.new(reference_password) == upload_password
      rescue NoMethodError => ex
        if :credentials == ex.name
          raise Coquelicot::Auth::Error.new("Missing 'credentials' attribute in 'userpass' configuration.")
        else
          raise
        end
      end
    end
  end
end
