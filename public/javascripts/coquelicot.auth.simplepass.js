var authentication = {
  getData: function() {
    return {
      upload_password: $('#upload_password').val()
    };
  },
  focus: function() {
    $('#upload_password').focus();
  },
  handleReject: function() {
    $('#upload_password').val('');
  },
};
