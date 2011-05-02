$(function($) {  
  $.lightBoxFu.initialize({
    imagesPath: 'images/',
    stylesheetsPath: 'stylesheets/'
  });
  $('form#upload').uploadProgress({
    start:function() {
      // after starting upload open lightBoxFu with our bar as html
      $.lightBoxFu.open({
        html: '<div id="uploading"><span id="received"></span><span id="size"></span><br/><div id="progress" class="bar"><div id="progressbar">&nbsp;</div></div><span id="percent"></span></div>',
        width: "250px",
        closeOnClick: false
      });
      jQuery('#received').html(i18n.uploadStarting);
      jQuery('#percent').html("0%");
    },
    uploading: function(upload) {
      // update upload info on each /progress response
      jQuery('#received').html(i18n.uploading + parseInt(upload.received / 1024) + "/");
      jQuery('#size').html(parseInt(upload.size / 1024) + ' ' + i18n.kb);
      jQuery('#percent').html(upload.percents + "%");
    },
    interval: 2000,
    /* if we are using images it's good to preload them, safari has problems with
       downloading anything after hitting submit button. these are images for lightBoxFu
       and progress bar */
    preloadImages: ["images/overlay.png", "images/ajax-loader.gif"],
    jqueryPath: "javascripts/jquery.min.js",
    uploadProgressPath: "javascripts/jquery.uploadProgress.js",
    progressUrl: "progress"
  });
});
function authenticate() {
  var link = $('<a href="#" id="gen_pass" />');
  link.text(i18n.generateRandomPassword);
  var file_key = $('#file_key');
  file_key.after(link);
  link.click(function() {
    link.text(i18n.generatingRandomPassword);
    $.get('random_pass', function(pass) {
      file_key.val(pass);
      file_key.hide();
      var show = $('<div class="random-pass" />');
      show.text(pass);
      link.before(show);
      link.remove();
    });
  });

  var authForm = $('<form></form>')
  var authDiv = $('#upload-authentication').remove();
  var lb = $.lightBoxFu;
  authForm.bind('submit', function() {
    jQuery.ajax({
      type: 'POST',
      url: 'authenticate',
      dataType: 'text',
      data: {
        'upload_token': authenticationData.call()
      },
      complete: function(res, status) {
        if (status === 'success') {
          var hiddenField = $('<input type="hidden" name="upload_token" />');
          hiddenField.val(JSON.stringify(authenticationData.call()));
          $('#upload').append(hiddenField);
          lb.close();
        } else if (res.responseText == 'Forbidden') {
          $('#auth-message').text(i18n.pleaseTryAgain);
        } else {
          $('#auth-message').text(i18n.error + alert(status));
        }
        authenticationReset();
      }
    });
    return false;
  });
  lb.open({
    html: authForm.append(authDiv).append('<div id="auth-message"></div>'),
    width: "300px",
    closeOnClick: false
  });
  authenticationFocus();
}

function authenticationReset(){
    $('#upload_token').val('');
}
