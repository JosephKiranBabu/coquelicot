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
      jQuery('#received').html("Upload starting.");
      jQuery('#percent').html("0%");
    },
    uploading: function(upload) {
      // update upload info on each /progress response
      jQuery('#received').html("Uploading: " + parseInt(upload.received / 1024) + "/");
      jQuery('#size').html(parseInt(upload.size / 1024) + " kB");
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
$(document).ready(function() {
  var link = $('<a href="#" id="gen_pass" />');
  link.text(generateRandomPassword);
  var file_key = $('#file_key');
  file_key.after(link);
  link.click(function() {
    link.text(generatingRandomPassword);
    $.get('random_pass', function(pass) {
      file_key.val(pass);
      file_key.hide();
      var show = $('<div class="random-pass" />');
      show.text(pass);
      link.before(show);
      link.remove();
    });
  });
});
