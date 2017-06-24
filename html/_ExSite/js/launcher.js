<!--

// to make an app launching link, use a click target with class '.appLaunchLink' and
// id 'app_PLUGINNAME'.

$(document).ready(function(){
    $(".appLaunchLink").click(function(){
	var app = this.id.split("_")[1];
	if (app) {
	    launchApp(app);
	}
	else {
	    alert("Error: no app to launch!");
	}
    });
    $("#newapp").click(function(event){raiseApp(event,"newapp");});
});

// launch a plugin app
// url = url of app ctrl panel
// mode = 
//   0 => direct link
//   1 => target="_blank" (new window/browser tab)
//   2 => popup
//   3 => admin tab
// size = small, medium, large, x-large
// name = module name
// title = human-friendly module name

function launchApp(name) {
    var App;
    var context;
//    alert("launching "+name);
    if (typeof Apps === 'undefined') {
	// not in original launcher window
	if (typeof parent.Apps === 'undefined') {
	    // unknown context, open app in new window
	    var url = window.location.href;
	    var newurl = url.replace(/ex\.cgi\/admin\/.*/,"ex.cgi/admin/"+name);
	    window.open(newurl);
	    return;
	}
	// iframe launch
	App = parent.Apps[name];
	context = window.parent;
	// use window.opener.parent in popup?
    }
    else {
	// direct launch
//	alert("direct launch");
	App = Apps[name];
	context = window;
    }

    launchAppFromContext(name,App,context);
    return;
}

// launchAppFromContext: context is window (for same document), 
// window.opener (for popups), window.parent (for iframes)

function launchAppFromContext(name,App,context) {
    App.count++;
    var loc = name + "_" + App.count;
//    alert(loc);
    var title = App.title;
    var url = App.url;

    // lose current tab focus
    context.$(".thisApp").toggleClass("thisApp");

    // make a tab
//    context.$("#appinfo").prepend('<div class="appTab thisApp" id="tab_'+loc+'"><span class="appClose fa fa-fw fa-close"></span><span class="appName">'+title+'</span><span class="appIcon"></span><span class="appHere fa fa-fw fa-play fa-inverse"></span></div>');
    context.$("#appinfo").prepend('<div class="appTab thisApp" id="tab_'+loc+'"><span class="appClose fa fa-fw fa-close"></span><span class="appName">'+title+'</span></div>');
    // install new tab click handlers
    context.$("#tab_" + loc).click(function(event){raiseAppFromContext(event,"tab_"+loc,context);});
// close handler
    context.$("#tab_" + loc).find(".appClose").click(function(event){closeAppFromContext(event,"tab_"+loc,context);});

    // hide all appboxes
    context.$('div.app').hide();

    // make a new appbox
    context.$("div#ExSiteAdmin").prepend('<div class="app" id="app_' + loc + '"><iframe class="appframe" src="' + url + '"></iframe></div>');
}

function raiseApp(event,id) {
    // assume same window context
    raiseAppFromContext(event,id,window);
}

function raiseAppFromContext(event,id,context) {
//    alert("raise "+id);
    context.$(".thisApp").toggleClass("thisApp");  // defocus current tab
    context.$("#"+id).toggleClass("thisApp");       // focus new tab
    context.$("div.app").hide();                     // hide current app
    if (id === "newapp") {
	// show launcher
	context.$("div#app_new").show();                 // show launcher
    }
    else {
	// show app
	var appbox = id.replace("tab","app");
//	alert("raising "+appbox);
	context.$("#"+appbox).show();
    }
    event.stopPropagation();
}

function closeAppFromContext(event,id,context) {
//    alert("closing "+id);
    event.stopPropagation();
    var nextid = context.$("#"+id).next().attr("id");
//    alert("next = "+nextid);
    context.$("#"+id).detach(); // remove tab
    var appbox = id.replace("tab","app");
//    alert("closing pane "+appbox);
    context.$("#"+appbox).detach(); // remove appbox

// FIXME: do not raiseApp if we closed a lowered app

//    alert("opening "+nextid);
    raiseAppFromContext(event,nextid,context);
    return;
}


//-->
