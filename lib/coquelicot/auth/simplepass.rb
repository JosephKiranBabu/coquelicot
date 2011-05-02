module Coquelicot
  module Auth
    module Simplepass

      def authenticate(params)
        return TRUE if settings.upload_password.nil?
        upload_password = params['upload_token'].is_a?(Hash) ? params['upload_token']['upload_password'] : params['upload_password']
        (not upload_password.nil?) && Digest::SHA1.hexdigest(upload_password) == settings.upload_password
      end
    end
  end
end