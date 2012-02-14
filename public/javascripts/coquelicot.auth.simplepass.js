function authenticationData(){
  return {
    upload_password: $('#upload_password').val()
  };
}

function authenticationFocus(){
  $('#upload_password').focus();
}

function authenticationReset() {
  $('#upload_password').val('');
}
