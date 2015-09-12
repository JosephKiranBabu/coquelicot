# -*- coding: UTF-8 -*-
# Coquelicot: "one-click" file sharing with a focus on users' privacy.
# Copyright © 2010-2015 potager.org <jardiniers@potager.org>
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

ENV['RACK_ENV'] = 'test'

require 'rubygems'
require 'bundler'
Bundler.require(:default, :development)
Bundler.setup

require 'rack/test'
require 'rspec'
require 'stringio'

# Set a default time zone. Otherwise tests using Timecop fail when
# activesupport is loaded.
require 'active_support/time'
Time.zone = 'UTC'

require 'coquelicot'

shared_context 'with Coquelicot::Application' do
  def app
    Coquelicot::Application
  end

  before do
    app.set :environment, :test
  end

  around(:each) do |example|
    path = Dir.mktmpdir('coquelicot')
    begin
      @depot_path = File.join(path, 'depot')
      FileUtils.mkdir(@depot_path)
      app.set :depot_path, @depot_path
      @cache_path = File.join(path, 'cache')
      FileUtils.mkdir(@cache_path)
      app.set :cache_path, @cache_path
      example.run
    ensure
      FileUtils.remove_entry_secure path
    end
  end
end

module StoredFileHelpers
  FIXTURES = { 'LICENSE-secret-1.0' => '1.0',
               'small-secret-1.0' => 'small 1.0',
               'LICENSE-secret-2.0' => '2.0'
             }

  shared_context 'with a StoredFile fixture' do |name|
    let(:stored_file_path) {
      File.expand_path("../fixtures/#{name}/stored_file", __FILE__)
    }
    let(:stored_file) { Coquelicot::StoredFile.open(stored_file_path, 'secret') }
    let(:reference) {
      YAML.load_file(File.expand_path("../fixtures/#{name}/reference", __FILE__))
    }
  end

  def for_all_file_versions(&block)
    FIXTURES.each_pair do |name, description|
      context "with a #{description} file" do
        include_context 'with a StoredFile fixture', name
        instance_eval &block
      end
    end
  end
end

module CoquelicotSpecHelpers
  # written by cash on
  # http://rails-bestpractices.com/questions/1-test-stdin-stdout-in-rspec
  def capture(*streams)
    streams.map! { |stream| stream.to_s }
    begin
      result = StringIO.new
      streams.each { |stream| eval "$#{stream} = result" }
      yield
    ensure
      streams.each { |stream| eval("$#{stream} = #{stream.upcase}") }
    end
    result.string
  end

  if defined? Encoding
    def slurp(path)
      File.read(path, :encoding => 'binary')
    end
  else
    def slurp(path)
      File.read(path)
    end
  end

  # borrowed from https://gist.github.com/cyx/1325708
  def xhr(path, params = {})
    verb = params.delete(:as) || :get
    send(verb, path, params, 'HTTP_X_REQUESTED_WITH' => 'XMLHttpRequest')
  end
end

::RSpec.configure do |c|
  c.extend StoredFileHelpers
  c.include CoquelicotSpecHelpers

  c.expect_with :rspec do |e|
    e.syntax = :expect
  end
end
