/*
 * lightboxFu
 *
 * Copyright (c) 2008 Piotr Sarnacki (drogomir.com)
 *
 * Licensed under the MIT license:
 *   http://www.opensource.org/licenses/mit-license.php
 *
 */

(function($) {
  $.extend($, {lightBoxFu: {}});
  $.extend($.lightBoxFu, {
    initialize: function (o) {
      if($('#lightboxfu').length == 0) {
	  	options = {stylesheetsPath: '/stylesheets/', imagesPath: '/images/'};
	  	jQuery.extend(options, o);
        html = '<div id="lightboxfu" style="display: none"><div id="lOverlay"><div id="lWindow"><div id="lInner"></div></div></div></div>';
        $('body').append(html);
		$('#lOverlay').css('background', 'url('+options.imagesPath+'overlay.png) fixed');
        
	$.lightBoxFu.appendStyle();
      }
    },
    open: function(options) {
      options = options || {};
      $('#lInner').html(options.html);
      $('#lightboxfu').show();
      var width = options.width || '250';
      $('#lInner').css({'width': width});
      
      if(options.closeOnClick != false) {
        $('#lOverlay').one('click', $.lightBoxFu.close);
      }
    },
    close: function() {
      $('#lightboxfu').hide();
    },
    appendStyle: function() {
      $('#lOverlay').css({display: 'table'});
      $('#lOverlay #lWindow').css({display: 'table-cell'});
      $('#lOverlay').css({position: 'fixed', top: 0, left: 0, width: "100%", height: "100%"});
      $('#lOverlay #lWindow').css({'vertical-align': 'middle'});
      $('#lOverlay #lInner').css({width: '300px', 'background-color': '#fff', '-webkit-border-radius': '10px', 'border-radius': '10px', '-moz-border-radius': '10px', 'max-height': '350px', margin: '0 auto', padding: '15px', overflow: 'auto'});
    }
  });
  
  $.extend($.fn, {
	  lightBoxFu: function(options){
		  return this.each(function() {
        $(this).click(function() {
			$.lightBoxFu.open(options);
          return false;
        });
      });
  }});
})(jQuery);

