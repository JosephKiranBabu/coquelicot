module Coquelicot
  module Auth
    module Extension
      def authentication_method=(options)
        method = options.delete('name') || options.delete(:name)
        method = method.to_s if method.is_a? Symbol

        require "coquelicot/auth/#{method}"
        set :authenticator, Coquelicot::Auth.
           const_get("#{method.to_s.capitalize}Authenticator").new(self)

        options.each{|k,v| set k,v }
      end
    end

    class Error < StandardError; end

    class AbstractAuthenticator
      def initialize(app)
        @app = app
      end

      def settings
        @app
      end

      def authenticate(params)
        raise NotImplementedError.new('Authenticator needs to override the `authenticate` method!')
      end
    end
  end
end
