require 'net/imap'
module Coquelicot
  module Auth
    class ImapAuthenticator < AbstractAuthenticator
      def authenticate(params)
        imap = Net::IMAP.new(settings.imap_server, settings.imap_port, true)
        imap.login(params[:imap_user], params[:imap_password])
        imap.logout
        true
      rescue Errno::ECONNREFUSED
        raise Coquelicot::Auth::Error.new(
                  'Unable to connect to IMAP server')
      rescue NoMethodError => ex
        if [:imap_server, :imap_port].include? ex.name
          raise Coquelicot::Auth::Error.new(
                    "Missing '#{ex.name}' attribute in configuration.")
        else
          raise
        end
      end
    end
  end
end
