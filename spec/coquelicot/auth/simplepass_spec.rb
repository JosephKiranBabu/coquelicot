# -*- coding: UTF-8 -*-
# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2015 potager.org <jardiniers@potager.org>
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

require 'spec_helper'
require 'coquelicot/auth/simplepass'

describe Coquelicot::Auth::SimplepassAuthenticator do
  include_context 'with Coquelicot::Application'

  before(:each) do
    app.set :authentication_method, :name => :simplepass
  end

  def authenticate(params)
    Coquelicot.settings.authenticator.authenticate(params)
  end

  describe '.authenticate' do
    context 'when no upload password is configured' do
      before(:each) do
        allow(Coquelicot.settings).to receive(:upload_password).and_return(nil)
      end

      it 'should always return true' do
        expect(authenticate(:upload_password => nil)).to be_truthy
      end
    end

    context 'when an upload password is set' do
      before(:each) do
        allow(Coquelicot.settings).to receive(:upload_password).and_return(Digest::SHA1.hexdigest('uploadpassword'))
      end

      it 'should return true if the password is correct' do
        expect(authenticate(:upload_password => 'uploadpassword')).to be_truthy
      end

      it 'should return false if the password is wrong' do
        expect(authenticate(:upload_password => 'wrong')).to be_falsy
      end
    end
  end
end
