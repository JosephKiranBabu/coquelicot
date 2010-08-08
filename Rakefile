$:.unshift File.join(File.dirname(__FILE__), 'lib')

desc "Update pot/po files."
task :updatepo do
  require 'gettext/tools'
  require 'haml_parser'
  GetText.update_pofiles(
    "coquelicot",
    Dir.glob("views/**/*.{rb,haml}") << "coquelicot_app.rb",
    "coquelicot 1.0.0")
end

desc "Create mo-files"
task :makemo do
  require 'gettext/tools'
  GetText.create_mofiles(:mo_root => './locale')
end
