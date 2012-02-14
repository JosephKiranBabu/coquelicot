require 'rubygems'
require 'bundler'

Bundler.require(:development)

$:.unshift File.join(File.dirname(__FILE__), 'lib')
require 'coquelicot'

app = Coquelicot::Application

app.set :environment, :development
app.set :raise_errors, true
app.disable :run

run app
