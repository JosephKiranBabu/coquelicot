module Coquelicot
  module Auth
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
