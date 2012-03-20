# -*- coding: UTF-8 -*-
# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2012 potager.org <jardiniers@potager.org>
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

module Coquelicot::Rack
  describe MultipartParser do
    let(:env) { { 'SERVER_NAME' => 'example.org',
                  'SERVER_PORT' => 80,
                  'REQUEST_METHOD' => 'POST',
                  'PATH_INFO' => '/upload',
                  'CONTENT_TYPE' => "multipart/form-data; boundary=#{Rack::Multipart::MULTIPART_BOUNDARY}",
                  'CONTENT_LENGTH' => "#{defined?(input) ? input.size : 0}",
                  'rack.input' => StringIO.new(defined?(input) ? input : '')
                } }
    describe '.parse' do
      context 'when given a block taking one argument' do
        it 'should run the block with a new parser as argument' do
          MultipartParser.parse(env) do |p|
            p.should be_a(MultipartParser)
          end
        end
      end
    end

    describe '#start' do
      context 'when given no block' do
        it 'should raise an error' do
          MultipartParser.parse(env) do |p|
            expect { p.start }.to raise_exception(ArgumentError)
          end
        end
      end
      context 'when used once' do
        it 'should call the block on start' do
          mock = double
          mock.should_receive(:act)
          MultipartParser.parse(env) do |p|
            p.start { mock.act }
          end
        end
      end
      context 'when used twice in a row' do
        it 'should call both blocks on start' do
          mock = double
          mock.should_receive(:run).ordered
          mock.should_receive(:walk).ordered
          MultipartParser.parse(env) do |p|
            p.start { mock.run }
            p.start { mock.walk }
          end
        end
      end
      context 'when used twice with steps inbetween' do
        it 'should call both blocks on start' do
          mock = double
          mock.should_receive(:run).ordered
          mock.should_receive(:walk).ordered
          MultipartParser.parse(env) do |p|
            p.start { mock.run }
            p.many_fields
            p.start { mock.walk }
          end
        end
      end
    end

    describe '#many_fields' do
      let(:input) do <<-MULTIPART_DATA.gsub(/^ */, '').gsub(/\n/, "\r\n")
          --AaB03x
          Content-Disposition: form-data; name="one"

          1
          --AaB03x
          Content-Disposition: form-data; name="two"

          2
          --AaB03x
          Content-Disposition: form-data; name="three"

          3
          --AaB03x--
        MULTIPART_DATA
      end
      context 'when used alone' do
        it 'should call the given block only once' do
          mock = double
          mock.should_receive(:act).once
          MultipartParser.parse(env) do |p|
            p.many_fields do |params|
              mock.act
            end
          end
        end
        it 'should call the given block for all fields' do
          MultipartParser.parse(env) do |p|
            p.many_fields do |params|
              params.should == { 'one' => '1', 'two' => '2', 'three' => '3' }
            end
          end
        end
      end
      context 'positioned after "field"' do
        it 'should call the given block only once' do
          mock = double
          mock.should_receive(:act).once
          MultipartParser.parse(env) do |p|
            p.field :one
            p.many_fields do |params|
              mock.act
            end
          end
        end
        it 'should call the given block for the remaning fields' do
          MultipartParser.parse(env) do |p|
            p.field :one
            p.many_fields do |params|
              params.should == { 'two' => '2', 'three' => '3' }
            end
          end
        end
      end
      context 'positioned before "field"' do
        it 'should call the given block only once' do
          mock = double
          mock.should_receive(:act).once
          MultipartParser.parse(env) do |p|
            p.many_fields do |params|
              mock.act
            end
            p.field :three
          end
        end
        it 'should call the given block for the first two fields' do
          MultipartParser.parse(env) do |p|
            p.many_fields do |params|
              params.should == { 'one' => '1', 'two' => '2' }
            end
            p.field :three
          end
        end
      end
      context 'before and after "field"' do
        it 'should call each given block only once' do
          mock = double
          mock.should_receive(:run).ordered
          mock.should_receive(:walk).ordered
          MultipartParser.parse(env) do |p|
            p.many_fields do |params|
              mock.run
            end
            p.field :two
            p.many_fields do |params|
              mock.walk
            end
          end
        end
        it 'should call each given block for the first and last fields, respectively' do
          MultipartParser.parse(env) do |p|
            p.many_fields do |params|
              params.should == { 'one' => '1' }
            end
            p.field :two
            p.many_fields do |params|
              params.should == { 'three' => '3' }
            end
          end
        end
      end
    end
    describe '#field' do
      let(:input) do <<-MULTIPART_DATA.gsub(/^ */, '').gsub(/\n/, "\r\n")
          --AaB03x
          Content-Disposition: form-data; name="one"

          1
          --AaB03x
          Content-Disposition: form-data; name="two"

          2
          --AaB03x
          Content-Disposition: form-data; name="three"

          3
          --AaB03x--
        MULTIPART_DATA
      end
      context 'when positioned like the request' do
        it 'should call a block for each field' do
          mock = double
          mock.should_receive(:first).with('1').ordered
          mock.should_receive(:second).with('2').ordered
          mock.should_receive(:third).with('3').ordered
          MultipartParser.parse(env) do |p|
            p.field(:one)   { |value| mock.first  value }
            p.field(:two)   { |value| mock.second value }
            p.field(:three) { |value| mock.third  value }
          end
        end
      end
      context 'when request field does not match' do
        it 'should issue an error' do
          expect {
            MultipartParser.parse(env) do |p|
              p.field(:whatever)
            end
          }.to raise_exception(EOFError)
        end
      end
      context 'when request field does not match after many_fields' do
        it 'should not call the field block' do
          mock = double
          mock.should_not_receive(:foo)
          MultipartParser.parse(env) do |p|
            p.many_fields
            p.field(:whatever) { mock.foo }
          end
        end
      end
      context 'when request field  match after many_fields' do
        it 'should call the field block' do
          mock = double
          mock.should_receive(:foo).with('3')
          MultipartParser.parse(env) do |p|
            p.many_fields
            p.field(:three) { |value| mock.foo(value) }
          end
        end
      end
    end
    describe '#file' do
      context 'when file is at the end of the request' do
        let(:file) { __FILE__ }
        let(:input) { Rack::Multipart::Generator.new(
            'field1' => '1',
            'field2' => '2',
            'field3' => Rack::Multipart::UploadedFile.new(file)
          ).dump }
        context 'when positioned like the request' do
          it 'should call the given block in the right order' do
            mock = double
            mock.should_receive(:first).ordered
            mock.should_receive(:second).ordered
            mock.should_receive(:third).ordered
            MultipartParser.parse(env) do |p|
              p.field(:field1) { |value| mock.first }
              p.field(:field2) { |value| mock.second }
              p.file(:field3) do |filename, content_type, reader|
                mock.third
                while reader.call; end # flush file data
              end
            end
          end
          it 'should call the block passing the filename' do
            filename = File.basename(file)
            MultipartParser.parse(env) do |p|
              p.many_fields
              p.file(:field3) do |filename, content_type, reader|
                filename.should == filename
                while reader.call; end # flush file data
              end
            end
          end
          it 'should call the block passing the content type' do
            MultipartParser.parse(env) do |p|
              p.many_fields
              p.file(:field3) do |filename, content_type, reader|
                content_type.should == 'text/plain'
                while reader.call; end # flush file data
              end
            end
          end
          it 'should read the whole file with multiple reader.call' do
            data = ''
            MultipartParser.parse(env) do |p|
              p.many_fields
              p.file(:field3) do |filename, content_type, reader|
                buf = ''
                data << buf until (buf = reader.call).nil?
              end
            end
            data.should == slurp(file)
          end
        end
      end

      context 'when file is at the middle of the request' do
        let(:file) { __FILE__ }
        let(:input) { Rack::Multipart::Generator.new(
            'field1' => '1',
            'field2' => Rack::Multipart::UploadedFile.new(file),
            'field3' => '3'
          ).dump }
        context 'when positioned like the request' do
          it 'should call the given block in the right order' do
            mock = double
            mock.should_receive(:first).ordered
            mock.should_receive(:second).ordered
            mock.should_receive(:third).ordered
            MultipartParser.parse(env) do |p|
              p.field(:field1) { |value| mock.first }
              p.file(:field2) do |filename, content_type, reader|
                mock.second
                while reader.call; end # flush file data
              end
              p.field(:field3) { |value| mock.third }
            end
          end
          it 'should read the whole file with multiple reader.call' do
            data = ''
            MultipartParser.parse(env) do |p|
              p.field(:field1)
              p.file(:field2) do |filename, content_type, reader|
                buf = ''
                data << buf until (buf = reader.call).nil?
              end
              p.field(:field3)
            end
            data.should == slurp(file)
          end
        end
      end
      context 'when there two files follow each others in the request' do
        let(:file1) { __FILE__ }
        let(:file2) { File.expand_path('../../../spec_helper.rb', __FILE__) }
        let(:input) { Rack::Multipart::Generator.new(
            'field1' => Rack::Multipart::UploadedFile.new(file1),
            'field2' => Rack::Multipart::UploadedFile.new(file2)
          ).dump }
        context 'when positioned like the request' do
          it 'should call the given block in the right order' do
            mock = double
            mock.should_receive(:first).ordered
            mock.should_receive(:second).ordered
            MultipartParser.parse(env) do |p|
              p.file(:field1) do |filename, content_type, reader|
                mock.first
                while reader.call; end # flush file data
              end
              p.file(:field2) do |filename, content_type, reader|
                mock.second
                buf = ''
                while reader.call; end # flush file data
              end
            end
          end
          it 'should read the files correctly' do
            filename1 = File.basename(file1)
            filename2 = File.basename(file2)
            data1 = ''
            data2 = ''
            MultipartParser.parse(env) do |p|
              p.file(:field1) do |filename, content_type, reader|
                filename.should == filename1
                buf = ''
                data1 << buf until (buf = reader.call).nil?
              end
              p.file(:field2) do |filename, content_type, reader|
                filename.should == filename2
                buf = ''
                data2 << buf until (buf = reader.call).nil?
              end
            end
            data1.should == slurp(file1)
            data2.should == slurp(file2)
          end
        end
      end
    end

    describe '#finish' do
      context 'when given no block' do
        it 'should raise an error' do
          MultipartParser.parse(env) do |p|
            expect { p.finish }.to raise_exception(ArgumentError)
          end
        end
      end
      context 'when used once' do
        it 'should call the block on finish' do
          mock = mock('Object')
          mock.should_receive(:act)
          MultipartParser.parse(env) do |p|
            p.finish { mock.act }
          end
        end
      end
      context 'when used twice in a row' do
        it 'should call both blocks on finish (in reverse order)' do
          mock = double
          mock.should_receive(:run).ordered
          mock.should_receive(:walk).ordered
          MultipartParser.parse(env) do |p|
            p.finish { mock.walk }
            p.finish { mock.run }
          end
        end
      end
      context 'when used twice with steps inbetween' do
        it 'should call both blocks on finish (in reverse order)' do
          mock = double
          mock.should_receive(:run).ordered
          mock.should_receive(:walk).ordered
          MultipartParser.parse(env) do |p|
            p.finish { mock.walk }
            p.many_fields
            p.finish { mock.run }
          end
        end
      end
    end
  end
end
