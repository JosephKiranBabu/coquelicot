# -*- coding: UTF-8 -*-
# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2010-2013 potager.org <jardiniers@potager.org>
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
require 'coquelicot/jyraphe_migrator'
require 'tmpdir'
require 'digest/md5'
require 'timecop'

module Coquelicot
  describe JyrapheMigrator do
    include_context 'with Coquelicot::Application'

    around do |example|
      @jyraphe_var_path = Dir.mktmpdir('coquelicot')
      begin
        Dir.mkdir(File.expand_path('files', @jyraphe_var_path))
        Dir.mkdir(File.expand_path('links', @jyraphe_var_path))
        example.run
      ensure
        FileUtils.remove_entry_secure @jyraphe_var_path
      end
    end

    def add_file_to_jyraphe(file, options = {})
      options = { :mime_type => 'text/plain',
                  :expire_at => (Time.now + 3600).to_i }.merge(options)
      md5 = Digest::MD5.hexdigest(File.read(file))
      FileUtils.cp file, File.expand_path('files', @jyraphe_var_path)
      prefix = options[:one_time_only] ? 'O' : 'R'
      File.open(File.expand_path("links/#{prefix}#{md5}", @jyraphe_var_path), 'w') do |f|
        f.write("#{File.basename(file)}\n")
        f.write("#{options[:mime_type]}\n")
        f.write("#{File.stat(file).size}\n")
        f.write("#{options[:file_key]}\n")
        f.write("#{options[:expire_at]}\n")
      end
    end

    def get_first_migrated_file(pass = nil)
      old, new = migrator.migrated.to_a[0]
      if pass.nil?
        file, pass = new.split('-')
      else
        file = new
      end
      Coquelicot.depot.get_file(file, pass)
    end

    describe '#new' do
      context 'when the given directory is not a Jyraphe "var" directory' do
        it 'should raise an error' do
          expect {
            JyrapheMigrator.new(Coquelicot.settings.depot_path)
          }.to raise_error(ArgumentError)
        end
      end
    end

    describe '#migrate!' do
      let(:output) { double.as_null_object }
      let(:migrator) { JyrapheMigrator.new(@jyraphe_var_path, output) }
      context 'when there is a file in Jyraphe' do
        before(:each) do
          add_file_to_jyraphe(__FILE__, :mime_type => 'application/x-ruby')
        end
        it 'should add a new file to Coquelicot' do
          expect {
            migrator.migrate!
          }.to change { Coquelicot.depot.size }.by(1)
        end
        context 'when I read the file in Coquelicot' do
          before(:each) { migrator.migrate! }
          subject { get_first_migrated_file }
          it 'should have the same length' do
            expect(subject.meta['Length']).to be == File.stat(__FILE__).size
          end
          it 'should have the same mime type' do
            expect(subject.meta['Content-type']).to be == 'application/x-ruby'
          end
        end
      end

      context 'when there is two files in Jyraphe' do
        before(:each) do
          add_file_to_jyraphe(__FILE__, :mime_type => 'application/x-ruby')
          add_file_to_jyraphe(File.expand_path('../../../README', __FILE__),
                              :mime_type => 'text/plain')
        end
        it 'should add two files to Coquelicot' do
          expect {
            migrator.migrate!
          }.to change { Coquelicot.depot.size }.by(2)
        end
      end

      context 'when there is a "one-time only" file in Jyraphe' do
        before(:each) do
          add_file_to_jyraphe(__FILE__, :mime_type => 'application/x-ruby',
                                        :one_time_only => true)
        end
        it 'should add a file to Coquelicot' do
          expect {
            migrator.migrate!
          }.to change { Coquelicot.depot.size }.by(1)
        end
        context 'when I read the file in Coquelicot' do
          before(:each) { migrator.migrate! }
          subject { get_first_migrated_file }
          it 'should be labeled as "one-time only"' do
            expect(subject.meta['One-time-only']).to be true
          end
        end
      end

      context 'when there is a password protected file in Jyraphe' do
        let(:pass) { 'secret' }
        before(:each) do
          add_file_to_jyraphe(__FILE__, :mime_type => 'application/x-ruby',
                                        :file_key => pass)
        end
        it 'should add a file to Coquelicot' do
          expect {
            migrator.migrate!
          }.to change { Coquelicot.depot.size }.by(1)
        end
        context 'when I read the file in Coquelicot' do
          before(:each) { migrator.migrate! }
          it 'should need a pass' do
            stored_file = get_first_migrated_file
            expect(stored_file.meta).not_to include('Content-type')
          end
          it 'should be readable with a wrong pass' do
            expect {
              get_first_migrated_file('wrong')
            }.to raise_error(BadKey)
          end
          it 'should be readable with the same pass' do
            stored_file = get_first_migrated_file(pass)
            expect(stored_file.meta).to include('Content-type')
          end
        end
      end

      context 'when there is a never expiring file in Jyraphe' do
        before(:each) do
          add_file_to_jyraphe(__FILE__, :mime_type => 'application/x-ruby',
                                        :expire_at => -1)
        end
        it 'should issue a warning' do
          expect(output).to receive(:puts).
              with(/^W: R[0-9a-z]{32} expiration time has been reduced/)
          migrator.migrate!
        end
        it 'should add a file to Coquelicot' do
          expect {
            migrator.migrate!
          }.to change { Coquelicot.depot.size }.by(1)
        end
        context 'when I read the file in Coquelicot' do
          it 'should have the maximum expiration time' do
            Timecop.freeze(Time.now) do
              migrator.migrate!
              stored_file = get_first_migrated_file
              expect(stored_file.meta['Expire-at']).to be ==
                  (Time.now + Coquelicot.settings.maximum_expire * 60).to_i
            end
          end
        end
      end

      context 'when there is a file in Jyraphe which expires after the maximum allowed time' do
        before(:each) do
          add_file_to_jyraphe(
             __FILE__,
             :mime_type => 'application/x-ruby',
             :expire_at => (Time.now + Coquelicot.settings.maximum_expire * 60 + 5).to_i)
        end
        it 'should issue a warning' do
          expect(output).to receive(:puts).
              with(/^W: R[0-9a-z]{32} expiration time has been reduced/)
          migrator.migrate!
        end
        it 'should add a file to Coquelicot' do
          expect {
            migrator.migrate!
          }.to change { Coquelicot.depot.size }.by(1)
        end
        context 'when I read the file in Coquelicot' do
          it 'should have the maximum expiration time' do
            Timecop.freeze(Time.now) do
              migrator.migrate!
              stored_file = get_first_migrated_file
              expect(stored_file.meta['Expire-at']).to be ==
                  (Time.now + Coquelicot.settings.maximum_expire * 60).to_i
            end
          end
        end
      end

      context 'when there is a file in Jyraphe which has a bad expiration time' do
        before(:each) do
          add_file_to_jyraphe(__FILE__, :mime_type => 'application/x-ruby',
                                        :expire_at => 'unparseable')
        end
        it 'should issue a warning' do
          expect(output).to receive(:puts).
              with(/^W: R[0-9a-z]{32} has an unparseable expiration time\. Skipping\./)
          migrator.migrate!
        end
        it 'should not add a file to Coquelicot' do
          expect {
            migrator.migrate!
          }.to_not change { Coquelicot.depot.size }
        end
      end

      context 'when the file associated with a link is missing' do
        before(:each) do
          add_file_to_jyraphe(__FILE__, :mime_type => 'application/x-ruby')
          FileUtils.rm(File.expand_path(File.basename(__FILE__), "#{@jyraphe_var_path}/files"))
        end
        it 'should issue a warning' do
          expect(output).to receive(:puts).
              with(/^W: R[0-9a-z]{32} refers to a non-existent file\. Skipping\./)
          migrator.migrate!
        end
        it 'should not add a file to Coquelicot' do
          expect {
            migrator.migrate!
          }.to_not change { Coquelicot.depot.size }
        end
      end

      context 'when a file size does not match the link size' do
        before(:each) do
          add_file_to_jyraphe(__FILE__, :mime_type => 'application/x-ruby')
          File.truncate(File.expand_path(File.basename(__FILE__), "#{@jyraphe_var_path}/files"), 0)
        end
        it 'should issue a warning' do
          expect(output).to receive(:puts).
              with(/^W: R[0-9a-z]{32} refers to a file with mismatching size\. Skipping\./)
          migrator.migrate!
        end
        it 'should not add a file to Coquelicot' do
          expect {
            migrator.migrate!
          }.to_not change { Coquelicot.depot.size }
        end
      end
    end

    describe '#apache_rewrites' do
      let(:output) { double.as_null_object }
      let(:migrator) { JyrapheMigrator.new(@jyraphe_var_path, output) }
      context 'when there was nothing to migrate' do
        before(:each) { migrator.migrate! }
        subject { migrator.apache_rewrites }
        it { should == '' }
      end
      context 'when there was a file migrated' do
        before(:each) do
          add_file_to_jyraphe(__FILE__, :mime_type => 'application/x-ruby')
          migrator.migrate!
        end
        it 'should begin with "RewriteEngine on"' do
          expect(migrator.apache_rewrites).to satisfy do |s|
            s.start_with?('RewriteEngine on')
          end
        end
        context 'when given no prefix' do
          it 'should contain a rule appropriate for an .htaccess' do
            jyraphe, coquelicot = migrator.migrated.to_a[0]
            expect(migrator.apache_rewrites.split("\n")).to include(
                "RewriteRule ^file-#{jyraphe}$ #{coquelicot} [L,R=301]")
          end
        end
        context 'when given a prefix' do
          it 'should contain rules with the prefix' do
            jyraphe, coquelicot = migrator.migrated.to_a[0]
            expect(migrator.apache_rewrites('/dl/').split("\n")).to include(
                "RewriteRule ^/dl/file-#{jyraphe}$ /dl/#{coquelicot} [L,R=301]")
          end
        end
      end
      context 'when there was two files migrated' do
        before(:each) do
          add_file_to_jyraphe(File.expand_path('../../../README', __FILE__),
                              :mime_type => 'text/plain',
                              :one_time_only => true)
          add_file_to_jyraphe(__FILE__, :mime_type => 'application/x-ruby')
          migrator.migrate!
        end
        context 'when given no prefix' do
          it 'should contain two rule appropriate for an .htaccess' do
            jyraphe, coquelicot = migrator.migrated.to_a[0]
            expect(migrator.apache_rewrites.split("\n")).to include(
                "RewriteRule ^file-#{jyraphe}$ #{coquelicot} [L,R=301]")
            jyraphe, coquelicot = migrator.migrated.to_a[1]
            expect(migrator.apache_rewrites.split("\n")).to include(
                "RewriteRule ^file-#{jyraphe}$ #{coquelicot} [L,R=301]")
          end
        end
      end
    end

    describe '.run!' do
      context 'when given no option' do
        before(:each) do
          allow(JyrapheMigrator).to receive(:new).and_return(double.as_null_object)
        end
        it 'should display usage and exit with an error' do
          stderr = capture(:stderr) do
            expect {
              JyrapheMigrator.run! []
            }.to raise_error(SystemExit)
          end
          expect(stderr).to match /Usage:/
          expect(stderr).to match /--help for more details/
        end
      end
      context 'when given a path to a random directory' do
        it 'should display an error' do
          path = File.expand_path('files', @jyraphe_var_path)
          stderr = capture(:stderr) do
            expect {
              JyrapheMigrator.run! [path]
            }.to raise_error(SystemExit)
          end
          expect(stderr).to match /is not a Jyraphe/
        end
      end
      context 'when given a path to a Jyraphe var directory' do
        it 'should use the default depot path' do
          allow(JyrapheMigrator).to receive(:new).and_return(double.as_null_object)
          capture(:stdout) do
            JyrapheMigrator.run! [@jyraphe_var_path]
          end
          expect(Coquelicot.settings.depot_path).to be == @depot_path
        end
        it 'should migrate using the given Jyraphe var directory' do
          migrator = double('JyrapheMigrator').as_null_object
          expect(migrator).to receive(:migrate!)
          expect(JyrapheMigrator).to receive(:new).with(@jyraphe_var_path).
              and_return(migrator)
          capture(:stdout) do
            JyrapheMigrator.run! [@jyraphe_var_path]
          end
        end
        it 'should print rewrite rules after migrating' do
          migrator = double('JyrapheMigrator').as_null_object
          expect(migrator).to receive(:migrate!).ordered
          expect(migrator).to receive(:apache_rewrites).ordered.and_return('rules')
          allow(JyrapheMigrator).to receive(:new).and_return(migrator)
          stdout = capture(:stdout) do
            JyrapheMigrator.run! [@jyraphe_var_path]
          end
          expect(stdout.strip).to be == 'rules'
        end
      end
      context 'when using "-p"' do
        it 'should print rewrite rules using the given prefix' do
          migrator = double('JyrapheMigrator').as_null_object
          expect(migrator).to receive(:apache_rewrites).with('/prefix/')
          allow(JyrapheMigrator).to receive(:new).and_return(migrator)
          capture(:stdout) do
            JyrapheMigrator.run! ['-p', '/prefix/', @jyraphe_var_path]
          end
        end
      end
      context 'when using "-h"' do
        it 'should display help and exit' do
          stderr = capture(:stderr) do
            expect {
              JyrapheMigrator.run! ['-h']
            }.to raise_error(SystemExit)
          end
          expect(stderr).to match /Usage:/
        end
      end
    end
  end
end
