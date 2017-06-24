<!--

$(document).ready(function(){
    $("h1.titlebar").each(setupNavButtons);
});
function setupNavButtons (index) {
    if (window != window.top) { // only run this in iframes
	var navbuttons = '<div class="navtool" id="ctrlpanel_back">&#9666;</div><div class="navtool" id="ctrlpanel_redo">&#8635;</div>';
	if (typeof helpurl != 'undefined') {
	    navbuttons = navbuttons + '<div class="navtool" id="ctrlpanel_help">?</div>';
	}
	navbuttons = navbuttons + '<div class="navtool" id="ctrlpanel_pop">&#9652;</div>';
	$(this).before('<div id="ctrlpanel_navtools">'+navbuttons+'</div>');
	$("#ctrlpanel_back").click(function(){
	    if(document.referrer){
		// this is more reliable than history.back(), but can end up circular
		window.location.href = document.referrer;
	    }
	});
	$("#ctrlpanel_redo").click(function(){
	    location.reload();
	});
	$("#ctrlpanel_pop").click(function(){
	    window.open(document.URL,"","width=800,height=600,resizable=yes,scrollbars=yes,location=yes,toolbar=yes,menubar=no,status=no");
	});
    }
}

//-->
