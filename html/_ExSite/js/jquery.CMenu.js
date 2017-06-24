(function($){
	$.CMenu = function(option){
		$("ul#CMenu > li > ul").hide();
		var vertical_menu = $("ul#CMenu").hasClass("CMenu_vertical") ? true : false;
		$(".CMenu li").hover(function(){
			if (vertical_menu){
				$(this).find("ul:first").css({"position" : "absolute","top" : "0px","left" : $(this).find("a.menu:first").width() + "px"});
			}else{
				if (!$(this).parent().hasClass("CMenu")){
					$(this).find("ul:first").css({"position" : "absolute","top" : "0px","left" : $(this).find("a.menu:first").width() + "px"});
				}
			}
			$(this).find("ul:first").css("z-index","1000").show();
		},function(){
			$(this).find("ul:first").css("z-index","0").hide();
		});
	}
})(jQuery);
