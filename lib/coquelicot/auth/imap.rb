require 'net/imap'
module Coquelicot
  module Auth
    class ImapAuthenticator < AbstractAuthenticator
      def authenticate(params)
        p = params['upload_token'].is_a?(Hash) ? params['upload_token'] : params
        imap = Net::IMAP.new(settings.imap_server, settings.imap_port, true)
        imap.login(p['imap_user'],p['imap_password'])
        imap.logout
        true
      rescue
        false
      end
    end
  end
end
