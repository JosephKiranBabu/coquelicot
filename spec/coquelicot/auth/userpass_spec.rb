# -*- coding: UTF-8 -*-
# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2016 potager.org <jardiniers@potager.org>
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
require 'bcrypt'
require 'coquelicot/auth/userpass'

describe Coquelicot::Auth::UserpassAuthenticator do
  include_context 'with Coquelicot::Application'

  before(:each) do
    app.set :authentication_method, :name => :userpass
  end

  def authenticate(params)
    Coquelicot.settings.authenticator.authenticate(params)
  end

  describe '.authenticate' do
    context 'when no credentials are configured' do
      it 'should raise an error' do
        expect { authenticate(:upload_user => 'user', :upload_password => 'password') }.to raise_error(Coquelicot::Auth::Error)
      end
    end

    context 'when credentials are configured' do
      before(:each) do
        allow(Coquelicot.settings).to receive_messages(
            :credentials => { 'ada' => BCrypt::Password.create('lovelace'),
                              'emma' => BCrypt::Password.create('goldman') } ) 
      end

      it 'should return false if the login is empty' do
        expect(authenticate(:upload_login => '', :upload_password => 'something')).to be_falsy
      end

      it 'should return false if the password is empty' do
        expect(authenticate(:upload_login => 'something', :upload_password => '')).to be_falsy
      end

      it 'should return false if the user is unknown' do
        expect(authenticate(:upload_login => 'random', :upload_password => 'password')).to be_falsy
      end

      it 'should return false if the password is wrong' do
        expect(authenticate(:upload_login => 'ada', :upload_password => 'goldman')).to be_falsy
      end

      it 'should return false if the user and password are right' do
        expect(authenticate(:upload_login => 'emma', :upload_password => 'goldman')).to be_falsy
      end
    end
  end
end

