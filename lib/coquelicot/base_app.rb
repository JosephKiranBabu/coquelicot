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

require 'sinatra/base'
require 'haml'
require 'haml/magic_translations'

module Coquelicot
  AVAILABLE_LOCALES = %w(en fr de)

  class BaseApp < Sinatra::Base
    include FastGettext::Translation

    helpers Coquelicot::Helpers

    FastGettext.add_text_domain 'coquelicot', :path => 'po', :type => 'po'
    FastGettext.available_locales = AVAILABLE_LOCALES
    Haml::MagicTranslations.enable(:fast_gettext)

    before do
      FastGettext.text_domain = 'coquelicot'
      if params && params[:lang]
        locale = session[:lang] = params[:lang]
      elsif session[:lang]
        locale = session[:lang]
      else
        locale = request.env['HTTP_ACCEPT_LANGUAGE'] || 'en'
      end
      FastGettext.locale = locale
    end
  end
end
