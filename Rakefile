require 'rubygems'
require 'bundler'
Bundler.setup

require 'haml/magic_translations/tasks'

$:.unshift File.join(File.dirname(__FILE__), 'lib')

Haml::MagicTranslations::Tasks::UpdatePoFiles.new(:updatepo) do |t|
 t.text_domain = 'coquelicot'
 t.files = Dir.glob("views/**/*.{rb,haml}") << "lib/coquelicot/app.rb"
 t.app_version = 'coquelicot 1.0.0'
end

desc "Create mo-files"
task :makemo do
  require 'gettext/tools'
  GetText.create_mofiles(:mo_root => './locale')
end
