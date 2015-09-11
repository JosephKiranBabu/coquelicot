# -*- coding: UTF-8 -*-
# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2015 potager.org <jardiniers@potager.org>
#           © 2014 Rowan Thorpe <rowan@rowanthorpe.com>
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
require 'coquelicot/auth/ldap'

describe Coquelicot::Auth::LdapAuthenticator do
  include_context 'with Coquelicot::Application'

  before(:each) do
    app.set :authentication_method, :name => :ldap
  end

  def authenticate(params)
    Coquelicot.settings.authenticator.authenticate(params)
  end

  describe '.authenticate' do
    context 'when no LADP server is configured' do
      it 'should raise an error' do
        expect { authenticate(:ldap_user => 'user', :ldap_password => 'password') }.to raise_error(Coquelicot::Auth::Error)
      end
    end

    context 'when an LDAP server is configured' do
      before(:each) do
        allow(Coquelicot.settings).to receive_messages(:ldap_server => 'example.org', :ldap_port => 636, :ldap_base => 'dc=example,dc=com')
        @ldap = double('Net::LDAP').as_null_object
      end

      context 'when the server is working' do
        before(:each) do
          expect(Net::LDAP).to receive(:new).with(
              :host => 'example.org',
              :port => 636,
              :base => 'dc=example,dc=com',
              :encryption => :simple_tls,
              :auth => { :method => :anonymous }).
            and_return(@ldap)
        end

        it 'should attempt to login to the server' do
          expect(@ldap).to receive(:bind_as).with(
                :base => 'dc=example,dc=com',
                :filter => '(uid=user)',
                :password => 'password').
            and_return(double('Net::LDAP::PDU'))
          authenticate(:ldap_user => 'user', :ldap_password => 'password')
        end

        it 'should return true when login has been accepted' do
          allow(@ldap).to receive(:bind_as).and_return(double('Net::LDAP::PDU'))
          expect(authenticate(:ldap_user => 'user', :ldap_password => 'password')). to be_truthy
        end

        it 'should return fales when login has been denied' do
          allow(@ldap).to receive(:bind_as).and_return(nil)
          expect(authenticate(:ldap_user => 'user', :ldap_password => 'password')). to be_falsy
        end

        it "should properly escape the given username" do
          expect(@ldap).to receive(:bind_as).with(
                :base => 'dc=example,dc=com',
                :filter => '(uid=us\\29er)',
                :password => 'password').
            and_return(double('Net::LDAP::PDU'))
          authenticate(:ldap_user => 'us)er', :ldap_password => 'password')
        end
      end

      context 'when the server is unreachable' do
        before(:each) do
          expect(Net::LDAP).to receive(:new).and_raise(Errno::ECONNREFUSED)
        end

        it 'should raise an error' do
          expect { authenticate(:ldap_user => 'user', :ldap_password => 'password') }. to raise_error(Coquelicot::Auth::Error)
        end
      end
    end
  end
end
