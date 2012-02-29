# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2010-2012 potager.org <jardiniers@potager.org>
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
require 'bundler'

Bundler.require

$:.unshift File.join(File.dirname(__FILE__), 'lib')
require 'coquelicot'

if defined? Rainbows::Client
  # This implements the behaviour outlined in Section 8 of
  # <http://ftp.ics.uci.edu/pub/ietf/http/draft-ietf-http-connection-00.txt>.
  #
  # Half-closing the write part first and draining our input makes sure the
  # client will properly receive an error message instead of TCP RST (a.k.a.
  # "Connection reset by peer") when we interrupt it in the middle of a POST
  # request.
  #
  # Thanks Eric Wong for these few lines. See
  # <http://rubyforge.org/pipermail/rainbows-talk/2012-February/000328.html> for
  # the discussion that lead him to propose what follows.
  class Rainbows::Client
    def close
      close_write
      buf = ""
      loop do
        kgio_wait_readable(2)
        break unless kgio_tryread(512, buf)
      end
    ensure
      super
    end
  end
end

run Coquelicot::Application
