# -*- coding: UTF-8 -*-
# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2012-2015 potager.org <jardiniers@potager.org>
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

require 'net/imap'
module Coquelicot
  module Auth
    class ImapAuthenticator < AbstractAuthenticator
      def authenticate(params)
        imap = Net::IMAP.new(settings.imap_server, settings.imap_port, true)
        imap.login(params[:imap_user], params[:imap_password])
        imap.logout
        true
      rescue Net::IMAP::NoResponseError
        false
      rescue Errno::ECONNREFUSED
        raise Coquelicot::Auth::Error.new(
                  'Unable to connect to IMAP server')
      rescue NoMethodError => ex
        if [:imap_server, :imap_port].include? ex.name
          raise Coquelicot::Auth::Error.new(
                    "Missing '#{ex.name}' attribute in configuration.")
        else
          raise
        end
      end
    end
  end
end
