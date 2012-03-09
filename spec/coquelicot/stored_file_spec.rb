# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2010-2012 potager.org <jardiniers@potager.org>
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
        content = File.read(@src)
        StoredFile.create(@stored_file_path, @pass, meta) do
          buf, content = content, nil
          buf
        end
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
            OpenSSL::PKCS5.should_receive(:pbkdf2_hmac_sha1).
              with('secret', 'salt', 2000, hmac_len).
              and_return(hmac)
            StoredFile.get_cipher('secret', 'salt', method)
          end
          it 'should set the key to lower part of the HMAC' do
            OpenSSL::PKCS5.stub(:pbkdf2_hmac_sha1).
              and_return(hmac)
            cipher = OpenSSL::Cipher.new 'AES-256-CBC'
            cipher.should_receive(:key=).with(hmac[0..key_len-1])
            OpenSSL::Cipher.stub(:new).and_return(cipher)
            StoredFile.get_cipher('secret', 'salt', method)
          end
          it 'should set the IV to the higher part of the HMAC' do
            OpenSSL::PKCS5.stub(:pbkdf2_hmac_sha1).
              and_return(hmac)
            cipher = OpenSSL::Cipher.new 'AES-256-CBC'
            cipher.should_receive(:iv=).with(hmac[key_len..-1])
            OpenSSL::Cipher.stub(:new).and_return(cipher)
            StoredFile.get_cipher('secret', 'salt', method)
          end
          it 'should return an OpenSSL::Cipher' do
            cipher = StoredFile.get_cipher('secret', 'salt', method)
            cipher.should be_a(OpenSSL::Cipher)
          end
        end
      end
    end

    describe '.gen_salt' do
      it 'should return a string of proper length' do
        StoredFile.gen_salt.length == StoredFile::SALT_LEN
      end
      it 'should call OpenSSL::Random every time' do
        OpenSSL::Random.should_receive(:random_bytes).
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
        let(:expire_at) { Time.now + 60 }
        before(:each) do
          StoredFile.stub(:gen_salt).and_return(test_salt)
          create_stored_file('Expire-at' => expire_at)
        end
        let(:clear_meta) { YAML.load_file(@stored_file_path) }
        it 'should write Coquelicot file version' do
          clear_meta['Coquelicot'].should == '2.0'
        end
        it 'should generate a random Salt' do
          salt = Base64.decode64(clear_meta['Salt'])
          salt.should == test_salt
        end
        it 'should record expiration time' do
          clear_meta['Expire-at'].should == expire_at
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
          StoredFile.stub(:get_cipher).and_return(cipher)
          @content = StringIO.new
          open = File.method(:open)
          File.should_receive(:open).at_least(1).times do |path, *args, &block|
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
          @cipher.content.split(/^--- \n/, 3).length.should == 2
          YAML.load(@cipher.content).should be_a(Hash)
        end
        context 'in encrypted metadata' do
          before(:each) do
            create_stored_file
            @meta = YAML.load(@cipher.content)
          end
          it 'should contain Length' do
            @meta['Length'].should == @src_length
          end
          it 'should Created-at' do
            @meta.should include('Created-at')
          end
        end
      end
      context 'in encrypted content' do
        include_context 'in encrypted part', /stored_file\.content$/
        before(:each) do
          create_stored_file
        end
        it 'should contain the file content' do
          @cipher.content.should == File.read(@src)
        end
        it 'should have the whole file for encrypted content' do
          @content.string == File.read(@src)
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
          Timecop.freeze(2012, 1, 1) do
            create_stored_file
            stored_file = StoredFile.open(@stored_file_path, @pass)
            stored_file.created_at.should == Time.local(2012, 1, 1)
          end
        end
      end
      for_all_file_versions do
        it 'should return the creation time' do
          stored_file.created_at.should == Time.at(reference['Created-at'])
        end
      end
    end

    describe '#expire_at' do
      context 'with a new file' do
        include_context 'create new StoredFile'
        it 'should return the date of expiration' do
          create_stored_file('Expire-at' => Time.local(2012, 1, 1))
          stored_file = StoredFile.open(@stored_file_path, @pass)
          stored_file.expire_at.should == Time.local(2012, 1, 1)
        end
      end
      for_all_file_versions do
        specify { stored_file.expire_at.should == Time.at(reference['Expire-at']) }
      end
    end

    describe '#expired?' do
      include_context 'create new StoredFile'
      context 'when expiration time is in the past' do
        it 'should return true' do
          Timecop.freeze do
            create_stored_file('Expire-at' => Time.now - 60)
            stored_file = StoredFile.open(@stored_file_path, @pass)
            stored_file.should be_expired
          end
        end
      end
      context 'when expiration time is in the future' do
        it 'should return false' do
          Timecop.freeze do
            create_stored_file('Expire-at' => Time.now + 60)
            stored_file = StoredFile.open(@stored_file_path, @pass)
            stored_file.should_not be_expired
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
          stored_file.should be_one_time_only
        end
      end
      context 'when file is not labelled as "one time only"' do
        it 'should be false' do
          create_stored_file
          stored_file = StoredFile.open(@stored_file_path, @pass)
          stored_file.should_not be_one_time_only
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
            File.should_receive(:open) do |*args, &block|
              length = File.stat(path).size
              file = StringIO.new(File.read(path))
              block.call(file)
              file.string.should == "\0" * length
            end
          end
          @stored_file.empty!
        end
        it 'should truncate files' do
          @stored_file.empty!
          Dir.glob("#{@stored_file_path}*").each do |path|
            File.stat(path).size.should == 0
          end
        end
      end
    end

    describe '#lockfile' do
      for_all_file_versions do
        let(:stored_file) { StoredFile.open(stored_file_path, 'secret') }
        it 'should return a Lockfile' do
          stored_file.lockfile.should be_a(Lockfile)
        end
        it 'should create a Lockfile using the path followed by ".lock"' do
          Lockfile.should_receive(:new) do |path, options|
            path.should == "#{stored_file_path}.lock"
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
            buf.should == reference['Content']
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
          salt = Base64::decode64(YAML.load_file(stored_file_path)['Salt'])
          cipher = StoredFile.get_cipher('secret', salt, :decrypt)
          StoredFile.stub(:get_cipher).and_return(cipher)

          stored_file = StoredFile.open(stored_file_path, 'secret')
          cipher.should_receive(:reset)
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
            buf.should == File.read(@src)
          end
        end
        context 'when the file has been fully sent' do
          before(:each) do
            # read entirely
            @stored_file.each { |data| nil }
          end
          it 'should empty the file' do
            @stored_file.should_receive(:empty!)
            @stored_file.close
          end
        end
      end
    end
  end
end
