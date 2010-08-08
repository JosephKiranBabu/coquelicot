require 'sinatra'

set :environment, :development
set :raise_errors, true
disable :run

require 'coquelicot_app'
Coquelicot.setup :depot_path => File.join(File.dirname(__FILE__), 'files')
run Sinatra::Application
