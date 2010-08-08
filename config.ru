require 'sinatra'

set :environment, :development
set :raise_errors, true
disable :run

require 'coquelicot_app'
Coquelicot.setup :depot_path => File.expand("#{options.root}/../files")
run Sinatra::Application
