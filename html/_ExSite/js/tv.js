// Simple TreeView
// by Exware Solutions
//
// Usage:
// - create a <ul> list
// - any branches that should be closed by default should have class "closed"
//   on the li element
// - include jquery, jquery-ui, and this plugin file 
// - initialize with something like:
//   $(document).ready(function(){
//     $(".tv").simple_treeview(); // tv is the class of your main UL
//   });
//
// Use UI.css for default styling. To customize opener controls, target:
// .tv-opener - this is the control button; by default it is an 11x11 
//              box, positioned roughly where the bullet would be
// .tv-open - this controls the presentation when the branch is open
// .tv-closed - this controls the presentation when the branch is closed

(function ( $ ) {
$.fn.simple_treeview = function () {
    // initialize branches
    this.find("li").each(function () {
	if ($(this).hasClass("closed")) {
            $(this).prepend("<span class='tv-opener tv-closed'></span>");
            $(this).children("ul").hide();
	}
	else if ($(this).children("ul").length == 0) {
	    // no more branches
            $(this).prepend("<span class='tv-opener tv-null'></span>");
	}
	else {
            $(this).prepend("<span class='tv-opener tv-open'></span>");
	}
    });
    // open/close branches
    this.find(".tv-opener").click(function(){
	// toggle opener state
	if ($(this).hasClass("tv-open")) {
            $(this).removeClass("tv-open");
            $(this).addClass("tv-closed");
	}
	else {
            $(this).removeClass("tv-closed");
            $(this).addClass("tv-open");
	}
	// show/hide the branch
	$(this).parent().each(function () {
            if ($(this).hasClass("closed")) {
		$(this).removeClass("closed");
		$(this).children("ul").show("blind", { direction: "vertical" }, 300);
            }
            else {
		$(this).addClass("closed");
		$(this).children("ul").hide("blind", { direction: "vertical" }, 300);
            }
	});
    });
    return this;
}
} ( jQuery ));
