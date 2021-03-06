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
require 'timecop'

module Coquelicot
  describe Depot do
    describe '.new' do
      it 'should record the given path' do
        depot = Depot.new('/test')
        expect(depot.path).to be == '/test'
      end
    end

    around do |example|
      Dir.mktmpdir('coquelicot') do |tmpdir|
        @tmpdir = tmpdir
        example.run
      end
    end
    let(:depot)  { Depot.new(@tmpdir) }
    let(:pass)   { 'secret'}
    let(:expire) { 60 }

    def add_file
      content = 'Content'
      depot.add_file(pass, { 'Expire-at' => Time.now + expire }) do
        buf, content = content, nil
        buf
      end
    end

    describe '#add_file' do
      it 'should generate a random file name' do
        expect(depot).to receive(:gen_random_file_name).
          and_return('file', 'link')
        add_file
      end
      context 'when it generates a name that is already in use' do
        it 'should find another name' do
          FileUtils.touch File.expand_path('file', @tmpdir)
          expect(depot).to receive(:gen_random_file_name).
            and_return('file', 'another', 'link')
          add_file
        end
      end
      context 'when it generates the same name with another client' do
        it 'should find another name' do
          expect(depot).to receive(:gen_random_file_name).
            and_return('file', 'another', 'link')
          raised = false
          expect(StoredFile).to receive(:create).ordered.
              with(/\/file$/, pass, instance_of(Hash)).
              and_raise(Errno::EEXIST.new(File.expand_path('file', @tmpdir)))
          expect(StoredFile).to receive(:create).ordered.
              with(/\/another$/, pass, instance_of(Hash))
          add_file
        end
      end
      context 'when the given block raises an error' do
        it 'should not add a file to the depot' do
          expect {
            begin
              depot.add_file(pass, {}) { raise StandardError.new }
            rescue StandardError
              # pass
            end
          }.to_not change { depot.size }
        end
        it 'should cleanup any created files' do
          expect {
            begin
              depot.add_file(pass, {}) { raise StandardError.new }
            rescue StandardError
              # pass
            end
          }.to_not change { Dir.entries(@tmpdir) }
        end
      end
      context 'when given a fine content provider block' do
        it 'should add a new file in the depot' do
          expect {
            add_file
          }.to change { depot.size }.by(1)
        end
        it 'should return a randomly generated link name' do
          expect(depot).to receive(:gen_random_file_name).
            and_return('file', 'link')
          link = add_file
          expect(link).to be == 'link'
        end
        it 'should add the new link to the ".links" file' do
          expect(depot).to receive(:gen_random_file_name).
            and_return('file', 'link')
          add_file
          expect(File.read(File.expand_path('.links', @tmpdir))).to match /^link\s+file$/
        end
        context 'when it generates a link name that is already taken' do
          before(:each) do
            allow(depot).to receive(:gen_random_file_name).
              and_return('file', 'link', 'another', 'link', 'another_link')
            # add 'link' pointing to 'file'
            add_file
            # now it should add 'another_link' -> 'another'
            @link = add_file
          end
          it 'should not overwrite the existing link' do
            expect(depot.size).to be == 2
          end
          it 'should find another name' do
            expect(@link).to be == 'another_link'
          end
        end
      end
    end

    describe '#get_file' do
      context 'when there is no link with the given name' do
        it 'should return nil' do
          expect(depot.get_file('link')).to be_nil
        end
      end
      context 'when there is a link with the given name' do
        before(:each) do
          @link = add_file
        end
        it 'should return a StoredFile' do
          expect(depot.get_file(@link)).to be_a(StoredFile)
        end
        it 'should return the right file' do
          stored_file = depot.get_file(@link, pass)
          buf = ''
          stored_file.each { |data| buf << data }
          expect(buf).to be == 'Content'
        end
      end
      context 'when there is a link with no matching file' do
        before(:each) do
          expect(depot).to receive(:gen_random_file_name).
            and_return('file', 'link')
          @link = add_file
          File.unlink File.expand_path('file', @tmpdir)
        end
        it 'should return nil' do
          expect(depot.get_file(@link)).to be_nil
        end
      end
    end

    describe '#file_exists?' do
      subject { depot.file_exists?('link') }
      context 'when there is no link with the given name' do
        it { should_not be true }
      end
      context 'when there is a link with the given name' do
        before(:each) do
          expect(depot).to receive(:gen_random_file_name).
            and_return('file', 'link')
          add_file
        end
        it { should be true }
      end
      context 'when there is a link with no matching file' do
        before(:each) do
          expect(depot).to receive(:gen_random_file_name).
            and_return('file', 'link')
          add_file
          File.unlink File.expand_path('file', @tmpdir)
        end
        it { should_not be true }
      end
    end

    describe '#gc!' do
      context 'when there is no files' do
        it 'should do nothing' do
          expect { depot.gc! }.to_not change { Dir.entries(@tmpdir) }
        end
      end
      context 'when there is a file' do
        before(:each) do
          expect(depot).to receive(:gen_random_file_name).
            and_return('file', 'link')
          add_file
        end
        context 'before it is expired' do
          subject { depot.gc! }
          it 'should not remove links' do
            expect { subject }.to_not change { depot.size }
          end
          it 'should not remove files' do
            expect { subject }.to_not change { Dir.entries(@tmpdir) }
          end
          it 'should not empty the file' do
            expect {
              subject
            }.to_not change { File.stat(File.expand_path('file', @tmpdir)).size }
          end
        end
        context 'after it is expired' do
          subject { Timecop.travel(Date.today + 2) { depot.gc! } }
          it 'should not remove links' do
            expect { subject }.to_not change { depot.size }
          end
          it 'should not remove files' do
            expect { subject }.
                to_not change { Dir.entries(@tmpdir) }
          end
          it 'should empty the file' do
            expect { subject }.
                to change { File.stat(File.expand_path('file', @tmpdir)).size }.to(0)
          end
        end
        context 'after the gone period and two collections' do
          let(:now) { Time.now + Coquelicot.settings.gone_period * 61 }
          subject { Timecop.travel(now) { depot.gc!; depot.gc! } }
          it 'should remove links' do
            expect { subject }.to change { depot.size }.from(1).to(0)
          end
          it 'should remove files' do
            subject
            expect(Dir.glob("#{@tmpdir}/file*")).to be_empty
          end
        end
      end
      context 'when there is a file that expires after the gone period' do
        let(:expire) { Coquelicot.settings.gone_period + 42 }
        before(:each) do
          expect(depot).to receive(:gen_random_file_name).
            and_return('file', 'link')
          add_file
        end
        context 'after the gone period' do
          let(:now) { Time.now + Coquelicot.settings.gone_period * 61 }
          subject { Timecop.travel(now) { depot.gc! } }
          it 'should not remove links' do
            expect { subject }.to_not change { depot.size }
          end
          it 'should not remove files' do
            expect { subject }.
                to_not change { Dir.entries(@tmpdir) }
          end
        end
      end
      context 'when there is a link but no associated file' do
        before(:each) do
          expect(depot).to receive(:gen_random_file_name).
            and_return('file', 'link')
          add_file
          File.unlink File.expand_path('file', @tmpdir)
        end
        it 'should remove the link' do
          expect { depot.gc! }.to change { depot.size }.from(1).to(0)
        end
      end
      context 'when there is a corrupted file' do
        before(:each) do
          expect(depot).to receive(:gen_random_file_name).
            and_return('file', 'link')
          add_file
          @file_path = File.expand_path('file', @tmpdir)
          File.open(@file_path, 'w') do |f|
            f.write('gibberish')
          end
        end
        it 'should print a warning on stderr' do
          stderr = capture(:stderr) do
            depot.gc!
          end
          expect(stderr).to match /^W: #{@file_path} is not a Coquelicot file\. Skipping\./
        end
        it 'should not remove files' do
          capture(:stderr) do
            expect { depot.gc! }.to_not change { Dir.entries(@tmpdir) }
          end
        end
      end
    end

    describe '#size' do
      subject { depot.size }
      context 'when there is no files' do
        it { should == 0 }
      end
      context 'when there is a file' do
        before(:each) { add_file }
        it { should == 1 }
      end
      context 'when there is two files' do
        before(:each) { add_file ; add_file }
        it { should == 2 }
      end
    end
  end
end
