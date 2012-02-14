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

$(document).ready(function() {
  $('#imap-auth-submit').remove();
  var submit = $('<input type="submit" />');
  submit.attr('value', 'Login');
  submit.attr('id', 'imap-auth-submit');
  $('#upload-authentication').append(
    $('<div class="field" />').append(
      $('<div class="submit" />').append(
        submit)));
});
