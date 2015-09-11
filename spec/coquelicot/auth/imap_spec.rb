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
require 'coquelicot/auth/imap'

describe Coquelicot::Auth::ImapAuthenticator do
  include_context 'with Coquelicot::Application'

  before(:each) do
    app.set :authentication_method, :name => :imap
  end

  def authenticate(params)
    Coquelicot.settings.authenticator.authenticate(params)
  end

  describe '.authenticate' do
    context 'when no IMAP server is configured' do
      it 'should raise an error' do
        expect { authenticate(:imap_user => 'user', :imap_password => 'password') }.to raise_error(Coquelicot::Auth::Error)
      end
    end

    context 'when an IMAP server is configured' do
      before(:each) do
        allow(Coquelicot.settings).to receive_messages(:imap_server => 'example.org', :imap_port => 993)
        @imap = double('Net::IMAP').as_null_object
      end

      context 'when the server is working' do
        before(:each) do
          expect(Net::IMAP).to receive(:new).with('example.org', 993, true).and_return(@imap)
        end

        it 'should attempt to login to the server' do
          expect(@imap).to receive(:login).with('user', 'password')
          authenticate(:imap_user => 'user', :imap_password => 'password')
        end

        it 'should return true when login has been accepted' do
          allow(@imap).to receive(:login)
          expect(authenticate(:imap_user => 'user', :imap_password => 'password')). to be_truthy
        end

        it 'should return fales when login has been denied' do
          allow(@imap).to receive(:login).and_raise(Net::IMAP::NoResponseError.new(Net::IMAP::TaggedResponse.new(nil, nil, Net::IMAP::ResponseText.new(nil, :text => 'Login failed.'))))
          expect(authenticate(:imap_user => 'user', :imap_password => 'password')). to be_falsy
        end
      end

      context 'when the server is unreachable' do
        before(:each) do
          expect(Net::IMAP).to receive(:new).and_raise(Errno::ECONNREFUSED)
        end

        it 'should raise an error' do
          expect { authenticate(:imap_user => 'user', :imap_password => 'password') }. to raise_error(Coquelicot::Auth::Error)
        end
      end
    end
  end
end
