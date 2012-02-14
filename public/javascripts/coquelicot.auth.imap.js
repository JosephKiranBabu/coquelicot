var authentication = {
  getData: function() {
    return {
      imap_user: $('#imap_user').val(),
      imap_password: $('#imap_password').val()
    };
  },
  focus: function() {
    $('#imap_user').focus();
  },
  handleReject: function() {
    $('#imap_user').val('');
    $('#imap_password').val('');
  },
};
