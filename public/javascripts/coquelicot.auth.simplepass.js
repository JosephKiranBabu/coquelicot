var authentication = {
  getData: function() {
    return {
      upload_password: $('#upload_password').val()
    };
  },
  focus: function() {
    $('#upload_password').focus();
  },
  handleAccept: function() { alert('success!'); },
  handleReject: function() {
    $('#upload_password').val('');
  },
  handleFailure: function(status) { alert('failure!' + status); },
};
