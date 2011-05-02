module Coquelicot::Configure
  
  def self.included(c)
    c.extend ClassMethods
    c.configure
  end
  
  module ClassMethods
    def configure
      user_settings = File.exists?(settings_path) ? load_user_settings : {}
      default_settings.delete('authentication_method') if user_settings['authentication_method']
      merged_settings = default_settings.merge(user_settings)
      if (authm=merged_settings.delete('authentication_method'))
        authentication_method authm.delete('name'), authm
      end
      merged_settings.each{|k,v| set k,v }
    end
    private
    def authentication_method(method,options={})
      require "coquelicot/auth/#{method}"
      set :auth_method, method
      include (eval "Coquelicot::Auth::#{method.to_s.capitalize}")
      options.each{|k,v| set k,v }
    end
    def default_settings
      {
        'default_expire' => 60,
        'maximum_expire' => 60 * 24 * 30, # 1 month
        'gone_period' => 10080,
        'filename_length' => 20,
        'random_pass_length' => 16,
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