// ExSite::UI controls

// the following global variables should be defined before using
// these functions

var BASE; // HTML base dir
var current_tab; // preselected tab on DynTabBox

// setup popups

$(document).ready(function(){
    $(".PopupLink").click(function(){open_popup(this);});
});
$(document).ready(function(){
    $(".ToolTipLink").hover(
        function(){open_tooltip(this);},
        function(){close_tooltip(this);}
        );
});

// popups

function open_popup (obj) {
    var idname = $(obj).attr("href").split("#").pop();
    var id = "#" + idname; 
    //$(id).css("display:block;");//show();
    $(id).show();
    if ($(id).find(".PopupClose").length == 0) {
        // add a close link if one does not exist
        if ($(id).hasClass("PopupOverlay")) { 
            $(id).find(".PopupOverlayBox").prepend("<div class='PopupClose'></div>");
        }
        else {
            $(id).prepend("<div class='PopupClose'></div>");
        }
        $(".PopupClose").click(close_popup);
    }
}
function open_tooltip (obj) {
    var idname = $(obj).attr("href").split("#").pop();
    var id = "#" + idname;
    $(id).show();
}
function close_popup () {
    if ($(this).parent().hasClass("PopupOverlayBox")) { 
        $(this).parent().parent().hide();
    }
    else {
        $(this).parent().hide();
    }
}
function close_tooltip (obj) {
    var id = $(obj).attr("href").split("#").pop();
    $("#"+id).hide();
}

// CSS Popups - deprecated

function showpopup(popid) {
    var loc = document.getElementById(popid);
    loc.style.display="block";
}
function hidepopup(popid) {
    var loc = document.getElementById(popid);
    loc.style.display="none";
}

// Confirmation dialog

function confirm_custom(message, url) {
    if(confirm(message)) {
	window.location=url;
    }
    return; // false;
}

// Email obfuscator

function mailto(user,domain,anchor) {
    var addr = user + '@' + domain;
    if (! anchor) {
	anchor = addr;
    }
    document.write('<a href="mai' + 'lto:' + addr + '">' + anchor + '</a>');
}

// DynTabBox tab switcher

function loadtab(pane,tab) {
    // hide old pane
    var loc = document.getElementById("dyntabpane"+current_tab);
    loc.style.overflow = "hidden";
    loc.style.height = "0px";
    // show new pane
    var newtabpane = "dyntabpane" + pane;
    var loc = document.getElementById(newtabpane);
    loc.style.overflow = "visible";
    loc.style.height = "auto";
    // shade old tab
    var loc = document.getElementById("tab"+current_tab);
    loc.className = "tab";
    // highlight new tab
    tab.className = "tab thistab";
    // save new current tab
    current_tab = pane;
}

// AccordionBox open/close

function accordion_expand(id) {
    var iconid = "accordioncontrolicon" + id;
    var loc = document.getElementById(iconid);
    loc.innerHTML = "<img src='" + BASE + "/_ExSite/images/darr.png'>";
    var controlid = "accordioncontrol" + id;
    document.getElementById(controlid).onclick= function() { accordion_contract(id); }
    var paneid = "accordionpane" + id;
    var loc=document.getElementById(paneid);
    loc.style.display="block";
}
function accordion_contract(id) {
    var iconid = "accordioncontrolicon" + id;
    var loc = document.getElementById(iconid);
    loc.innerHTML = "<img src='" + BASE + "/_ExSite/images/rarr.png'>";
    var controlid = "accordioncontrol" + id;
    document.getElementById(controlid).onclick= function() { accordion_expand(id); }
    var paneid = "accordionpane" + id;
    var loc=document.getElementById(paneid);
    loc.style.display="none";
}

// DynList expand/contract

function list_expand(id) {
    var controlid = "listcontrol_" + id;
    var sublist = "list_" + id;
    var loc = document.getElementById(controlid);
    loc.innerHTML = "<a class='listcontrol' href='javascript:list_contract("+id+")'><img src='"+BASE+"/_ExSite/images/darr.gif'></a>";
    var loc=document.getElementById(sublist);
    loc.style.display="block";
}
function list_contract(id) {
    var controlid = "listcontrol_" + id;
    var sublist = "list_" + id;
    var loc = document.getElementById(controlid);
    loc.innerHTML = "<a class='listcontrol' href='javascript:list_expand("+id+")'><img src='"+BASE+"/_ExSite/images/rarr.gif'></a>";
    var loc=document.getElementById(sublist);
    loc.style.display="none";
}

// rollup/blind functions

function blindbox_rollup() {
    $(".blindbox .boxhead").click(function () {
	    var pane = $(this).parent().find(".boxpane");
	    if ($(this).hasClass("paneClosed")) {
		pane.show("blind", { direction: "vertical" }, 500);
	    }
	    else {
		pane.hide("blind", { direction: "vertical" }, 500);
	    }
	    $(this).toggleClass("paneClosed"); 
	});
}

function accordionbox_rollup() {
    $(".blindbox .boxhead").click(function () {
	    var pane = $(this).parent().find(".boxpane");
	    if ($(this).hasClass("paneClosed")) {
		pane.show("blind", { direction: "vertical" }, 500);
	    }
	    else {
		pane.hide("blind", { direction: "vertical" }, 500);
	    }
	    $(this).toggleClass("paneClosed"); 
	});
}
