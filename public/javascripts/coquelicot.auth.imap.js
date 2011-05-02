function authenticationData(){
	return {
		imap_user: $('#imap_user').val(),
		imap_password: $('#imap_password').val()
	};
}

function authenticationFocus(){
	$('#imap_user').focus();
}
