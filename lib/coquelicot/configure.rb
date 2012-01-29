module Coquelicot::Configure
  def self.included(c)
    c.extend ClassMethods
    c.configure
  end

  module ClassMethods
    def configure
      user_settings = load_user_settings if File.exists?(settings_path)
      merged_settings = default_settings.merge(user_settings || {})
      merged_settings.each { |k,v| set k,v }
    end

    def authentication_method=(options)
      method = options.delete('name') || options.delete(:name)
      method = method.to_s if method.is_a? Symbol
      require "coquelicot/auth/#{method}"
      set :authenticator, Coquelicot::Auth.
         const_get("#{method.to_s.capitalize}Authenticator").new(self)
      options.each{|k,v| set k,v }
    end

  private

    def default_settings
      {
        'default_expire' => 60,
        'maximum_expire' => 60 * 24 * 30, # 1 month
        'gone_period' => 10080,
        'filename_length' => 20,
        'random_pass_length' => 16,
        'about_text' => '',
        'additional_css' => '',
        'depot_path' => Proc.new { File.join(root, 'files') },
        'authentication_method' => {
          'name' => 'simplepass',
          'upload_password' => 'a94a8fe5ccb19ba61c4c0873d391e987982fbbd3'
        },
      }
    end

    def settings_path
      @settings_path ||= File.join(File.dirname(__FILE__),'..','..','conf','settings.yml')
    end

    def load_user_settings
      YAML.load(File.read(settings_path))
    end
  end
end
