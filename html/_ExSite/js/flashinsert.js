// IE hack for Flash - dynamically reinsert Flash objects
flobj=document.getElementsByTagName('object');
for (var i=0; i<flobj.length; ++i) flobj[i].outerHTML=flobj[i].outerHTML;
