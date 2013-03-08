/*
 * Coquelicot: "one-click" file sharing with a focus on users' privacy.
 * Copyright © 2012-2013 potager.org <jardiniers@potager.org>
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
