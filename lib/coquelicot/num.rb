# -*- coding: UTF-8 -*-
# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2012-2013 potager.org <jardiniers@potager.org>
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

require 'fast_gettext'

module Coquelicot::Num
  include FastGettext::Translation

  # found on: http://codereview.stackexchange.com/questions/9107/
  def as_size
    prefix = [N_('TiB'), N_('GiB'), N_('MiB'), N_('KiB'), N_('B')]
    s = self.to_f
    i = prefix.length - 1
    while s > 512 && i > 0
      s /= 1024
      i -= 1
    end
    ((s > 9 || s.modulo(1) < 0.1 ? '%d' : '%.1f') % s) + ' ' + _(prefix[i])
  end
end

Fixnum.send(:include, Coquelicot::Num)
Bignum.send(:include, Coquelicot::Num)
