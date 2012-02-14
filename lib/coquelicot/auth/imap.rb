require 'net/imap'
module Coquelicot
  module Auth
    class ImapAuthenticator < AbstractAuthenticator
      def authenticate(params)
        imap = Net::IMAP.new(settings.imap_server, settings.imap_port, true)
        imap.login(params[:imap_user], params[:imap_password])
        imap.logout
        true
      rescue
        false
      end
    end
  end
end
