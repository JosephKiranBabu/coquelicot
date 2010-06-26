require 'sinatra'

set :environment, :development
set :raise_errors, true
disable :run

require 'coquelicot'
run Sinatra::Application
