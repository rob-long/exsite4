<!--

// ToDo:
// username


var postFormHtml = "<form id='commentForm_:ID:'>"+
"<p>From:<br>"+
"<input type='text' name='from' size='40' value=':FROM:'></p>"+
"<p>Subject:<br>"+
"<input type='text' name='subject' size='40' value=':SUBJECT:'></p>"+
"<p>Comment:<br>"+
"<textarea name='comment' rows=8 cols=60></textarea></p>"+
"<input type='hidden' name='id' value=:ID:>"+
"<button id='commentSubmitButton_:ID:' type='button' class='commentSubmitButton'>Submit</button>"+
"<button id='commentCancelButton_:ID:' class='commentCancelButton' type='button'>Cancel</button>"+
"</form>";

var replyFormHtml = "<form id='commentForm_:ID:'>"+
"<p>From:<br>"+
"<input type='text' name='from' size='40' value=':FROM:'></p>"+
"<p>Comment:<br>"+
"<textarea name='comment' rows=8 cols=60></textarea></p>"+
"<input type='hidden' name='id' value=:ID:>"+
"<button id='commentSubmitButton_:ID:' type='button' class='commentSubmitButton'>Submit</button>"+
"<button id='commentCancelButton_:ID:' class='commentCancelButton' type='button'>Cancel</button>"+
"</form>";

var id; // comment parent id global
//var from = "anonymous";
var subject = "";
$(document).ready(function(){
    $(".commentReplyButton").click(function(){
	id = this.id.split("_")[1];
	$(this).hide();
	$(this).siblings(".commentBox").each(setupReply);
    });
    $(".commentPostButton").click(function(){
	id = this.id.split("_")[1];
	$(this).hide();
	$(this).siblings(".commentBox").each(setupPost);
    });
    $(".commentModerateButton").click(function(){
	// need comment ID, status
	var cid = this.id.split("_")[1];
	var status = $(this).attr("value");
	moderateComment(this,cid,status);
    });
});
function setupPost (index) {
    setupComment($(this),index,postFormHtml,"");
    $(this).find(".commentCancelButton").click(cancelPost);
}
function setupReply_old (index) {
    var comment = $(this).parents(".commentWrapper");
    subject = "Re: " + comment.find(".commentSubject").html();
    formhtml = replyformhtml.replace(/:ID:/g,id);
    formhtml = formhtml.replace(/:FROM:/g,from);
    formhtml = formhtml.replace(/:SUBJECT:/g,subject);
    $(this).html(formhtml);
    $(this).show("blind", { direction: "vertical" }, 500);
    $(this).find(".commentSubmitButton").click(postComment);
    $(this).find(".commentCancelButton").click(cancelComment);
}
function setupReply (index) {
    setupComment($(this),index,replyFormHtml);
    $(this).find(".commentCancelButton").click(cancelReply);
}
function setupComment (el,index,template,subject) {
    var comment = el.parents(".commentWrapper");
    if (typeof subject === 'undefined') {
	subject = "Re: " + comment.find(".commentSubject").html();
    }
    var from = username();
    formhtml = template.replace(/:ID:/g,id);
    formhtml = formhtml.replace(/:FROM:/g,from);
    formhtml = formhtml.replace(/:SUBJECT:/g,subject);
    el.html(formhtml);
    el.show("blind", { direction: "vertical" }, 500);
    el.find(".commentSubmitButton").click(postComment);
    //el.find(".commentCancelButton").click(cancelComment);
}
function cancelPost () {
    id = this.id.split("_")[1];
    //alert("cancel comment "+id);
    var tools = $(this).parents(".commentTools");
    tools.find(".commentPostButton").show();
    tools.find(".commentPostButton").show();
    tools.find(".commentBox").hide("blind", { direction: "vertical" }, 300);
}
function cancelReply () {
    id = this.id.split("_")[1];
    //alert("cancel comment "+id);
    var tools = $(this).parents(".commentTools");
    tools.find(".commentReplyButton").show();
    tools.find(".commentReplyButton").show();
    tools.find(".commentBox").hide("blind", { direction: "vertical" }, 300);
}
function cancelComment () { // deprecated
    id = this.id.split("_")[1];
    //alert("cancel comment "+id);
    var tools = $(this).parents(".commentTools");
    tools.find(".commentReplyButton").show();
    tools.find(".commentReplyButton").show();
    tools.find(".commentBox").hide("blind", { direction: "vertical" }, 300);
}
function postComment () {
    elid = this.id.split("_")[1];
    //alert("post comment "+id);
    var form = document.getElementById("commentForm_"+elid);
    //alert(form.comment.value);
    
    // also post the cookie data

    var cbox_id = "commentBox_"+elid;
    if (typeof posturl != 'undefined') {
	var cookie = document.cookie;
	var cdata = cookie.replace(/&/g,"%26")
	cdata = cdata.replace(/=/g,"%3D")
	cdata = cdata.replace(/ /g,"+")
	var id = elid.replace(/reply/,"");
	id = id.replace(/post/,"");
	var posturlid = posturl + "?_bare=2&_id=" + id + "&_cookie=" + cdata;
	subRequestData_Post(form,cbox_id,posturlid);
    }
    else {
	var cbox = document.getElementById(cbox_id);
	cbox.innerHTML = "Error: No post URL.";
    }
    // need to post to the page???
}
function username () {
    // extract name from cookiedata
    var cookie = document.cookie;
    var uid_start = cookie.indexOf(" " + c_uid + "=");
    if (uid_start == -1) {
	uid_start = cookie.indexOf(c_uid + "=");
    }
    if (uid_start == -1) {
	// not logged in
	return "";
    }
    uid_start = cookie.indexOf("=", uid_start) + 1;
    var uid_end = cookie.indexOf(";", uid_start);
    if (uid_end == -1) {
	uid_end = cookie.length;
    }
    var uid = unescape(cookie.substring(uid_start,uid_end));
    // fields are login_id:pwd_hash:full_name (last is optional)
    var uid_field = uid.split(":");
    if (typeof uid_field[2] != 'undefined') {
	return uid_field[2];
    }
    else {
	// no full-name field, use login ID
	return uid_field[0];
    }
}
function moderateComment (obj,id,status) {
    //alert(status + " " + id);
    var toolbox = $('#' + "commentTools_" + id);
    toolbox.html("updating...");
    //document.getElementById(toolboxid).innerHTML = "updating...";
    var postdata = "mod=" + status;
    if (typeof posturl != 'undefined') {
	var cookie = document.cookie;
	var cdata = cookie.replace(/&/g,"%26")
	cdata = cdata.replace(/=/g,"%3D")
	cdata = cdata.replace(/ /g,"+")
	var modurlid = posturl + "?_bare=2&_id=" + id + "&_cookie=" + cdata;
	sendAsyncPost(modurlid,"commentTools_"+id,postdata);
    }
    else {
	var cbox = document.getElementById(cbox_id);
	cbox.innerHTML = "Error: No post URL.";
    }
}
// custom AJAX post tool
function sendAsyncPost(url,id,postdata) {
    var xmlObj = createRequestObj(); // from httprequest.js
    xmlObj.onreadystatechange= function() { 
        if (xmlObj.readyState==4)
            if (xmlObj.status==200)
                updateTools(xmlObj, id);
    }
    xmlObj.open("POST",url,false);
    xmlObj.setRequestHeader("Content-type", "application/x-www-form-urlencoded");
    //xmlObj.setRequestHeader("Content-length", postdata.length);
    //xmlObj.setRequestHeader("Connection", "close");
    xmlObj.send(postdata);
    return xmlObj;
}
// writeHTML - async callback to insert result into page
function updateTools(req, id) {
    //document.getElementById(id).innerHTML = req.responseText;
    var tools = $('#' + id);
    tools.html(req.responseText);
    tools.find(".commentModerateButton").click(function(){
	// need comment ID, status
	var cid = this.id.split("_")[1];
	var status = $(this).attr("value");
	//alert("adding click handler "+cid+" -> "+status);
	moderateComment(this,cid,status);
    });
}

//-->
