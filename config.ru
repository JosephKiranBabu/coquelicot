require 'sinatra'

set :environment, :development
set :raise_errors, true
set :depot_path, Proc.new { File.join(public, "../files") }
disable :run

require 'coquelicot'
run Sinatra::Application
