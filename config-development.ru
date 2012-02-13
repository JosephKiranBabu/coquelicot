require 'coquelicot'

app = Coquelicot::Application

app.set :environment, :development
app.set :raise_errors, true
app.disable :run

run app
