# -*- coding: UTF-8 -*-
# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2012-2014 potager.org <jardiniers@potager.org>
#           ©      2014 Rowan Thorpe <rowan@rowanthorpe.com>
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

# TODO: set array of multiple ldap servers in settings and loop over them to
#       find first matching UID to connect as

# TODO: add commented code showing how to direct login by full username,
#       without lookup

# TODO: add commented code showing how to use starttls as an option instead of
#       dedicated SSL port, too

# NB:   :simple_tls ensures all communication is encrypted, but it doesn't
#       verify the server-certificate. A method which does *both* doesn't
#       seem to exist in Net::LDAP yet...

require 'net/ldap'

module Coquelicot
  module Auth
    class LdapAuthenticator < AbstractAuthenticator
      def authenticate(params)
        if params[:ldap_user].empty? || params[:ldap_password].empty?
          raise Coquelicot::Auth::Error.new('Empty username or password.')
        end
        # connect anonymously & lookup user to do authenticated bind_as() next
        ldap = Net::LDAP.new(:host => settings.ldap_server,
                             :port => settings.ldap_port,
                             :base => settings.ldap_base,
                             :encryption => :simple_tls,
                             :auth => { :method => :anonymous })
        result = ldap.bind_as(:base => settings.ldap_base,
                              :filter => "(uid=#{Net::LDAP::Filter.escape(params[:ldap_user])})",
                              :password => params[:ldap_password])
        unless result
          raise Coquelicot::Auth::Error.new(
                    'Failed authentication to LDAP server')
        end
        true
      rescue Errno::ECONNREFUSED
        raise Coquelicot::Auth::Error.new(
                  'Unable to connect to LDAP server')
      rescue NoMethodError => ex
        if [:ldap_server, :ldap_port, :ldap_base].include? ex.name
          raise Coquelicot::Auth::Error.new(
                    "Missing '#{ex.name}' attribute in configuration.")
        else
          raise
        end
      end
    end
  end
end
