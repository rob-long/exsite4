// you should defined these variables before including this file:
// var base_pwd_strength = 5;
// var min_pwd_strength = 1;
// var login_cookie = "ExSiteID";
// Change the values to what is appropriate for your site.


///////// integrate with ExSite::Auth::set_password

var words = new Array(
'able','ably','ace','ache','acing','act','add','ado','ads','aft',
'age','ago','ague','aid','ail','aim','air','ale','all','alter',
'amble','amp','anal','and','anger','angle','ani','ant','any','ape',
'apse','apt','arc','are','ark','arm','art','ash','ask','asp',
'ass','aster','ate','aunt','aver','awe','awl','axe','aye','back',
'bad','bag','ban','bar','base','bat','bed','bee','beg','best',
'bet','bid','big','bin','bit','bloc','blur','boa','bomb','bond',
'boo','bound','bow','box','boy','bra','buck','bud','buff','bug',
'bull','bum','bun','bur','bus','but','cab','cad','calm','cam',
'can','cap','car','cast','cat','cave','cede','cent','char','chi',
'cite','city','cock','cod','comb','come','con','coo','cop','cord',
'corn','cost','cot','count','cove','cow','cross','cry','cue','cup',
'cur','cut','cycle','dam','day','deal','deb','deli','den','dew',
'dial','die','dig','dim','din','dip','dis','dive','doc','dog',
'don','door','dot','drop','duct','due','dust','each','ear','ease',
'east','eat','eave','edge','edit','eel','egg','ego','eight','eke',
'elect','elf','ell','ems','end','enter','eon','era','ere','erg',
'err','ester','eta','etch','eve','evil','ewe','expo','eye','fan',
'far','fast','fat','fed','fee','fen','fer','fest','fie','fig',
'file','fin','fir','fish','fit','fix','flat','flu','fly','fog',
'foot','for','foul','free','fresh','fro','full','fun','fur','gab',
'gag','gain','gal','gas','gel','gene','gent','get','gig','gin',
'give','god','goo','got','grad','gun','hack','had','ham','hang',
'hard','harp','has','hat','have','haw','head','heap','heck','help',
'hem','hen','her','hes','hew','hick','hid','hie','high','him',
'hip','his','hit','hive','hoe','hole','home','hook','hoot','hop',
'horn','hos','hot','hove','how','hum','hut','ice','ides','idle',
'idly','ids','ilk','ill','imp','inch','ink','inn','ins','inter',
'ion','ire','irk','iron','ism','itch','its','jack','join','joy',
'just','ken','key','kid','kin','kit','lab','lack','lad','lag',
'lain','lam','lance','lane','lank','lap','last','law','lax','lay',
'laze','lea','led','lee','leg','lent','less','lest','let','lib',
'lick','lid','lie','lift','light','like','limb','lime','line','lip',
'list','lit','live','load','lob','lock','log','long','look','loom',
'lop','lose','loss','lot','loud','love','low','luck','lug','lung',
'lush','lust','lute','lying','mad','main','man','mar','mas','mat',
'mean','meg','men','mes','met','mid','mil','mind','mine','mini',
'miss','mist','mitt','mix','mock','mod','moo','mote','moth','mount',
'move','mud','mum','mute','nab','nag','name','nap','nary','need',
'nest','net','new','nick','nigh','nine','nip','nit','nod','non',
'nor','not','now','nth','numb','nut','oak','oar','oat','odd',
'ode','off','oft','oil','old','once','one','oops','opt','oral',
'orb','order','ore','otter','ouch','ounce','our','out','ova','over',
'owe','owl','own','pack','pad','pain','pal','pan','pap','par',
'pas','pat','paw','pay','pea','peck','pee','pen','per','pet',
'pick','pie','pig','pin','pip','pis','pit','plan','ploy','plum',
'ply','poi','pol','pool','pop','port','pose','post','pot','pound',
'press','print','pro','pun','pus','put','qua','quest','queue','quit',
'rack','rag','rain','raise','ram','ran','rap','rat','rave','raw',
'ray','raze','read','real','ream','red','reed','ref','rely','rent',
'rep','rest','rev','rib','rich','rick','rid','rift','rig','rim',
'ring','riot','rip','rise','risk','rite','road','rob','rock','rod',
'roll','romp','roof','room','root','rope','rose','rot','round','rove',
'row','rub','rude','rue','rug','rum','run','rush','rust','rut',
'sac','sad','safe','sag','salt','sat','saw','say','sea','sect',
'see','sent','serve','set','sex','she','shin','short','shy','sic',
'side','sigh','sign','sin','sir','sis','sit','six','ski','sky',
'sly','sob','sol','some','son','sort','sound','spa','spec','spur',
'step','stud','sty','sub','sue','suit','sum','sun','sup','sure',
'tab','tack','tag','take','talk','tam','tan','tap','tar','tat',
'tax','tea','tee','temp','ten','tern','test','text','the','thin',
'tho','thy','tic','tie','tile','time','tin','tip','tit','tom',
'ton','too','top','tor','tot','tow','tress','try','tub','tun',
'type','ugh','umber','ump','under','ups','urge','urn','use','utter',
'van','vat','vent','verse','very','vest','vet','via','vie','vine',
'viol','vise','void','volt','vote','vow','wag','wait','wake','wan',
'war','was','way','wed','wee','who','wide','win','wise','wit',
'woo','word','work','writ','yea','yon','you','zed','zing');
var login_id = "";
function get_login_id () {
    if (login_id.length < 1) {
	var logincookie = ((typeof login_cookie === 'undefined') ? "ExSiteID" : login_cookie) + "=";
	var cookie = document.cookie.split(';');
	for (var i=0; i<cookie.length; i++) {
            var c = cookie[i].trim();
            if (c.indexOf(logincookie) == 0) {
		var cookieval = c.substring(logincookie.length,c.length);
		var cookiefields = cookieval.split(":");
		login_id = cookiefields[0];
	    }
	}
    }
    return login_id;
}
$(document).ready(function(){
    $("input.NewPassword").keypress(function(){
	var basestr = (typeof base_pwd_strength === 'undefined') ? 5 : base_pwd_strength;
        var pwd = $(this).val();
        var str = pwd.length - basestr;
	//alert("start:"+str);

	// count digits, upper case, and non-alphanumeric characters as double

	var pwdchar = pwd.split("");
	var len = pwdchar.length;
        for (var i = 0; i < len; i++) {
	    if (pwdchar[i].search(/\d/) == 0) { str++; }
	    else if (pwdchar[i].search(/[A-Z]/) == 0) { str++; }
	    else if (pwdchar[i].search(/[^0-9a-zA-Z]/) == 0) { str++; }
        }
	//alert("doubled chars:"+str);
	
	// discount login id
	get_login_id();
	if (login_id && pwd.indexOf(login_id) >= 0) {
	    str -= login_id.length;
	}
	//alert("discount login id:"+str);

	// discount common character sequences (only count for half character value)
	// eg. "password1234"
	var discount = 0;
	var sequence = new Array("1234567890",
				 "abcdefghijklmnopqrstuvwxyz",
				 "qwertyuiop",
				 "asdfghjkl",
				 "zxcvbnm");
        for (var iseq = 0; iseq < sequence.length; iseq++) {
	    var subseq = new Array();
	    var found = 0;
	    var multiplier = (sequence[iseq].search(/\d/)>=0 ? 2 : 1);
	    var seq = sequence[iseq].split("");
            for (var i = 0; i < seq.length; i++) {
		subseq.push(seq[i]);
		if (subseq.length > 3) {
		    subseq.shift;
		}
		if (subseq.length >= 3) {
		    var subseqstr = subseq.join("");
		    if (pwd.search(subseqstr)>=0) {
			if (! found) {
			    discount += 2 * multiplier;
			    found = 1;
			}
			discount += 1 * multiplier;
		    }
		}
	    }
	}
	str -= discount / 2;
	//alert("discount sequences:"+str);

	// discount repeated characters (3+ chars)
	// eg. "password1111"
	var subseq = new Array();
	discount = 0;
	var pwdchar = pwd.split("");
	var len = pwdchar.length;
        for (var i = 0; i < len; i++) {
	    subseq.push(pwdchar[i]);
	    if (subseq.length > 3) {
		subseq.shift();
	    }
	    if (subseq[0] == subseq[1] && subseq[0] == subseq[2]) {
		discount += 1;
		if (subseq[0].search(/\d/)>=0) {
		    discount += 1;
		}
	    }
	}
	str -= discount;
	//alert("discount repetition:"+str);

	// discount commonly used words
	discount = 0;
        for (var i = 0; i < words.length; i++) {
	    var word = words[i];
	    if (pwd.search(word)>=0) {
		discount += word.length;
	    }
	}
	str -= discount / 2;
	//alert("discount common words:"+str);

	var minstr = (typeof min_pwd_strength === 'undefined') ? 1 : min_pwd_strength;
        if (str < minstr) {
	    $(this).attr("style","background-color:#ff9999");
	    //$("#NewPasswordTip").html("too weak");
	}
        else if (str < minstr + 2) {
	    $(this).attr("style","background-color:#ffff99");
	    //$("#NewPasswordTip").html("okay");
	}
        else {
	    $(this).attr("style","background-color:#99ff99");
	    //$("#NewPasswordTip").html("good password!");
	}
    });
});


