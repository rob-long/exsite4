<!--

// Basic AJAX/HttpRequest object

function createRequestObj(){
    var myObj = null;
    try{
	myObj = new ActiveXObject("Msxml2.XMLHTTP");
    } catch(e1) {
	try{
	    myObj = new ActiveXObject("Microsoft.XMLHTTP");
	} catch(e2){			
	    myObj = null;
	}
    }	
    if(!myObj && typeof XMLHttpRequest != "undefined"){
	myObj = new XMLHttpRequest();
    }
    return myObj;
}

// AJAX/HttpRequest Methods for simple GETs

function sendHttpRequest(url){
    var xmlObj = createRequestObj();
    xmlObj.open("GET",url,false);
    xmlObj.send(null);
    return xmlObj;
}
function getRequestData(url){
    var result, myObj;
    myObj = sendHttpRequest(url);
    if (myObj.status == 200) {
	result = myObj.responseText;
    }
    else {
	result = "<p class=error>Problem: " + url + " - " + myObj.statusText + "</p>\n";
    }
    return result;
}
function subRequestData(id,url){
    var data = getRequestData(url);
    var loc = document.getElementById(id);
    loc.innerHTML = data;
}

// AJAX/HttpRequest Methods for asynchronous GETs

function sendHttpRequestAsync(url, id){
    var xmlObj = createRequestObj();
    xmlObj.onreadystatechange= function() { 
        if (xmlObj.readyState==4)
            if (xmlObj.status==200)
                writeHTML(xmlObj, id);
    }
    xmlObj.open("GET",url,true);
    xmlObj.send(null);
    return xmlObj;
}
function getRequestDataAsync(url, id){
    var myObj;
    url += '&' + myTimestamp();
    myObj = sendHttpRequestAsync(url, id);
    return "";
}

// AJAX/HttpRequest Methods for POSTS

// AJAX forms can use this for their submit button:
// <input type="button" value="Submit" onclick="javascript:subRequestData_Post(this.parentNode,destination_div_id,post_url);">
// <input type="button" value="Submit" onclick="javascript:getRequestDataAsync_Post(this.parentNode,destination_div_id,post_url);">

function sendHttpRequest_Post(url,postdata){
    var xmlObj = createRequestObj();
    xmlObj.open("POST",url,false);
    xmlObj.setRequestHeader("Content-type", "application/x-www-form-urlencoded");
    //xmlObj.setRequestHeader("Content-length", postdata.length);
    //xmlObj.setRequestHeader("Connection", "close");
    xmlObj.send(postdata);
    return xmlObj;
}
function getRequestData_Post(obj,url) {
    var result, myObj;
    var postdata = "";
    var f = obj;
    //var f = document.myform;
    for (var i=0; i < f.elements.length; i++) {
        var formel = f.elements[i];
	if (i > 0) { postdata = postdata + "&"; }
        postdata = postdata + formel.name + "=" + encodeURI( formel.value );
    }
    myObj = sendHttpRequest_Post(url,postdata);
    if (myObj.status == 200) {
	result = myObj.responseText;
    }
    else {
	result = "<p class=error>Problem: " + url + " - " + myObj.statusText + "</p>\n";
    }	
    return result;
}
function subRequestData_Post(form,id,url){
    var data = getRequestData_Post(form,url);
    var loc = document.getElementById(id);
    loc.innerHTML = data;
}

// ditto, for asynchronous posts

function sendHttpRequestAsync_Post(url,id,postdata){
    var xmlObj = createRequestObj();
    xmlObj.onreadystatechange= function() { 
        if (xmlObj.readyState==4)
            if (xmlObj.status==200)
                writeHTML(xmlObj, id);
    }
    xmlObj.open("POST",url,false);
    xmlObj.setRequestHeader("Content-type", "application/x-www-form-urlencoded");
    //xmlObj.setRequestHeader("Content-length", postdata.length);
    //xmlObj.setRequestHeader("Connection", "close");
    xmlObj.send(postdata);
    return xmlObj;
}
function getRequestDataAsync_Post(form,id,url) {
    var myObj;
    url += '&' + myTimestamp();
    var postdata = getPostData(form);
    alert("post " + postdata + " to " + url + " and sub to " + id);
    return "";
    myObj = sendHttpRequestAsync_Post(url, id, postdata);
    return "";
}

// dispatch: gang multiple AJAX calls into a single request; 
// return results in a JSON structure

function dispatch(url,post) {
    // post ignored for now
    var dispraw = getRequestData(url); // JSON struct
    var dispdata = eval ('(' + dispraw + ')'); // convert to JS struct
    for (var id in dispdata) {
	var loc = document.getElementById(id);
	loc.innerHTML = dispdata[id];
    }
}

// misc functions

// getPostData - assemble form data into an encoded string
function getPostData(f) {
    var postdata = "";
    for (var i=0; i < f.elements.length; i++) {
        var formel = f.elements[i];
	if (i > 0) { postdata = postdata + "&"; }
        postdata = postdata + formel.name + "=" + encodeURI( formel.value );
    }
    return postdata;
}
// writeHTML - async callback to insert result into page
function writeHTML(req, id) {
    document.getElementById(id).innerHTML = req.responseText;
}

// myTimestamp - returns a timestamp. used to avoid IE caching Ajax requests
function myTimestamp(){
    tstmp = new Date();
    return tstmp.getTime();
}

//-->
