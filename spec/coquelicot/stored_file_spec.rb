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
require 'tmpdir'
require 'yaml'
require 'timecop'
require 'base64'

module Coquelicot
  describe StoredFile do
    shared_context 'create new StoredFile' do
      around do |example|
        Dir.mktmpdir('coquelicot') do |tmpdir|
          @tmpdir = tmpdir
          example.run
        end
      end

      def create_stored_file(extra_meta = {})
        @stored_file_path ||= File.expand_path('stored_file', @tmpdir)
        @pass = 'secret'
        @src = __FILE__
        @src_length = File.stat(@src).size
        meta = { 'Expire-at' => 0 }
        meta.merge!(extra_meta)
        content = slurp(@src)
        StoredFile.create(@stored_file_path, @pass, meta) do
          buf, content = content, nil
          buf
        end
      end
    end

    def read_meta(path)
      File.open(path) do |f|
        meta = f.readline
        while buf = f.readline
          break if buf =~ /^---( |\n)/
          meta += buf
        end
        YAML.load(meta)
      end
    end

    describe '.get_cipher' do
      context 'when given an unknown method' do
        it 'should raise an error' do
          expect {
            StoredFile.get_cipher('secret', 'salt', :whatever)
          }.to raise_error(NameError)
        end
      end
      [ :encrypt, :decrypt ].each do |method|
        let(:key_len)  { 32 } # this is AES-256-CBC
        let(:iv_len)   { 16 } # this is AES-256-CBC
        let(:hmac_len) { key_len + iv_len }
        let(:hmac) { (1..hmac_len).to_a.collect { |c| c.chr }.join }
        context "when given #{method} as method" do
          it 'should use PKCS5.pbkdf2_hmac_sha1' do
            expect(OpenSSL::PKCS5).to receive(:pbkdf2_hmac_sha1).
              with('secret', 'salt', 2000, hmac_len).
              and_return(hmac)
            StoredFile.get_cipher('secret', 'salt', method)
          end
          it 'should set the key to lower part of the HMAC' do
            allow(OpenSSL::PKCS5).to receive(:pbkdf2_hmac_sha1).
              and_return(hmac)
            cipher = OpenSSL::Cipher.new 'AES-256-CBC'
            expect(cipher).to receive(:key=).with(hmac[0..key_len-1])
            allow(OpenSSL::Cipher).to receive(:new).and_return(cipher)
            StoredFile.get_cipher('secret', 'salt', method)
          end
          it 'should set the IV to the higher part of the HMAC' do
            allow(OpenSSL::PKCS5).to receive(:pbkdf2_hmac_sha1).
              and_return(hmac)
            cipher = OpenSSL::Cipher.new 'AES-256-CBC'
            expect(cipher).to receive(:iv=).with(hmac[key_len..-1])
            allow(OpenSSL::Cipher).to receive(:new).and_return(cipher)
            StoredFile.get_cipher('secret', 'salt', method)
          end
          it 'should return an OpenSSL::Cipher' do
            cipher = StoredFile.get_cipher('secret', 'salt', method)
            expect(cipher).to be_a(OpenSSL::Cipher)
          end
        end
      end
    end

    describe '.gen_salt' do
      it 'should return a string of proper length' do
        StoredFile.gen_salt.length == StoredFile::SALT_LEN
      end
      it 'should call OpenSSL::Random every time' do
        expect(OpenSSL::Random).to receive(:random_bytes).
            and_return(1, 2)
        StoredFile.gen_salt == 1
        StoredFile.gen_salt == 2
      end
    end

    describe '.open' do
      context 'when the given file does not exist' do
        it 'should raise an error' do
          expect {
            StoredFile.open('/nonexistent')
          }.to raise_error(Errno::ENOENT)
        end
      end
      context 'when the file is not a StoredFile' do
        it 'should raise an error' do
          expect {
            StoredFile.open(__FILE__)
          }.to raise_error(ArgumentError)
        end
      end
      context 'when giving no pass' do
        for_all_file_versions do
          subject { StoredFile.open(stored_file_path) }
          it 'should read clear metadata' do
            subject.meta['Coquelicot'] == reference['Coquelicot']
          end
          # XXX: maybe we want a way to know that we can't uncrypt the rest
        end
      end
      context 'when giving a wrong pass' do
        for_all_file_versions do
          it 'should raise an error' do
            expect {
              StoredFile.open(stored_file_path, 'whatever')
            }.to raise_error(BadKey)
          end
        end
      end
      context 'when giving the right pass' do
        for_all_file_versions do
          subject { StoredFile.open(stored_file_path, 'secret') }
          it 'should read the metadata' do
            subject.meta['Length'] == reference['Length']
          end
        end
      end
    end

    describe '.create' do
      include_context 'create new StoredFile'
      context 'when the metadata file already exists' do
        it 'should raise an error' do
          @stored_file_path = File.expand_path('stored_file', @tmpdir)
          FileUtils.touch @stored_file_path
          expect {
            create_stored_file
          }.to raise_error(Errno::EEXIST)
        end
      end
      context 'when the content file already exists' do
        it 'should raise an error' do
          @stored_file_path = File.expand_path('stored_file', @tmpdir)
          FileUtils.touch "#{@stored_file_path}.content"
          expect {
            create_stored_file
          }.to raise_error(Errno::EEXIST)
        end
      end
      context 'in metadata file, clear part' do
        let(:test_salt) { "\0" * StoredFile::SALT_LEN }
        let(:expire_at) { Time.at(Time.now.to_i + 60) } # we need to round it at second-level
        before(:each) do
          allow(StoredFile).to receive(:gen_salt).and_return(test_salt)
          create_stored_file('Expire-at' => expire_at)
        end
        let(:clear_meta) { read_meta(@stored_file_path) }
        it 'should write Coquelicot file version' do
          expect(clear_meta['Coquelicot']).to be == '2.0'
        end
        it 'should generate a random Salt' do
          salt = Base64.decode64(clear_meta['Salt'])
          expect(salt).to be == test_salt
        end
        it 'should record expiration time' do
          expect(clear_meta['Expire-at']).to be == expire_at
        end
      end
      shared_context 'in encrypted part' do |path_regex|
        before(:each) do
          class NullCipher
            attr_reader :content
            def initialize; reset; end
            def reset; @buf, @content = '', nil; end
            def update(str); @buf << str ; str; end
            def final; @content = @buf; ''; end
          end
          cipher = NullCipher.new
          allow(StoredFile).to receive(:get_cipher).and_return(cipher)
          @content = StringIO.new
          open = File.method(:open)
          expect(File).to receive(:open).at_least(1).times do |path, *args, &block|
            if path =~ path_regex
              ret = block.call(@content)
              @cipher = cipher.dup
              ret
            else
              open.call(path, *args, &block)
            end
          end
        end
      end
      context 'in metadata file, encrypted part' do
        include_context 'in encrypted part', /stored_file$/
        it 'should contain metadata as YAML block' do
          create_stored_file
          expect(@cipher.content.split(/^---(?: |\n)/, 3).length).to be == 2
          expect(YAML.load(@cipher.content)).to be_a(Hash)
        end
        context 'in encrypted metadata' do
          before(:each) do
            create_stored_file
            @meta = YAML.load(@cipher.content)
          end
          it 'should contain Length' do
            expect(@meta['Length']).to be == @src_length
          end
          it 'should Created-at' do
            expect(@meta).to include('Created-at')
          end
        end
      end
      context 'in encrypted content' do
        include_context 'in encrypted part', /stored_file\.content$/
        before(:each) do
          create_stored_file
        end
        it 'should contain the file content' do
          expect(@cipher.content).to be == slurp(@src)
        end
        it 'should have the whole file for encrypted content' do
          @content.string == slurp(@src)
        end
      end
      context 'when the given block raise an error' do
        it 'should not leave files' do
          expect {
            path = File.expand_path('stored_file', @tmpdir)
            begin
              StoredFile.create(path, 'secret', {}) do
                raise StandardError.new
              end
            rescue StandardError
              # that was expected!
            end
          }.to_not change { Dir.entries(@tmpdir) }
        end
      end
    end

    describe '#created_at' do
      context 'with a new file' do
        include_context 'create new StoredFile'
        it 'should return the creation time' do
          Timecop.freeze(Time.local(2012, 1, 1)) do
            create_stored_file
            stored_file = StoredFile.open(@stored_file_path, @pass)
            expect(stored_file.created_at).to be == Time.local(2012, 1, 1)
          end
        end
      end
      for_all_file_versions do
        it 'should return the creation time' do
          expect(stored_file.created_at).to be == Time.at(reference['Created-at'])
        end
      end
    end

    describe '#expire_at' do
      context 'with a new file' do
        include_context 'create new StoredFile'
        it 'should return the date of expiration' do
          create_stored_file('Expire-at' => Time.local(2012, 1, 1))
          stored_file = StoredFile.open(@stored_file_path, @pass)
          expect(stored_file.expire_at).to be == Time.local(2012, 1, 1)
        end
      end
      for_all_file_versions do
        specify { expect(stored_file.expire_at).to be == Time.at(reference['Expire-at']) }
      end
    end

    describe '#expired?' do
      include_context 'create new StoredFile'
      context 'when expiration time is in the past' do
        it 'should return true' do
          Timecop.freeze do
            create_stored_file('Expire-at' => Time.now - 60)
            stored_file = StoredFile.open(@stored_file_path, @pass)
            expect(stored_file).to be_expired
          end
        end
      end
      context 'when expiration time is in the future' do
        it 'should return false' do
          Timecop.freeze do
            create_stored_file('Expire-at' => Time.now + 60)
            stored_file = StoredFile.open(@stored_file_path, @pass)
            expect(stored_file).not_to be_expired
          end
        end
      end
    end

    describe '#one_time_only?' do
      include_context 'create new StoredFile'
      context 'when file is labelled as "one time only"' do
        it 'should be true' do
          create_stored_file('One-time-only' => true)
          stored_file = StoredFile.open(@stored_file_path, @pass)
          expect(stored_file).to be_one_time_only
        end
      end
      context 'when file is not labelled as "one time only"' do
        it 'should be false' do
          create_stored_file
          stored_file = StoredFile.open(@stored_file_path, @pass)
          expect(stored_file).not_to be_one_time_only
        end
      end
    end

    describe '#empty!' do
      for_all_file_versions do
        include_context 'create new StoredFile'
        before(:each) do
          FileUtils.cp Dir.glob("#{stored_file_path}*"), @tmpdir
          @stored_file_path = File.expand_path('stored_file', @tmpdir)
          @stored_file = StoredFile.open(@stored_file_path, @pass)
        end
        it 'should overwrite file contents with \0' do
          Dir.glob("#{@stored_file_path}*").each do |path|
            expect(File).to receive(:open) do |*args, &block|
              length = File.stat(path).size
              file = StringIO.new(slurp(path))
              block.call(file)
              expect(file.string).to be == "\0" * length
            end
          end
          @stored_file.empty!
        end
        it 'should truncate files' do
          @stored_file.empty!
          Dir.glob("#{@stored_file_path}*").each do |path|
            expect(File.stat(path).size).to be == 0
          end
        end
      end
    end

    describe '#lockfile' do
      for_all_file_versions do
        let(:stored_file) { StoredFile.open(stored_file_path, 'secret') }
        it 'should return a Lockfile' do
          expect(stored_file.lockfile).to be_a(Lockfile)
        end
        it 'should create a Lockfile using the path followed by ".lock"' do
          expect(Lockfile).to receive(:new) do |path, options|
            expect(path).to be == "#{stored_file_path}.lock"
          end
          stored_file.lockfile
        end
      end
    end

    describe '#each' do
      context 'when the right pass has been given' do
        for_all_file_versions do
          it 'should output the whole content with several yields' do
            buf = ''
            stored_file.each do |data|
              buf << data
            end
            expect(buf).to be == reference['Content']
          end
        end
      end
      context 'when no password has been given' do
        for_all_file_versions do
          let(:stored_file) { StoredFile.open(stored_file_path) }
          it 'should raise BadKey' do
            expect {
              stored_file.each
            }.to raise_error(BadKey)
          end
        end
      end
    end

    describe '#close' do
      for_all_file_versions do
        it 'should reset the cipher' do
          salt = Base64::decode64(read_meta(stored_file_path)['Salt'])
          cipher = StoredFile.get_cipher('secret', salt, :decrypt)
          allow(StoredFile).to receive(:get_cipher).and_return(cipher)

          stored_file = StoredFile.open(stored_file_path, 'secret')
          expect(cipher).to receive(:reset)
          stored_file.close
        end
      end
      context 'when file is "one-time only"' do
        include_context 'create new StoredFile'
        before(:each) do
          create_stored_file('One-time-only' => true)
          @stored_file = StoredFile.open(@stored_file_path, @pass)
          # XXX: that is not a nice assumption (at all)
          @stored_file.lockfile.lock
        end
        context 'when the file has not been fully sent' do
          it 'should leave the content untouched' do
            begin
              @stored_file.each { |data| raise StandardError }
            rescue
              # do nothing
            end
            @stored_file.close
            another = StoredFile.open(@stored_file_path, @pass)
            buf = ''
            another.each { |data| buf << data }
            expect(buf).to be == slurp(@src)
          end
        end
        context 'when the file has been fully sent' do
          before(:each) do
            # read entirely
            @stored_file.each { |data| nil }
          end
          it 'should empty the file' do
            expect(@stored_file).to receive(:empty!)
            @stored_file.close
          end
        end
      end
    end
  end
end
