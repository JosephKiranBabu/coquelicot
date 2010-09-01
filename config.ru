require 'coquelicot_app'

Coquelicot.setup :depot_path => File.join(File.dirname(__FILE__), 'files')

app = Coquelicot::Application

app.set :public, File.join(File.dirname(__FILE__), 'public')
app.set :environment, :development
app.set :raise_errors, true
app.disable :run

run app
