/*
 * Coquelicot: "one-click" file sharing with a focus on users' privacy.
 * Copyright © 2010-2012 potager.org <jardiniers@potager.org>
 *           © 2011 mh / immerda.ch <mh+coquelicot@immerda.ch>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

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
    success: function(upload) {
      $('#received').html('');
      $('#size').html('');
      $('#percent').html("100%");
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

function addLinkToPasswordGenerator() {
  var link = $('<a href="#" id="gen_pass" />');
  link.text(i18n.generateRandomPassword);
  var file_key = $('#file_key');
  file_key.after(link);
  link.click(function(e) {
    e.preventDefault();
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
}

function authenticate() {
  var authForm = $('<form></form>')
  var authDiv = $('#upload-authentication').remove();
  var lb = $.lightBoxFu;
  authForm.bind('submit', function() {
    jQuery.ajax({
      type: 'POST',
      url: 'authenticate',
      dataType: 'text',
      data: authentication.getData(),
      success: function(data, textStatus, jqXHR) {
        if (data != 'OK') {
          /* Mh. Something strange happened. */
          return;
        }
        var hiddenFields = $('<div />')
        $.each(authentication.getData(), function(key, value) {
          var hiddenField = $('<input type="hidden" />');
          hiddenField.attr('name', key);
          hiddenField.val(value);
          hiddenFields.append(hiddenField)
        });
        $('#upload').prepend(hiddenFields);
        lb.close();
        if (authentication.handleAccept) {
          authentication.handleAccept();
        }
      },
      error: function(jqXHR, textStatus, errorThrown) {
        switch (jqXHR.status) {
          case 403:
            $('#auth-message').text(i18n.pleaseTryAgain);
            if (authentication.handleReject) {
              authentication.handleReject();
            }
            return;
          default:
            $('#auth-message').
              empty().
              append($('<div />').text(i18n.error)).
              append($('<div />').append($('<strong />').text(errorThrown))).
              append($('<div />').text(jqXHR.responseText));
            if (authentication.handleFailure) {
              authentication.handleFailure(textStatus);
            }
        }
      },
    });
    return false;
  });
  lb.open({
    html: authForm.append(authDiv).append('<div id="auth-message"></div>'),
    width: "430px",
    closeOnClick: false
  });
  authentication.focus();
}
