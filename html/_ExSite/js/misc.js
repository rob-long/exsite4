<!--

// Miscellaneous useful javascript functions used by ExSite admin programs.


// ========================== POP-UPS ========================== //


function popup(url) {
  window.open(url,"","resizable,scrollbars=1,menubar=0,status=0")
}

function popup_small(url) {
  window.open(url,"","width=400,height=250,resizable,scrollbars=1,menubar=0,status=0")
}

function popup_medium(url) {
  window.open(url,"","width=640,height=480,resizable,scrollbars=1,menubar=0,status=0")
}

// add a location bar to large popups, since they are used for real work

function popup_large(url) {
  window.open(url,"","width=800,height=600,resizable=yes,scrollbars=yes,location=yes,toolbar=yes,menubar=no,status=no")
}

function popup_xlarge(url) {
  window.open(url,"","width=1024,height=768,resizable=yes,scrollbars=yes,location=yes,toolbar=yes,menubar=no,status=no")
}

function popup_custom(width,height,url) {
  window.open(url,"","width="+width+",height="+height+",resizable=yes,scrollbars=yes,menubar=no,status=no,toolbar=yes,location=yes")
}

// popup_image
// Usage:
//	popup_image(url)
// 		-url: image url
var popup_img_obj;
function popup_image(url){
	popup_img_obj = new Image();
	popup_img_obj.src = url;
	load_image();
}
function load_image(){
	var img_offset = 40;
	if (popup_img_obj.complete){
		var img_width = popup_img_obj.width + img_offset;
		var img_height = popup_img_obj.height + img_offset;
		window.open(popup_img_obj.src,"","resizable=0,width=" + img_width + ",height=" + img_height + ",scrollbars=1,menubar=0,status=0");
		popup_img_obj = null;
	}else{
		setTimeout("load_image()",500);
	}
}

// ======================= COOKIES ========================== //

function set_cookie(key,val,days,domain) {
	var expires = "";
	if (days) {
		var date = new Date();
		date.setTime(date.getTime()+(days*24*60*60*1000));
		expires = "; expires="+date.toGMTString();
	}
	var cookie = key+"="+val+expires+"; path=/";
	if (domain) {
		cookie = cookie + "; domain=" + domain;
	}
	document.cookie = cookie;
}

function get_cookie(name) {
	var nameEQ = name + "=";
	var cookies = document.cookie.split(';');
	for(var i=0;i < cookies.length;i++) {
		var c = cookies[i];
		while (c.charAt(0)==' ') c = c.substring(1,c.length);
		if (c.indexOf(nameEQ) == 0) return c.substring(nameEQ.length,c.length);
	}
	return null;
}

function del_cookie(name) {
	set_cookie(name,"",-1);
}

// ========================= DIALOGS ========================== //

function confirm_custom(message, url) {
	if(confirm(message)) {
		window.location=url;
	}
	return; // false;
}

// link/goto

function gotourl(url,frame) {
    if (frame) {
	top.frames[frame].location.href = url;
    }
    else {
	window.location.href = url;
    }
}

function gotourl(url,frame) {
    if (frame) {
	top.frames[frame].location.href = url;
    }
    else {
	window.location.href = url;
    }
}

//-->
