#!/usr/bin/perl -d

# INSTRUCTIONS:
# You must define a database (db3) in your configuration that points
# to the original V3 system. The regular database (db) should point
# to your v4 system.

### TODO:
# convert sections first, retaining original section IDs
# - this will simplify other data conversions
# existing path-based content needs to be copied
# jgallery conversions - should these be converted to albums??
# ISO8859 -> utf8

use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Util;
use ExSite::ML;
use ExSite::Form;
use Modules::Forms::Question;
use ExSite::Product;
use Modules::ID::Contact;
use MIME::Base64;

#--------------------------------------------------------------------------
# conversion options

# username to login as for conversion
my $username = "exware";

# convert to utf8
my $latin1_to_utf8 = 0;

# contact types that should be attached to profile rather than account
my $profile_contact_type = "practice";

# profile title template
# allowed fields include name, first_name, last_name, organization, honorific,
# and META_var where var is any member attribute, eg. title, credentials, etc.
my $profile_title_template = "[[name]]";

# copy invalid financial data (incomplete invoices, cancelled payments, etc)
my $copy_invalid_finances = 0;

# copy invalid users (access level 0, no login/password)
my $copy_invalid_users = 0;

#--------------------------------------------------------------------------

my %access = ( public=>0, members=>1, 'members only'=>1, administrators=>5 );
my @iaccess = (0,2,7,8);
my %memberstatus = ( active=>0, pending=>4, incomplete=>5, expired=>6, archived=>7 );
my %ticketstatus = ( active=>"confirmed", unconfirmed=>"reserved", waitlist=>"waitlist", canceled=>"canceled" );
&exsite_init;
my $ml = new ExSite::ML;
my $db3 = new ExSite::Form(%{$config{server}{db3}});  # old v3 db
$db3->{map}->load_submaps();
my $db = new ExSite::Form();
$db->{map}->load_submaps();
$db->do_login_temp($username);  # change to user with high access level
my %content;
# old id to new content id
my %old2new;
# old page id -> old parent, template, master id
my (%parent,%template,%master);
# track url changes old->new, old->newid
my (%url,%urlid);
# track form usage
my %form;
# track accounting codes
my %acctcode;
# track event relationships
my %evtparent;
# track account->content relationships
my (%uid2acct,%acct2contact);

my %ctype = &keywise("name",scalar $db->fetch_all("content_type"));

my $arg = shift @ARGV;
my ($goto,$section_id);
if ($arg =~ /^-goto$/) {
    $goto = shift @ARGV;
    $section_id = shift @ARGV;
}
else {
    $section_id = $arg;
}

die "no section id provided" if (! $section_id);
my $section = $db3->fetch("section",$section_id);
goto uc($goto) if $goto;

my $new_section_id = &section_to_cnode($section);
print "section $section->{title}\n";

#-- port standard content
my %pagestatus = (active=>0, disabled=>7,archived=>1);
my @page = $db3->fetch_child("page","section",$section_id);
foreach my $p (@page) {
    if ($p->{type} eq "page") {
	next if ($p->{filename} eq "index.html");
	&page_to_cnode($p,$new_section_id);
    }
    elsif ($p->{type} eq "template") {
	&template_to_cnode($p,$new_section_id);
    }
    elsif ($p->{type} eq "library") {
	&library_to_cnode($p,$new_section_id);
    }
    elsif ($p->{type} eq "alternate") {
	&alternate_to_cnode($p,$new_section_id);
    }
    elsif ($p->{type} eq "alias") {
	&alias_to_cnode($p,$new_section_id);
    }
    print "$p->{type} $p->{filename}\n";
}

#-- port e-zines
# get service page
ZINES:
my @serv = $db3->fetch_match("service",{section_id=>$section_id,name=>"Zine"});
my ($oldzinepage,$template);
if (@serv > 0 && $serv[0]{page_id}) {
    $oldzinepage = $db3->fetch("page",$serv[0]{page_id});
}
if ($oldzinepage) {
    $template = $old2new{"page ".$oldzinepage->{template_id}};
}
else {
    print "WARNING: no Zine service page, Zines need to be manually configured\n";
}
my @zine = $db3->fetch_match("article",{parent_id=>0,section_id=>$section_id});
my %articlestatus = (inactive=>5,active=>0,pending=>4,rejected=>8,archived=>1);
&article_to_cnode($new_section_id,$template,@zine);

# account codes
ACCOUNTS:
if ($db3->{map}->is_mapped("acctcode")) {
    my @acctcode = $db3->fetch_all("acctcode");
    if ($db->count("acctcode") < 1) { # only do this once
	foreach my $ac (@acctcode) { $db->insert("acctcode",$ac); }
    }
    %acctcode = &keywise("code",\@acctcode);
    &convert_accounts();
}

# forms
### TODO: convert libs as well
FORMS:
if ($db3->{map}->is_mapped("qa_form")) {
    my @form = $db3->fetch_match("qa_form",{section_id=>$section_id});
    if (@form > 0) {
	&make_forms(@form);
    }
}

#-- port calendars
CALENDARS:
if ($db3->{map}->is_mapped("evt")) {
    my @evt = $db3->fetch_match("evt",{section_id=>$section_id},"evt_id");
    if (@evt > 0) {
	# get service page
	my @serv = $db3->fetch_match("service",{section_id=>$section_id,name=>"EvtCal"});
	my ($oldcalpage,$template);
	if (@serv > 0 && $serv[0]{page_id}) {
	    $oldcalpage = $db3->fetch("page",$serv[0]{page_id});
	}
	if ($oldcalpage) {
	    $template = $old2new{"page ".$oldcalpage->{template_id}};
	}
	else {
	    print "WARNING: no EvtCal service page, Calendar needs to be manually configured\n";
	}
	# make a calendar
	my %cnode = (
	    type=>$ctype{calendar}{content_type_id},
	    title=>"Calendar of Events",
	    label=>"Calendar",
	    name=>"Calendar",
	    template=>$template,
	    parent=>$new_section_id,
	    access=>0,
	    content_role=>"editorial",
	    publish=>"static",
	    status=>0,
	    );
	my $calendar_id = &make_cnode(\%cnode);
	# pass1: main events
	foreach my $evt (@evt) {
	    if (! $evt->{parent}) {
		&evt_to_cnode($calendar_id,$template,$evt);
	    }
	}
	# pass2: activities
	foreach my $evt (@evt) {
	    if ($evt->{parent}) {
		$evtparent{$evt->{evt_id}} = $evt->{parent};
		&evt_to_cnode($calendar_id,$template,$evt);
	    }
	}
    }
}

#-- product catalogs
CATALOGS:
my %product_done;
if ($db3->{map}->is_mapped("catalog_category")) {
    my @cat = $db3->fetch_match("catalog_category",{section_id=>$section_id});
    if (@cat > 0) {
	&make_catalog(@cat);
    }
}

# jgalleries
JGALLERIES:
if ($db3->{map}->is_mapped("jgallery")) {
    if ($db->{map}->is_mapped("jgallery")) {
	my @jgal = $db3->fetch_match("jgallery",{section_id=>$section_id});
	foreach my $jg (@jgal) {
	    $jg->{section_id} = $new_section_id;
	    $jg->{library_id} = $old2new{"library ".$jg->{library_id}};
	    my $jid = $db->insert("jgallery",$jg);
	    $old2new{"jgallery ".$jg->{jgallery_id}} = $jid;
	    print "jgallery $jg->{type}\n";
	}
    }
    else {
	print "ERROR: JGallery not installed\n";
    }
}

# profiles
PROFILES:
if ($db3->{map}->is_mapped("member_attribute")) {
    my @mtype = $db3->fetch_match("member_fee",{section_id=>$section_id},"member_fee_id");
    if (@mtype > 0) {

	# get service page
	my @serv = $db3->fetch_match("service",{section_id=>$section_id,name=>"Membership"});
	my ($oldmempage,$template);
	if (@serv > 0 && $serv[0]{page_id}) {
	    $oldmempage = $db3->fetch("page",$serv[0]{page_id});
	}
	if ($oldmempage) {
	    $template = $old2new{"page ".$oldmempage->{template_id}};
	}
	else {
	    print "WARNING: no Membership service page, Memberships need to be manually configured\n";
	}

	# make a dummy page to hold memberships
	my %cnode = (
	    type=>$ctype{page}{content_type_id},
	    title=>"Membership",
	    label=>"Membership",
	    name=>"membership",
	    template=>$template,
	    parent=>$new_section_id,
	    access=>0,
	    content_role=>"editorial",
	    publish=>"daily",
	    status=>0,
	    );
	&cnode_name(\%cnode);
	my $page_id = &make_cnode(\%cnode);
	print "Memberships...\n";

	&make_membership($page_id,$template,@mtype); 
    }
}

# invoices
INVOICES:
if ($db3->{map}->is_mapped("acctcode")) {
    &convert_invoices();
}

# update parent, template, master relationships
# old2new{type oldid} = new content ID
foreach my $oldid (keys %old2new) {
    if ($oldid =~ /page (\d+)/) {
	my $pid = $1;
	my %data;
	if ($parent{$pid} && $old2new{"page $parent{$pid}"}) {
	    if (! $content{$old2new{$oldid}}{parent}) {
		$data{parent} = $old2new{"page $parent{$pid}"};
	    }
	}
	if ($template{$pid} && $old2new{"page $template{$pid}"}) {
	    $data{template} = $old2new{"page $template{$pid}"};
	}
	if ($master{$pid} && $old2new{"page $master{$pid}"}) {
	    $data{master} = $old2new{"page $master{$pid}"};
	}
	if ((scalar keys %data) > 0) {
	    $data{content_id} = $old2new{"page $pid"};
	    $db->update("content",\%data);
	}
    }
    elsif ($oldid =~ /section (\d+)/) {
	my $sid = $1;
	my %data;
	if ($parent{$sid} && $old2new{"section $parent{$sid}"}) {
	    $data{parent} = $old2new{"page $parent{$sid}"};
	}
	if ($template{$sid} && $old2new{"page $template{$sid}"}) {
	    $data{template} = $old2new{"page $template{$sid}"};
	}
	if ($master{$sid} && $old2new{"page $master{$sid}"}) {
	    $data{master} = $old2new{"page $master{$sid}"};
	}
	if ((scalar keys %data) > 0) {
	    $data{content_id} = $old2new{"page $sid"};
	    $db->update("content",\%data);
	}
    }
}

# attach any remaining orphans to the section
my $stype = $ctype{section}{content_type_id};
$db->custom_query("update content set parent=$new_section_id where parent=0 and type!=$stype");

# fix {{N}} urls/links
delete $share{content}{tree}; # reload tree
foreach my $cid (keys %content) {
    if ($content{$cid}{_html}) {
	$content{$cid}{_html} =~ s/\{\{(.+?)\}\}/&fix_page_url($1)/eg;
	$content{$cid}{_html} =~ s/\[\[(.+?)\]\]/&fix_content_url($1)/eg;
	$content{$cid}{_html} =~ s/<!--&QA\(form=(\d+)\)-->/&fix_form_tag($cid,$1)/eg;
	$content{$cid}{_html} =~ s/<!--&VMenu\(page_id=(\d+)\)-->/&fix_vmenu_tag($1)/eg;
	$content{$cid}{_html} =~ s/<!--&ImageRotate\((.+?)\)-->/&fix_imagerotate_tag($1)/eg;
	$content{$cid}{_html} =~ s/<!--&(Zine|Blog)\((.+?)\)-->/&fix_zine_tag($cid,$2)/eg;
	$content{$cid}{_html} =~ s/<!--&Document\((.+?)\)-->/&fix_document_tag($1)/eg;
	$content{$cid}{_html} =~ s/<!--&(SlideShow|Gallery)\((.+?)\)-->/&fix_album_tag($1,$2)/eg;
	$content{$cid}{_html} =~ s/<!--&JGallery\((.+?)\)-->/&fix_jgallery_tag($1)/eg;
	# unescape things
	$content{$cid}{_html} =~ s/\{\|\{(.*?)\}\|\}/{{$1}}/g;
	$content{$cid}{_html} =~ s/\[\|\[(.*?)\]\|\]/[[$1]]/g;
	$content{$cid}{_html} =~ s/< !--&/<!--&/g;
	# update the HTML
	my $view = $content{$cid}->revision()->view();
	if ($view) {
	    $view->setdata("data", $content{$cid}{_html});
	    $view->force_save();
	}
    }
}
# fix form templates
foreach my $fid (keys %{$form{template}}) {
    my $f = new Modules::Forms::Form(id=>$fid);
    my $template = $form{template}{$fid};
    my $t = $f->find($template);
    if ($t && $t->ok) {
	my $rev = $t->revision();
	if ($rev->ok) {
	    # move revision to form
	    $rev->setdata("content_id",$f->id);
	}
	$t->delete();
    }
}

# keywords
if ($db3->{map}->is_mapped("keyword")) {
    my @kw = $db3->fetch_all("keyword");
    if (@kw > 0) {
	my %index = (
	    type=>$ctype{index}{content_type_id},
	    title=>"Keyword Index",
	    name=>"keywords",
	    label=>"Index",
	    parent=>$new_section_id,
	    access=>0,
	    content_role=>"editorial",
	    publish=>"static",
	    status=>0,
	    );
	my $index_id = &make_cnode(\%index);
	
	foreach my $kw (@kw) {
	    my %keyw = (
		type=>$ctype{keyword}{content_type_id},
		title=>$kw->{keyword},
		name=>$kw->{keyword},
		label=>$kw->{keyword},
		parent=>$index_id,
		access=>0,
		content_role=>"editorial",
		publish=>"static",  # daily?
		status=>0,
		);
	    my $kw_id = &make_cnode(\%keyw);
	    foreach my $tag ($db->fetch_child("keyword_tag","keyword",$kw->{keyword_id})) {
		my ($title,$name,$label,$master);
		if ($tag->{section_id}) {
		    my $s = $db3->fetch("section",$tag->{section_id});
		    $title = $s->{title};
		    $label = $s->{title};
		    $name = $s->{publish_to};
		    $master = $old2new{"section $tag->{section_id}"};
		}
		elsif ($tag->{page_id}) {
		    my $p = $db3->fetch("page",$tag->{page_id});
		    $title = $p->{title};
		    $label = $p->{label};
		    $name = $p->{filename};
		    $name =~ s/\.\w+$//;
		    $master = $old2new{"page $tag->{page_id}"};
		}
		elsif ($tag->{content_id}) {
		    my $p = $db3->fetch("content",$tag->{content_id});
		    $title = $p->{name};
		    $label = $p->{name};
		    $name = $p->{name};
		    $master = $old2new{"content $tag->{content_id}"};
		}
		elsif ($tag->{article_id}) {
		    my $p = $db3->fetch("article",$tag->{article_id});
		    $title = $p->{title};
		    $label = $p->{title};
		    $name = $p->{name};
		    $master = $old2new{"article $tag->{article_id}"};
		}
		my %tag = (
		    type=>$ctype{alias}{content_type_id},
		    title=>$title,
		    name=>$name,
		    label=>$label,
		    parent=>$kw_id,
		    master=>$master,
		    access=>0,
		    content_role=>"editorial",
		    publish=>"static",
		    status=>0,
		    );
		my $tag_id = &make_cnode(\%tag);
	    }
	}
    }
}

# security/access
# for this admin
$db->insert("content_key",{content_id=>$new_section_id,
			   type=>"grant",
			   uid=>$db->my_uid,
			   role=>"editor; designer; administrator; reviewer"});
# add any additional users
foreach my $member ($db3->fetch_match("member",{section_id=>$section_id})) {
    next if (! $copy_invalid_users &&
	     (! $member->{access} || ! $member->{login} || ! $member->{password}));
    next if ($member->{login} eq $db->my_login);
    my $name = exists $member->{name} ? $member->{name} : $member->{first_name}." ".$member->{last_name};
    my $uid = $db->insert("user",{uid=>$member->{member_id},login=>$member->{login},password=>$member->{password},access=>$iaccess[$member->{access}],name=>$name,email=>$member->{email},section_id=>$new_section_id});
    print "added user $member->{login}\n";
    foreach my $key ($db3->fetch_match("member_site_link",{member_id=>$member->{member_id},section_id=>$member->{section_id}})) {
	$db->insert("content_key",{content_id=>$new_section_id,uid=>$uid,type=>"grant",role=>$key->{priveleges}});
    }
}

open F, ">convert.log";
foreach my $old (sort keys %old2new) {
    print F "$old => $old2new{$old}\n";
}
close F;
print "ERRORS:\n";
print &ExSite::Config::show_diagnostics("text");

sub fix_page_url {
    my $arg = shift;
    if ($arg =~ /^\d+$/) {
	return "{|{". $old2new{"page $arg"}. "}|}";
    }
    else {
	my ($name,$suffix) = split /\./,$arg;
	return "{|{$name}|}";
    }
}

sub fix_content_url {
    my $arg = shift;
    if ($arg =~ /^\d+$/) {
	return "[|[". $old2new{"content $arg"}. "]|]";
    }
    else {
	return "[|[$arg]|]";
    }
}

sub fix_form_tag {
    my ($content_id,$formid) = @_;
    # move form to the current page
    my $p = $content{$content_id}->my_page();
    my $f = $content{$old2new{"qa_form $formid"}};
    if ($f) {
	if ($p) {
	    $f->setdata("parent",$p->id);
	    $f->save();
	    $form{count}{$f->id}++; # count # of times form has been used
	}
    }
    else {
	return undef; 
    }
    return ($form{count}{$f->id} > 1) ?
	"<!--&Content(id=".$f->id().")-->" :  # form is being reused
	"<!--content(".$f->name().")-->";     # form is local to this page
}

sub fix_zine_tag {
    my ($pid,$args) = @_;
    my %arg = &DecodeString($args);
    # move zine to the current page
    if ($arg{aid}) {
	my $p = $content{$pid}->my_page();
	my $b = $content{$old2new{"article ".$arg{aid}}};
	if ($b && $p) {
	    $b->setdata("parent",$p->id);
	    $b->save();
	    return "<!--content(".$b->name().")-->";
	}
    }
    return "<!-- unknown zine: $args -->";
}

sub fix_document_tag {
    my ($pid,$args) = @_;
    my %arg = &DecodeString($args);
    if ($arg{lib}) {
	my $p = $content{$pid}->my_page();
	my $lib = $content{$old2new{"library ".$arg{lib}}};
	return "<!--&Document(lib=".$lib->id().")-->";
    }
    return "<!-- no document library specified: $args -->";
}

sub fix_vmenu_tag {
    my $arg = shift;
    if ($arg =~ /^\d+$/) {
	return "< !--&VMenu(page_id=".$old2new{"page $arg"}.")-->";
    }
    return "< !--&VMenu()-->";
}

sub fix_imagerotate_tag {
    my %opt = &DecodeString(shift);
    if ($opt{id}) {
	$opt{id} = $old2new{"library ".$opt{id}};
	return "< !--&ImageRotate(".&EncodeHash(%opt).")-->";
    }
    return "< !--&ImageRotate()-->";
}

sub fix_album_tag {
    my $mod = shift;
    my %opt = &DecodeString(shift);
    if ($opt{id}) {
	$opt{id} = $old2new{"library ".$opt{id}};
	return "< !--&${mod}(".&EncodeHash(%opt).")-->";
    }
    elsif ($opt{name}) {
	$opt{name} = "lib_".$opt{name};
	return "< !--&${mod}(".&EncodeHash(%opt).")-->";
    }
    return "< !--&${mod}()-->";
}

sub fix_jgallery_tag {
    my %opt = &DecodeString(shift);
    if ($opt{jgallery_id}) {
	$opt{jgallery_id} = $old2new{"jgallery ".$opt{jgallery_id}};
	return "< !--&JGallery(".&EncodeHash(%opt).")-->";
    }
    return "<!-- invalid JGallery tag -->";
}

sub make_cnode {
    my ($cnode,%opt) = @_;  # %opt is for &revise();
    if (exists $cnode->{template} && ! $cnode->{template}) {
	$cnode->{template} = 0;
    }
    if (exists $cnode->{parent} && ! $cnode->{parent}) {
	$cnode->{parent} = 0;
    }
    elsif (! exists $cnode->{parent}) {
	$cnode->{parent} = 0;
    }
    if (exists $cnode->{master} && ! $cnode->{master}) {
	$cnode->{master} = 0;
    }
    if (length $cnode->{name} > 80) {
	$cnode->{name} = substr($cnode->{name},0,80);
    }
    if (length $cnode->{label} > 80) {
	$cnode->{label} = substr($cnode->{label},0,80);
    }
    if ($cnode->{sortkey} =~ /^\d+$/) {
	# numeric sortkeys can break down when sorted 
	# alphabetically (eg. 10 comes before 2)
	# pad with "0" characters (so 2 becomes 0002, and 10 becomes 0010)
	my $len = length "$cnode->{sortkey}";
	$cnode->{sortkey} = ("0"x(4-$len)).$cnode->{sortkey};
    }
    if (! exists $cnode->{ctime}) {
	$cnode->{ctime} = undef;
    }
    defined $cnode->{status} or $cnode->{status} = 0;
    $cnode->{title} = &utf8encode($cnode->{title});
    $cnode->{label} = &utf8encode($cnode->{label});
    $cnode->{name} = &utf8encode($cnode->{name});

    my $content = new ExSite::Content(data=>$cnode,dirty=>1);
    my $error = join "; ",$content->validate();
    if ($error =~ /already in use/) {
	# name collision
	my $name = $cnode->{name} . "_" . &randname(5);
	$content->setdata("name",$name);
    }
    if ($error =~ /URL-friendly/) {
	# bad name
	$content->setdata("name",&safetext($cnode->{name}));
    }
    if ($error =~ /maximum length/ || length $content->getdata("name") > 80) {
	# name? too long
	my $name = &make_name($cnode->{name},1);
	$content->setdata("name",substr($name,0,70)."_".&randname(5));
    }
    $content->save();
    my $cid = $content->id;
    if ($cid) {
	my $newobj = $content->get_content_obj();
	my $newurl = $newobj->get_url_canonical();
	$content{$cid} = $content;
	if ($opt{data}) {
	    if ($opt{mime_type} =~ /text/) {
		$opt{data} = &utf8encode($opt{data});
	    }
	    $content->revise(%opt);
	    if ($opt{mime_type} eq "text/html") {
		# remember HTML so we can fix CMS tags later 
		if ($opt{data} =~ /\{\{/ || 
		    $opt{data} =~ /\[\[/ || 
		    $opt{data} =~ /<!--&/) {
		    $content{$cid}{_html} = $opt{data};
		}
	    }
	}
    }
    else {
	print $content->show_diagnostics("error");
	die "failed to make content $cnode->{name}";
    }
    return $cid;
}

sub cnode_name {
    my ($cnode,$name) = @_;
    if (! $cnode->{name}) {
	if ($name) {
	    $cnode->{name} = &make_name($name,1),
	}
	elsif ($cnode->{label}) {
	    $cnode->{name} = &make_name($cnode->{label},1),
	}
	elsif ($cnode->{title}) {
	    $cnode->{name} = &make_name($cnode->{title},1),
	}
	if (! $cnode->{name}) {
	    $cnode->{name} = &randtext(5,"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz01234567890");
	}
	my @exists = $db->fetch_match("content",{name=>$cnode->{name},parent=>$cnode->{parent}});
	if (@exists > 0) {
	    # name already exists here
	    $cnode->{name} .= "_" . &randtext(3,"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz01234567890");
	}
    }
}

sub section_to_cnode {
    my $section = shift;
    # find the index page
    my @page = $db3->fetch_match("page",{section_id=>$section->{section_id},type=>"page",filename=>"index.html"});
    my $index = $page[0];
    my %cnode = (
	type=>$ctype{section}{content_type_id},
	title=>$index->{title},
	label=>$section->{title},
	name=>&clean_filename($section->{title}),
#	template=>,  ####### FIXME
#	master=>, ####### FIXME
	url=>$section->{url},
	access=>$access{public},
	content_role=>"editorial",
	publish=>"static",
	status=>0,
	);
    my ($page,$content,$homecontent);
    if ($index) {
	($page,$content) = &get_page_and_content($index);
	if ($page->{visibility} eq "hidden") {
	    $cnode{hide} = "menu; sitemap";
	}
	elsif ($page->{visibility} eq "menu-only") {
	    $cnode{hide} = "sitemap";
	}
	elsif ($page->{visibility} eq "sitemap-only") {
	    $cnode{hide} = "menu";
	}
	if ($page->{version}) {
	    $cnode{language} = $page->{version};
	}
    }
    if ($content->{page}) {
	$homecontent = $content->{page}{content_data}{data};
	delete $content->{page};
    }
    my $content_id = $homecontent ? 
	&make_cnode(\%cnode,data=>$homecontent,format=>"text",mime_type=>"text/html",note=>"import") :
	&make_cnode(\%cnode);
    $old2new{"section $section->{section_id}"} = $content_id;
    $old2new{"page $index->{page_id}"} = $content_id;
    if ($index->{keywords}) {
	&add_metadata("keywords",$index->{keywords},$content_id);
    }
    if ($index->{description}) {
	&add_metadata("description",$index->{description},$content_id);
    }
    $template{$index->{page_id}} = $index->{template_id};
    &install_page_content($page->{page_id}, $content_id, $content);
    return $content_id;
}

sub page_to_cnode {
    my ($oldpage,$section_id) = @_;
    # find the page
    my ($page,$content) = &get_page_and_content($oldpage);
    my $name = $page->{filename};
    $name =~ s/\.\w+//;
    my $hide;
    if ($page->{visibility} eq "hidden") {
	$hide = "menu; sitemap";
    }
    elsif ($page->{visibility} eq "menu-only") {
	$hide = "sitemap";
    }
    elsif ($page->{visibility} eq "sitemap-only") {
	$hide = "menu";
    }
    my %cnode = (
	type=>$ctype{page}{content_type_id},
	title=>$page->{title},
	label=>$page->{label},
#	template=>,  ####### FIXME
#	master=>, ####### FIXME
	parent=>$page->{parent_id} ? undef : $section_id,
	access=>$access{$page->{access}},
	content_role=>"editorial",
#	publish=>$page->{publish_method},
	status=>$pagestatus{$page->{status}},
	hide=>$hide,
	sortkey=>$page->{rank} ? $page->{rank} : undef,
	ctime=>$page->{ctime},
	);
    &cnode_name(\%cnode,$name);
    my $alttemplate;
    if ($content->{page}) {
	$alttemplate = $content->{page}{content_data}{data};
	delete $content->{page};
    }
    my $content_id = &make_cnode(\%cnode,data=>$alttemplate,format=>"text",mime_type=>"text/html",note=>"import");
    $old2new{"page $page->{page_id}"} = $content_id;
    $parent{$page->{page_id}} = $page->{parent_id};
    $template{$page->{page_id}} = $page->{template_id};
    &install_page_content($page->{page_id},$content_id,$content);
    # metadata
    if ($page->{keywords}) {
	&add_metadata("keywords",$page->{keywords},$content_id);
    }
    if ($page->{description}) {
	&add_metadata("description",$page->{description},$content_id);
    }
}

### this is the same as page_to_cnode above
sub alternate_to_cnode {
    my ($oldpage,$section_id) = @_;
    # find the page
    my ($page,$content) = &get_page_and_content($oldpage);
    # for alternates, parent is the master, master's parent is the parent
    my $master = $db3->fetch("page",$page->{parent_id});
    my %cnode = (
	type=>$ctype{page}{content_type_id},
	title=>$page->{title},
	label=>$page->{label},
#	template=>,  ####### FIXME
#	master=>$page->{parent_id},
#	parent=>$master->{parent_id},
	access=>$access{$page->{access}},
	content_role=>"editorial",
#	publish=>$page->{publish_method},
	status=>$pagestatus{$page->{status}},
	language=>$page->{version},
	sortkey=>$page->{rank} ? $page->{rank} : undef,
	ctime=>$page->{ctime},
	);
    &cnode_name(\%cnode,$page->{filename});
    my $body;
    if ($content->{body}) {
	$body = $content->{body}{content_data}{data};
	delete $content->{body};
    }
    my $content_id = &make_cnode(\%cnode,data=>$body,format=>"text",mime_type=>"text/html",note=>"import");
    $old2new{"page $page->{page_id}"} = $content_id;
    $parent{$page->{page_id}} = $master->{parent_id};
    $template{$page->{page_id}} = $page->{template_id};
    $master{$page->{page_id}} = $page->{parent_id};
    &install_page_content($page->{page_id},$content_id,$content);
    # metadata
    if ($page->{keywords}) {
	&add_metadata("keywords",$page->{keywords},$content_id);
    }
    if ($page->{description}) {
	&add_metadata("description",$page->{description},$content_id);
    }
}

sub template_to_cnode {
    my ($oldtemplate,$section_id) = @_;
    # find the page
    my ($page,$content) = &get_page_and_content($oldtemplate);
    my %cnode = (
	type=>$ctype{template}{content_type_id},
	title=>$page->{title},
	label=>$page->{label} || $page->{title},
#	template=>,  ####### FIXME
#	master=>, ####### FIXME
	parent=>$section_id,
	access=>0, #$access{$page->{access}},
	content_role=>"design",
	publish=>"static",#$page->{publish_method},
	sortkey=>899,
	status=>$pagestatus{$page->{status}},
	ctime=>$page->{ctime},
	);
    &cnode_name(\%cnode,"template_".$page->{filename});
    my $pagecontent;
    if ($content->{page}) {
	$pagecontent = $content->{page}{content_data}{data};
	delete $content->{page};
    }
    my $content_id = &make_cnode(\%cnode,data=>$pagecontent,format=>"text",mime_type=>"text/html",note=>"import");
    $old2new{"page $page->{page_id}"} = $content_id;
    $parent{$page->{page_id}} = $page->{parent_id};
    $template{$page->{page_id}} = $page->{template_id};
    &install_page_content($page->{page_id},$content_id,$content);
}

sub library_to_cnode {
    my ($oldlib,$section_id) = @_;
    # find the library
    my ($page,$content) = &get_page_and_content($oldlib);
    my %cnode = (
	type=>$ctype{library}{content_type_id},
	title=>$page->{title},
	label=>$page->{label} || $page->{title},
	parent=>$section_id,
	access=>$access{$page->{access}},
	content_role=>"editorial",
	publish=>$access{$page->{access}} ? "dynamic" : $page->{publish_method},
	status=>$pagestatus{$page->{status}},
	sortkey=>999,
	ctime=>$page->{ctime},
	);
    &cnode_name(\%cnode,"lib_".$page->{filename});
    my $content_id = $db->insert("content",\%cnode);
    $old2new{"library $page->{page_id}"} = $content_id;
    &install_page_content($page->{page_id},$content_id,$content);
}

sub alias_to_cnode {
    my ($oldpage,$section_id) = @_;
    # find the page
    my ($page,$content) = &get_page_and_content($oldpage);
    my %cnode = (
	type=>$ctype{alias}{content_type_id},
	title=>$page->{title},
	label=>$page->{label},
	parent=>$page->{parent_id} ? 0 : $section_id,
	master=>$page->{template_id},
	access=>$access{$page->{access}},
	content_role=>"editorial",
#	publish=>$page->{publish_method},
	status=>$pagestatus{$page->{status}},
	ctime=>$page->{ctime},
	);
    my $name = $page->{filename};
    $name =~ s/\.html//;
    &cnode_name(\%cnode,$name);
    my $content_id = $db->insert("content",\%cnode);
    $parent{$page->{page_id}} = $page->{parent_id};
    $master{$page->{page_id}} = $page->{template_id};
    $old2new{"page $page->{page_id}"} = $content_id;
#    $old2new{"alias $page->{page_id}"} = $content_id;
}

sub article_to_cnode {
    my ($parent,$template,@article) = @_;
    foreach my $article (@article) {
	# get the article
	my $type = $article->{type};
	print "$type $article->{title}\n";
	#next if ($type eq "attachment");
	my ($atype,$name,%hide);
	if ($article->{type} eq "article") {
	    $atype = "article";
	    $name = $article->{name};
	}
	elsif ($article->{type} eq "forum") {
	    $atype = "forum";
	    $name = $article->{name};
	}
	elsif ($article->{type} eq "attachment") {
	    $atype = "content";
	    $name = $article->{name};
	}
	elsif ($article->{type} eq "comment") {
	    $atype = "comment";
	    $name = "comment_".&randtext(5,"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz01234567890");
	}
	else {
	    $atype = "blog"; #############
	    $name = $article->{name};
	    $hide{menu} = 1;
	}
	if ($article->{status} eq "archived") {
	    $hide{menu} = 1;
	}
	my %cnode = (
	    type=>$ctype{$atype}{content_type_id},
	    title=>$article->{title},
	    label=>$article->{title},
#	    name=>&clean_filename($article->{name}),
	    template=>$template,
#	master=>, ####### FIXME
	    parent=>$parent,
	    access=>$access{$article->{privacy}},
	    content_role=>"editorial",
	    #publish=>$access{$article->{privacy}} > 0 ? "dynamic" : "static",
	    status=>$articlestatus{$article->{status}},
	    hide=>join("; ",keys %hide),
	    sortkey=>$article->{sortkey},
	    ctime=>$article->{ctime},
	    ptime=>$article->{mtime},
	);
	&cnode_name(\%cnode);
	if (! $cnode{type}) {
	    # unsupported zine type
	    print "Unsupported zine type: $article->{type}\n";
	    $cnode{type} = $ctype{article}{content_type_id};
	}
	my %rev;
	my $caption;
	if ($article->{body}) {
	    %rev = (
		data=>$article->{body},
		'format'=>"text",
		mime_type => "text/html",
		note=>"import"
		);
	    if ($article->{content_type} !~ /html/i) {
		# convert plaintext data to HTML
		my $br = $ml->br();
		$rev{data} =~ s/\&/\&amp;/g;      # escape &
		$rev{data} =~ s/(\r?\n\s*){2,}/<\/p>\n<p>/g;
		$rev{data} = $ml->p($rev{data});
	    }
	}
	elsif ($article->{picture}) {
	    %rev = (
		data=>$article->{picture},
		'format'=>"file",
		note=>"import",
		);
	    $rev{view}{thumb} = $article->{thumb} ? {data=>$article->{thumb},'format'=>"file"} : 1;
	    $caption = $article->{caption};
	    delete $article->{picture}; # don't install as secondary content
	}
	my $content_id = &make_cnode(\%cnode,%rev);
	$old2new{"article $article->{article_id}"} = $content_id;

	# metadata
	if ($article->{author}) {
	    &add_metadata("author",$article->{author},$content_id);
	}
	if ($article->{summary}) {
	    &add_metadata("abstract",$article->{summary},$content_id);
	}
	if ($article->{about}) {
	    &add_metadata("footnote",$article->{about},$content_id);
	}
	### subtitle?
	### owner - key??

	# photo
	if ($article->{picture}) {
	    my $caption = $article->{caption};
	    my ($filename, undef) = split /\#/, $article->{picture};
	    my $mime = &MimeType($filename);
	    $filename =~ s/\.\w{3,4}$//;
	    my $name = $caption && length $caption < 40 ? $caption : $filename;
	    my %cnode2 = (
		type=>$ctype{content}{content_type_id},
		title=>$name,
		label=>$name,
		name=>&clean_filename($name),
		parent=>$content_id,
		access=>$cnode{access},
		content_role=>"editorial",
		publish=>"static",#$cnode{publish},
		status=>$cnode{status},
		hide=>$cnode{hide},
		sortkey=>0,
		ctime=>$article->{ctime},
		ptime=>$article->{mtime},
		);
	    my %rev = (
		data=>$article->{picture},
		'format'=>"file",
		mime_type=>$mime,
		note=>"import"
		);

	    ### FIXME: thumb filename is wrong

	    if ($article->{thumb}) {
		my $file = $article->{thumb};
		if ($file !~ /^th_/) {
		    $file = "th_" . $file;
		}
		$rev{view}{thumbnail} = {
		    data=>$file,
		    'format'=>"file",
		    mime_type=>$mime,
		};
		$rev{view}{small} = 1; # useful for floating right
	    }
	    my $attach_id = &make_cnode(\%cnode2,%rev);
	    if ($article->{caption}) {
		&add_metadata("caption",$article->{caption},$attach_id);
	    }
	}
	
	# child articles
	my @art = $db3->fetch_match("article",{parent_id=>$article->{article_id}},"article_id");
	&article_to_cnode($content_id,$template,@art);
    }
}

sub evt_to_cnode {
    my ($calid,$template,$evt) = @_;

    my %cnode = (
	type=>$ctype{event}{content_type_id},
	title=>$evt->{name},
	label=>$evt->{name},
	template=>$template,
	parent=>$evt->{parent} ? $old2new{"evt $evt->{parent}"} : $calid,
	access=>($evt->{privacy} eq "public" ? 0 : 1),
	content_role=>"editorial",
#	publish=>"static", ## if registration should be dynamic
	status=>($evt->{status} =~ /cancel/ ? 7 : 0), ## archived?
	hide=>($evt->{visibility} =~ /hidden/ ? "indexes" : undef),
	ctime=>$evt->{ctime},
	ptime=>$evt->{ctime},
	);
    &cnode_name(\%cnode);
    my %rev;
    my $caption;
    if ($evt->{description} && 
	length($evt->{description} > 12)) {  # skip <div></div>
	%rev = (
	    data=>$evt->{description},
	    'format'=>"text",
	    mime_type => "text/html",
	    note=>"import"
	    );
    }
    my $evt_id = &make_cnode(\%cnode,%rev);
    $old2new{"evt $evt->{evt_id}"} = $evt_id;
    print "event $evt->{name}\n";

    # add dates
    foreach my $date ($db3->fetch_child("evt_date","evt",$evt->{evt_id})) {
	my $start = $date->{date};
	if ($date->{time} && $date->{time} !~ /^00:00/) {
	    $start .= " ".$date->{time};
	}
	my $end = $date->{enddate};
	if ($date->{endtime} && $date->{endtime} !~ /^00:00/) {
	    $end .= " ".$date->{endtime};
	}
	$db->insert("content_date",
		    {content_id=>$evt_id,
		     type=>"calendar",
		     start=>$start,
		     end=>$end,
		     status=>"active"});
    }

    # locations
    my %contact_privacy = (public=>0,members=>2,administrators=>5);
    foreach my $evtloc ($db3->fetch_child("evt_location","evt",$evt->{evt_id})) {
	my $loc = $db3->fetch("location",$evtloc->{location_id});
	my %cnode2 = (
	    type=>$ctype{location}{content_type_id},
	    title=>$loc->{name},
	    label=>$loc->{name},
	    template=>$template,
	    parent=>$evt_id,
	    access=>$cnode{access},
	    content_role=>"editorial",
#	    publish=>$cnode{publish},
	    status=>$cnode{status},
	    ctime=>$cnode{ctime},
	    ptime=>$cnode{ctime},
	    );
	&cnode_name(\%cnode2);
	print "location $loc->{name}\n";
	my %rev;
	if ($loc->{description} && 
	    length($loc->{description} > 12)) {  # skip <div></div>
	    %rev = (
		data=>$loc->{description},
		'format'=>"text",
		mime_type => "text/html",
		note=>"import"
		);
	}
	my $loc_id = &make_cnode(\%cnode2,%rev);
	# location contacts
	foreach my $contact ($db3->fetch_child("contact","location",$loc->{location_id})) {
	    $contact->{content_id} = $loc_id;
	    #### should privacy be renamed access?
	    $contact->{privacy} = $contact_privacy{$contact->{privacy}};
	    delete $contact->{section_id};
	    delete $contact->{account_id};
	    delete $contact->{location_id};
	    $contact->{phone} = $contact->{phone1};
	    $contact->{cell} = $contact->{phone2};
	    delete $contact->{phone1};
	    delete $contact->{phone2};
	    my $c = new Modules::ID::Contact();
	    $c->save_contact_data($contact);
	}
    }
    &make_registration($evt,$evt_id);
}

sub make_registration {
    my ($old_evt,$new_evt_id) = @_;
    my @fee = $db3->fetch_match("evt_fee",{evt_id=>$old_evt->{evt_id}},"evt_fee_id");
    return if (scalar @fee ==0);
    my (%donefee,%donename,%newfee,%price,%meta,%form,%flag,%message,%allfee,%usefee);

    # 1: scan the old fees
    foreach my $fee (@fee) {
	my $access;
	if ($fee->{privacy} =~ /admin/) {
	    $access = 5;
	}
	elsif ($fee->{privacy} =~ /member/) {
	    $access = 2;
	}
	else { # public
	    $access = 0;
	}
	my $fee_id;
	if ($fee->{treat_as}) {
	    $fee_id = $fee->{treat_as};
#	    $newfee{$fee->{evt_fee_id}} = $newfee{$fee_id};
	}
	elsif ($donename{$fee->{name}} && $evtparent{$old_evt}) {
	    # probably a special case of an activity fee
	    $fee_id = $donename{$fee->{name}}{evt_fee_id};
#	    $newfee{$fee->{evt_fee_id}} = $newfee{$fee_id};
	}
	else {
	    $fee_id = $fee->{evt_fee_id};
	    $newfee{$fee_id} = {
		type=>$ctype{fee}{content_type_id},
		title=>$fee->{name},
		label=>$fee->{name},
		parent=>$new_evt_id,
		access=>$access,
		sortkey=>sprintf("%03d",$fee->{sortkey}),
		status=>$fee->{status} eq "active" ? 0 : 7,
		hide=>($fee->{visibility} =~ /hidden/ ? "indexes" : undef),
		ctime=>$fee->{ctime},
	    };
	    if ($fee->{reglimit}) {
		$meta{$fee_id}{maximum_registrations} = $fee->{reglimit};
	    }
	    if ($fee->{form}) {
		$form{$fee_id} = $fee->{form};
	    }
	    if ($fee->{message}) {
		$message{$fee_id} = $fee->{message};
	    }
	    $donename{$fee->{name}} = $fee;
	}
	$usefee{$fee->{evt_fee_id}} = $fee_id;
	if (! exists $price{$fee_id}) {
	    $price{$fee_id} = [];
	}
	push @{$price{$fee_id}}, {
	    status=>"active",
	    description=>$fee->{description},
	    cost=>$fee->{cost},
	    acctcode_id=>$acctcode{EVENT}{acctcode_id},
	    access=>$access,
	};
	if ($fee->{open} && $fee->{open} !~ /^0/) {
	    $price{$fee_id}[-1]{start} = $fee->{open};
	}
	if ($fee->{close} && $fee->{close} !~ /^0/) {
	    $price{$fee_id}[-1]{end} = $fee->{close};
	}
	if ($access < $newfee{$fee_id}{access}) {
	    $newfee{$fee_id}{access} = $access;
	}
	if ($fee->{options}) {
	    foreach my $opt (split /; /, $fee->{options}) {
		$flag{$fee_id}{$opt} = 1;
	    }
	}

	#available to !!!
	#access code
	#group
	$allfee{$fee->{evt_fee_id}} = $fee_id;
    }

    # fix bad treat-as references
    foreach my $fee_id (keys %allfee) {
	if (exists $newfee{$usefee{$fee_id}}) {
	    if (scalar keys %{$newfee{$usefee{$fee_id}}} == 0) {
		# treat-as points to non-canonical fee
		delete $newfee{$usefee{$fee_id}};
		### anything else to fix?
	    }
	}
	else {
	    $usefee{$fee_id} = $usefee{$usefee{$fee_id}};
	}
    }

    # 2: build the new fees
    %donefee = ();
    foreach my $old_fee_id (sort keys %newfee) {
	my $cnode = $newfee{$old_fee_id};
	&cnode_name($cnode);
	my $fee_id = &make_cnode($cnode);
	$old2new{"fee $old_fee_id"} = $fee_id;
	print "- registration fee $cnode->{label}\n";

	# pricing
	my %doneprice;
	if (ref $price{$old_fee_id} eq "ARRAY") {
	    foreach my $price (@{$price{$old_fee_id}}) {
		my $key = &hash2text(%$price);
		next if ($doneprice{$key});
		$price->{content_id} = $fee_id;
		$db->insert("price",$price);
		$doneprice{$key} = 1;
	    }
	}

	# metadata
	foreach my $meta (keys %{$meta{$old_fee_id}}) {
	    &add_metadata($meta,$meta{$old_fee_id}{$meta},$fee_id);
	}
	# flags
	foreach my $flag (keys %{$flag{$old_fee_id}}) {
	    $db->insert("content_flag",{content_id=>$fee_id,flag=>$flag});
	}

	# message
	if ($message{$old_fee_id}) {
	    my $cnode = {
		type=>$ctype{content}{content_type_id},
		parent=>$fee_id,
		name=>"message",
		title=>"$cnode->{label} registration message",
		label=>"Registration message",
		status=>0,
		access=>0,
		content_role=>"editorial",
		publish=>"never",
	    };
	    my %rev = (
		data=>$message{$old_fee_id},
		'format'=>"text",
		mime_type => "text/html",
		note=>"import"
		);
	    &make_cnode($cnode,%rev);
	}

	# form
	if ($form{$old_fee_id}) {
	    my $cnode = {
		type=>$ctype{alias}{content_type_id},
		parent=>$fee_id,
		name=>"form",
		title=>"$cnode->{label} registration form",
		label=>"Registration form",
		master=>$old2new{"qa_form $form{$old_fee_id}"}||"0",
		status=>0,
	    };
	    $db->insert("content",$cnode);
	}
    }

    # 3: copy registrants
    print "- copying tickets...\n";
    foreach my $fee (@fee) {
	my $old_fee_id = $fee->{evt_fee_id};
	my $new_fee_id = $old2new{"fee $usefee{$old_fee_id}"};
	if ($new_fee_id) {
	    my %reg2tic;
	    foreach my $reg ($db3->fetch_match("evt_reg",{evt_fee_id=>$old_fee_id},"evt_reg_id")) {
		next if ($reg->{status} =~ /inactive|canceled/);
		my $ticket_id = $db->insert("ticket",{content_id=>$new_fee_id,status=>"active"});
		my $tcid = $db->insert("ticket_claim",
				       {ticket_id=>$ticket_id,
					account_id=>$reg->{account_id},
					guest_account_id=>$reg->{guest_account_id},
					status=>$ticketstatus{$reg->{status}},
					parent=>$reg2tic{$reg->{parent}} || "0",
					first_name=>&utf8encode($reg->{first_name}),
					last_name=>&utf8encode($reg->{last_name}),
					response_id=>$old2new{"qa_response $reg->{response_id}"}||"0",
					ctime=>$reg->{ctime}});
		$old2new{"evt_reg $reg->{evt_reg_id}"} = $ticket_id;
		if (! $reg->{parent}) {
		    # remember primaries
		    $reg2tic{$reg->{evt_reg_id}} = $tcid;
		}
	    }
	}
	else {
	    print "ERROR: fee $old_fee_id has no correlate\n";
	}
    }
}

### deprecated
sub copy_tickets_old {
    my ($old_fee_id,$new_fee_id) = @_;
    my %reg2tic;
    foreach my $reg ($db3->fetch_match("evt_reg",{evt_fee_id=>$old_fee_id},"evt_reg_id")) {
	next if ($reg->{status} =~ /inactive|canceled/);
	my $ticket_id = $db->insert("ticket",{content_id=>$new_fee_id,status=>"active"});
	my $tcid = $db->insert("ticket_claim",
			       {ticket_id=>$ticket_id,
				account_id=>$reg->{account_id},
				guest_account_id=>$reg->{guest_account_id},
				status=>$ticketstatus{$reg->{status}},
				parent=>$reg2tic{$reg->{parent}} || "0",
				first_name=>&utf8encode($reg->{first_name}),
				last_name=>&utf8encode($reg->{last_name}),
				response_id=>$old2new{"qa_response $reg->{response_id}"}||"0",
				ctime=>$reg->{ctime}});
	$old2new{"evt_reg $reg->{evt_reg_id}"} = $ticket_id;
	if (! $reg->{parent}) {
	    # remember primaries
	    $reg2tic{$reg->{evt_reg_id}} = $tcid;
	}
    }
}

### WARNING: we only port memberships of known types

sub make_membership {
    my ($parent_page_id,$template,@fee) = @_;

    my %donefee;
    foreach my $mfee (@fee) {
	my $mfee_id;
	my $price_descr;
	if ($donefee{$mfee->{type}}) {
	    $mfee_id = $donefee{$mfee->{type}};
	    if ($mfee->{description}) {
		$price_descr = " - ".$mfee->{description};
	    }
	}
	else {
	    my %cnode = (
		type=>$ctype{membership_type}{content_type_id},
		title=>$mfee->{type},
		label=>$mfee->{type},
		template=>$template,
		parent=>$parent_page_id,
		access=>0,
		content_role=>"editorial",
		publish=>"daily",
		sortkey=>$mfee->{sortkey},
		status=>0,
		hide=>($mfee->{visibility} =~ /hidden/ ? "indexes" : undef),
		ctime=>$mfee->{ctime},
		);
	    &cnode_name(\%cnode);
	    
	    my %rev;
	    my $caption;
	    if ($mfee->{description}) {
		%rev = (
		    data=>$mfee->{description},
		    'format'=>"text",
		    mime_type => "text/html",
		    note=>"import"
		    );
	    }
	    $mfee_id = &make_cnode(\%cnode,%rev);
	    $old2new{"membership_type $mfee->{member_fee_id}"} = $mfee_id;
	    print "member fee $mfee->{type}\n";
	}

	# new member pricing
	my $price = {content_id=>$mfee_id,
		     status=>"active",
		     description=>"Application".$price_descr,
		     cost=>$mfee->{cost},
		     acctcode_id=>$acctcode{DUES}{acctcode_id},
		     access=>0,
		     start=>$mfee->{open},
		     end=>$mfee->{close}};
	$db->insert("price",$price);
	# renewal pricing
	if ($mfee->{renew_cost} && $mfee->{renew_cost} > 0.00) {
	    $price->{description} = "Renewal".$price_descr;
	    $price->{cost} = $mfee->{renew_cost};
	    $price->{access} = 2;
	    $db->insert("price",$price);
	}
	if (! $donefee{$mfee->{type}}) {
	    foreach my $member ($db3->fetch_match("member",{section_id=>$section_id,type=>"member/".$mfee->{type}})) {
		&make_profile($mfee_id,$member);
	    }
	}
	$donefee{$mfee->{type}} = $mfee_id;
    }
}

sub make_profile {
    my ($mfee_id,$member) = @_;
    my %subhash = (
	first_name => $member->{first_name},
	middle_name => $member->{middle_name},
	last_name => $member->{last_name},
	name=>"$member->{first_name} $member->{last_name}",
	organization=>$member->{organization},
	honorific=>$member->{honorific},
	);
    my @meta = $db3->fetch_match("member_attribute",{member_id=>$member->{member_id}});
    my %meta = &keywise("name",\@meta);
    foreach my $key (keys %meta) {
	$subhash{"META_$key"} = $meta{$key};
    }
    my $name = &substitute($profile_title_template,\%subhash);

    my $access;
    if ($member->{privacy} eq "public") {
	$access = 0;
    }
    elsif ($member->{privacy} =~ /member/) {
	$access = 2;
    }
    else { # default to admin
	$access = 5;
    }

    # status
    my @status =  $db3->fetch_match("member_status",{member_id=>$member->{member_id}});
    my $final_status = (scalar @status > 0) ? $memberstatus{$status[-1]{status}} : 5;

    my %cnode = (
	type=>$ctype{profile}{content_type_id},
	title=>$name,
	label=>$name,
	parent=>$mfee_id,
	access=>$access,
	sortkey=>uc($member->{last_name})." ".uc($member->{first_name}),
	status=>$final_status,
	hide=>($member->{visibility} =~ /hidden/ ? "indexes" : undef),
	ctime=>$member->{ctime},
	);
    &cnode_name(\%cnode);
    
    my %rev;
    if ($meta{bio} || $meta{description}) {
	my $protxt = $meta{bio}{value} || $meta{description}{value};
	if ($protxt !~ /<[A-Za-z]+/) {
	    # plain text ?
	    $protxt =~ s/\n/<br>\n/g;
	}
	%rev = (
	    data=>$protxt,
	    'format'=>"text",
	    mime_type => "text/html",
	    note=>"import"
	    );
	delete $meta{bio};
	delete $meta{description};
    }
    my $profile_id = &make_cnode(\%cnode,%rev);

    if ($member->{photo}) {
	my ($filename,undef) = split /#/, $member->{photo};
	my $mime = &MimeType($filename);
	my %cnode = (
	    type=>$ctype{content}{content_type_id},
	    title=>"Photo of $name",
	    label=>"Photo",
	    parent=>$profile_id,
	    access=>$access,
	    status=>0,
	    ctime=>$member->{ctime},
	    );
	&cnode_name(\%cnode,"$name photo");
	%rev = (
	    data=>$member->{photo},
	    'format'=>"file",
	    mime_type=>$mime,
	    note=>"import",
	    view=>{ thumbnail=>1 }
	    );
	if ($member->{thumbnail}) {
	    $rev{view}{thumbnail} = {
		data=>$member->{thumbnail},
		mime_type=>$mime,
		'format'=>"file",
	    };
	}
	my $photo_id = &make_cnode(\%cnode,%rev);
    }

    # member attributes
    foreach my $metakey (keys %meta) {
	# Y/N metadata - convert to flags?
	if ($meta{$metakey}) {
	    &add_metadata($metakey,$meta{$metakey}{value},$profile_id);
	}
    }
    if ($member->{first_name}) {
	&add_metadata("first_name",$member->{first_name},$profile_id);
    }
    if ($member->{last_name}) {
	&add_metadata("last_name",$member->{last_name},$profile_id);
    }
    if ($member->{middle_name}) {
	&add_metadata("middle_name",$member->{middle_name},$profile_id);
    }
    if ($member->{gender}) {
	&add_metadata("gender",$member->{gender},$profile_id);
    }
    if ($member->{honorific}) {
	&add_metadata("honorific",$member->{honorific},$profile_id);
    }
    ### FIXME: detect file type attributes, reinstall as content objects
    ### example: spouse_mug_shot in JPD

    $old2new{"profile $member->{member_id}"} = $profile_id;
    print "profile $name\n";

    foreach my $stat (@status) {
	$db->insert("content_date",{content_id=>$profile_id,type=>"log",description=>$stat->{note},start=>$stat->{date},status=>"active"});
    }

    # expiry date
    if ($member->{expirydate} && $member->{expirydate} !~ /^0/) {
	if (! $final_status) { # member is active - add an expiry task
	    $db->insert("content_date",{content_id=>$profile_id,type=>"task",description=>"expire",start=>$member->{expirydate},status=>"active"});
	}
    }

    # keys, user
    $db->insert("content_key",{uid=>$member->{member_id},type=>"grant",role=>"owner"});
    if ($acct2contact{$uid2acct{$member->{member_id}}}{$profile_contact_type}) {
	$db->update("contact",
		    {content_id=>$profile_id,account_id=>undef},
		    {account_id=>$uid2acct{$member->{member_id}},type=>$profile_contact_type}
	    );
    }
    return $profile_id;
}

my %catmap;
sub make_catalog {
    my (@cat) = @_;
    # get service page
    my @serv = $db3->fetch_match("service",{section_id=>$section_id,name=>"Catalog"});
    my ($oldcatpage,$template);
    if (@serv > 0 && $serv[0]{page_id}) {
	$oldcatpage = $db3->fetch("page",$serv[0]{page_id});
    }
    if ($oldcatpage) {
	$template = $old2new{"page ".$oldcatpage->{template_id}};
    }
    else {
	print "WARNING: no Catalog service page, Catalogs need to be manually configured\n";
    }
    my %cnode = (
	type=>$ctype{catalog}{content_type_id},
	title=>"Catalog",
	label=>"Catalog",
	name=>"Catalog",
	template=>$template,
	parent=>$new_section_id,
	access=>0,
	content_role=>"editorial",
	publish=>"static",
	status=>0,
	);
    my $catalog_id = &make_cnode(\%cnode);
    print "Catalog...\n";

    # build a catalog tree
    #parent=>, type=>, data=>
    my $ctree = new ExSite::Tree("id","parent");
    my %cmap;
    my $id = 0;
    # - start with categories
    my %cat = &keywise("catalog_category_id",\@cat);
    my @cjoin = $db3->fetch_all("catalog_category_join");
    my %cjoin = &keywise("catalog_category_join_id",\@cjoin);
    my $parent_cat = 0;
    my @allcat;
    # start the tree:
#    foreach my $cj (@cjoin) {
#	# exclude categories from other catalogs
#	next if (! exists $cat{$cj->{child}});
#	if ($cj->{parent} == 0) {
#	    $id++;
#	    $ctree->addtopnode({id=>$id,parent=>0,type=>"c",data=>$cat{$cj->{child}}});
#	    $cmap{"category ".$cj->{child}} = $id;
#	    push @allcat, $cj->{child};
#	}
#    }

    # topnodes:
    my @unjoin = $db3->custom_query("select c.* from catalog_category c left join catalog_category_join j on j.child=c.catalog_category_id where c.section_id=$section_id and (j.parent is null or j.parent=0)");
    foreach my $uj (@unjoin) {
	$id++;
	$ctree->addtopnode({id=>$id,parent=>0,type=>"c",data=>$uj});
	$cmap{"category ".$uj->{catalog_category_id}} = $id;
	push @allcat, $uj->{catalog_category_id};
    }

    # fill out the tree:
    while (scalar @allcat > 0) {
	my $cat = pop @allcat;
	foreach my $cj (@cjoin) {
	    next if (! exists $cat{$cj->{child}});
	    if ($cj->{parent} == $cat) {
		$id++;
		my $parent = $cmap{"category ".$cj->{parent}};
		$ctree->addnode({id=>$id,parent=>$parent,type=>"c",data=>$cat{$cj->{child}}});
		$cmap{"category ".$cj->{child}} = $id;
		push @allcat, $cj->{child};
	    }
	}
    }
    # populate tree with products
    my @prod = $db3->fetch_all("catalog_product");
    my %prod = &keywise("catalog_product_id",\@prod);
    my @pjoin = $db3->fetch_all("catalog_product_category_join");
    my %pjoin = &keywise("catalog_product_category_join_id",\@cjoin);
    foreach my $pj (@pjoin) {
	next if (! exists $cat{$pj->{catalog_category_id}});
	my $parent = $cmap{"category ".$pj->{catalog_category_id}};
	my $prod = $prod{$pj->{catalog_product_id}};
	$id++;
	$ctree->addnode({id=>$id,parent=>$parent,type=>"p",data=>$prod});
	$cmap{"product ".$pj->{catalog_product_id}} = $id;
    }

    # now, walk the catalog tree, and generate the corresponding content tree
    my @top = $ctree->get_topnodes_data();
    foreach my $cdata (@top) {
	if ($cdata->{type} eq "c") {
	    &catalog_to_cnode( $catalog_id, $template, $cdata, $ctree );
	}
	else { # product
	    &product_to_cnode( $catalog_id, $template, $cdata, $ctree );
	}
    }
}

sub catalog_to_cnode { 
    my ($parent,$template,$cdata,$tree) = @_;
    my $cat = $cdata->{data};
#    return if ($cat->{status} eq "disabled");
    my %cnode = (
	type=>$ctype{catalog}{content_type_id},
	title=>$cat->{title},
	label=>$cat->{title},
	name=>$cat->{code},
	template=>$template,
	parent=>$parent,
	access=>0,
	content_role=>"editorial",
	publish=>"static",
	status=>$cat->{status} eq "disabled" ? 7 : 0,
	hide=>($cat->{status} =~ /hidden/ ? "indexes" : undef),
	);
    &cnode_name(\%cnode);
    my %rev;
    if ($cat->{description}) {
	%rev = (
	    data=>$cat->{description},
	    'format'=>"text",
	    mime_type => "text/html",
	    note=>"import"
	    );
    }
    my $catid = &make_cnode(\%cnode,%rev);
    print "catalog $cat->{title}\n";
    $old2new{"catalog_category $cat->{catalog_category_id}"} = $catid;
    $catmap{$cdata->{id}} = $catid;
    my @child = $tree->get_child_data($cdata->{id});
    foreach my $cdata (@child) {
	if ($cdata->{type} eq "c") { # catalog category
	    &catalog_to_cnode( $catid, $template, $cdata, $tree );
	}
	else { # product
	    &product_to_cnode( $catid, $template, $cdata, $tree );
	}
    }
}

sub product_to_cnode { 
    my ($parent,$template,$cdata,$tree) = @_;
    my $prod = $cdata->{data};

#    return if ($prod->{status} eq "disabled");
    my %cnode = (
	type=>$ctype{product}{content_type_id},
	title=>$prod->{title},
	label=>$prod->{code} || $prod->{title},
	template=>$template,
	parent=>$parent || 0,
	access=>0,
	content_role=>"editorial",
	publish=>"static",
	status=>$prod->{status} eq "disabled" ? 7 : 0,
	sortkey=>$prod->{sortkey},
	hide=>($prod->{status} =~ /hidden/ ? "indexes" : undef),
	ctime=>$prod->{mtime},
	);
    &cnode_name(\%cnode);

    if ($product_done{$prod->{catalog_product_id}}) {
	# already inserted this product, make an alias instead
	$cnode{type} = $ctype{alias}{content_type_id};
	$cnode{master} = $old2new{"catalog_product $prod->{catalog_product_id}"};
	$cnode{template} = 0;
	# aliases are skooky, insert directly
	my $prodid = $db->insert("content",\%cnode);
	print "alias to product $prod->{title}\n";
	return $prodid;
    }
    $product_done{$prod->{catalog_product_id}} = 1;

    my %rev;
    my $details = $prod->{details};
    my $summary = $prod->{summary};
    my $length = length(&html_to_plaintext($details));
    if (! $details || $length < 5) {
	$details = $prod->{summary};
	$summary = undef;
	$length = length(&html_to_plaintext($details));
    }
    if ($details && $length >= 5) {
	%rev = (
	    data=>$details,
	    'format'=>"text",
	    mime_type => "text/html",
	    note=>"import"
	    );
    }
    my $prodid = &make_cnode(\%cnode,%rev);
    print "product $prod->{title}\n";
    $old2new{"catalog_product $prod->{catalog_product_id}"} = $prodid;
    $catmap{$cdata->{id}} = $prodid;

    my $p = new ExSite::Product(id=>$prodid);
    if ($summary && length($summary) > 12) {
	$p->meta_set("description",$summary);
    }

    # prices
    if ($prod->{price} && $prod->{price} > 0.00) {
	$db->insert("price",{content_id=>$prodid,status=>"active",cost=>$prod->{price},acctcode_id=>$prod->{acctcode_id},access=>0});
    }
    if ($prod->{price_member} && $prod->{price_member} > 0.00 && $prod->{price_member} != $prod->{price}) {
	$db->insert("price",{content_id=>$prodid,status=>"active",cost=>$prod->{price_member},description=>"member price",acctcode_id=>$prod->{acctcode_id},access=>2});
    }

    if ($prod->{options}) {
	foreach my $option (split(/;/,$prod->{options})) {
	    my ($key,$val);
	    if ($option =~ /=/) {
		($key,$val) = split /=/, $option;
	    }
	    else {
		$key = "Option";
		$val = $option;
	    }
	    $p->meta_set("option_$key",$val);
	}
    }
    if ($prod->{size}) {
	$p->meta_set("shipping_size",$prod->{size});
    }
    if ($prod->{acctcode_id}) {
	$p->meta_set("acctcode",$prod->{acctcode_id});
    }
    $p->save;

    my @attachment = $db3->fetch_child("catalog_product_attachment","catalog_product",$prod->{catalog_product_id});
    foreach my $att (@attachment) {
	my $title = $att->{heading};
	if (! $title) {
	    ($title,undef) = split /\#/, $att->{upload};
	    $title =~ s/\.\w+$//;
	}
	my %cnode = (
	    type=>$ctype{content}{content_type_id},
	    title=>$title,
	    label=>$title,
	    access=>$access{public},
	    content_role=>"editorial",
	    publish=>"static",
	    status=>0,
	    parent=>$prodid,
	    );
	&cnode_name(\%cnode);
	my %rev = ( note=>"import" );
	$rev{data} = $att->{upload};
	$rev{format} = "file";
	$rev{view}{thumbnail} = 1;
	$rev{view}{small} = 1;
	my $attid = &make_cnode(\%cnode,%rev);
	print "product image $title\n";
	if ($attid && $att->{description}) {
	    my $c = new ExSite::Content(id=>$attid);
	    $c->meta_set("caption",$att->{description});
	    $c->save;
	}
    }
}

### templates - move under form

sub make_forms {
    my (@form) = @_;
    # get service page
    my @serv = $db3->fetch_match("service",{section_id=>$section_id,name=>"QA"});
    my ($oldformpage,$template);
    if (@serv > 0 && $serv[0]{page_id}) {
	$oldformpage = $db3->fetch("page",$serv[0]{page_id});
    }
    if ($oldformpage) {
	$template = $old2new{"page ".$oldformpage->{template_id}};
    }
    else {
	print "WARNING: no QA service page, Forms need to be manually configured\n";
    }
    # make a dummy page to hold forms
    my %cnode = (
	type=>$ctype{page}{content_type_id},
	title=>"Forms",
	label=>"Forms",
	name=>"forms",
	template=>$template,
	parent=>$new_section_id,
	access=>0,
	hide=>"menu; sitemap; indexes; search; robots",
	content_role=>"editorial",
	publish=>"dynamic",
	status=>0,
	);
    &cnode_name(\%cnode);
    my $page_id = &make_cnode(\%cnode);
    print "Forms...\n";

    foreach my $fdata (@form) {
	my %cnode = (
	    type=>$ctype{form}{content_type_id},
	    title=>$fdata->{title},
	    label=>$fdata->{title},
	    template=>$template,
	    parent=>$page_id,
	    access=>($fdata->{flags}=~/members/?1:0),
	    content_role=>"editorial",
#	    publish=>"dynamic",
	    status=>0,
	    );
	&cnode_name(\%cnode,$fdata->{name});
	my $form_id = &make_cnode(\%cnode);
	$old2new{"qa_form ".$fdata->{qa_form_id}} = $form_id;
	print ("form $fdata->{title}\n");

	# template
	if ($fdata->{template}) {
	    # remember template for later, since it may not have been created yet
	    $form{template}{$form_id} = $fdata->{template};
	}

	# questions
	my @questions = $db3->fetch_child("qa_question","qa_form",$fdata->{qa_form_id});
	foreach my $q (@questions) {
	    my $b = $db3->fetch("qa_base",$q->{qa_base_id});
	    next if (! $b);
	    my $flags = $q->{flags};
	    my $format = $b->{format};
	    if ($format eq "string") { $format = undef; }
	    elsif ($format eq "textarea") { $format = "long text"; }
	    my %cnode = (
		type=>$ctype{question}{content_type_id},
		title=>$b->{label},
		label=>$b->{label},
		name=>$q->{name} || $b->{name} || "q_".$q->{qa_question_id},
		parent=>$form_id,
		access=>($flags=~/admin/?5:0),
		content_role=>"editorial",
		publish=>"never",#"dynamic",
		status=>0,
		);
	    my $question_id = &make_cnode(\%cnode);
	    $old2new{"qa_question ".$q->{qa_question_id}} = $question_id;
	    print ("- question $cnode{title}\n");
	    my $qnew = new Modules::Forms::Question(id=>$question_id);
	    $qnew->meta_set("format",$format) if $format;
	    my $datatype = &qa_datatype($b);
	    $qnew->meta_set("datatype",$datatype) if ($datatype && $datatype ne "string");
	    my $value = $q->{value};
	    if ($value) {
		if ($flags =~ /placeholder/) {
		    $qnew->meta_set("placeholder",$value);
		}
		else {
		    $qnew->meta_set("preset",$value);
		}
	    }
	    $value = $b->{value};
	    $qnew->meta_set("options",$value) if $value;
	    my $size = $b->{size};
	    $qnew->meta_set("size",$size) if $size;
	    $qnew->set_flag("required") if ($flags =~ /required/);
	    $qnew->save;
	}

	foreach my $r ($db3->fetch_match("qa_response",{qa_form_id=>$fdata->{qa_form_id}})) {
	    my $rid = $db->insert("response",{form_id=>$form_id,uid=>$r->{member_id},language=>$r->{version},note=>$r->{note},ctime=>$r->{ctime}});
	    if ($rid) {
		foreach my $a ($db3->fetch_match("qa_answer",{qa_response_id=>$r->{qa_response_id}})) {
		    $db->insert("answer",{response_id=>$rid,question_id=>$old2new{"qa_question $a->{qa_question_id}"},value=>$a->{value}});
		}
		$old2new{"qa_response $r->{qa_response_id}"} = $rid;
	    }
	}
    }
}

sub qa_datatype {
    my $b = shift;
    if ($b) {
	my $fmt = $b->{format};
	if ($fmt eq "password") {
	    return "password";
	}
	my $val = $b->{value};
	if ($val && $fmt =~/string|textarea|password/) {
	    return $val;
	}
	else {
	    return ($fmt =~ /textarea/) ? "text" : "string";
	}
    }
    return undef;
}

sub install_page_content {
    my ($oldpid,$newpid,$content) = @_;
    if (! $content) {
	(my $page,$content) = &get_page_and_content($oldpid);
    }
    my %done;
    foreach my $key (keys %$content) {
	my $name = $content->{$key}{content}{name};
	my ($caption,$description);
	my %cnode = (
	    type=>$ctype{content}{content_type_id},
	    title=>$name,
	    label=>$name,
	    name=>&clean_filename($name),
	    access=>$access{public},
	    content_role=>$content->{$key}{content}{type},
#	    publish=>"static",
	    status=>0,
	    parent=>$newpid,
	    ctime=>$content->{$key}{content}{ctime},
	    );
	if ($done{$cnode{name}}) {
	    # duped name (!)
	    $cnode{name} .= "_" . &randtext(3,"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz01234567890");
	}
	my %rev;
	if ($content->{$key}{content_data}) {
	    my $cdata = $content->{$key}{content_data};
	    %rev = ( note=>"import", mime_type=>$cdata->{mime_type} );
	    if ($cdata->{data}) {
		$rev{data} = $cdata->{data};
		$rev{format} = "text";
	    }
	    elsif ($cdata->{url}) {
		$rev{data} = $cdata->{url};
		$rev{format} = "url";
	    }
	    elsif ($cdata->{file}) {
		if ($config{content}{install_files}) {
		    # convert back to fdata, which will reconvert to path in revise()
		    my @path = split /\//,$cdata->{file};
		    my $fdata = &get_file($cdata->{file});
		    $rev{data} = $path[-1]."#".encode_base64($fdata,"");
		    $rev{format} = "file";
		}
		else {
		    # leave file in original location (!) ### FIXME?
		    $rev{data} = $cdata->{file};
		    $rev{format} = "path";
		    print "WARNING: file $cdata->{file} not imported\n";
		}
	    }
	    else {
		$rev{data} = $cdata->{fdata};
		$rev{format} = "file";
		my %attr = &DecodeAttributes($cdata->{attributes});
		$rev{attributes} = \%attr;
		if ($cdata->{thumb}) {
		    # add a thumbnail revision
		    $rev{view}{thumbnail} = {
			type=>"thumbnail",
			mime_type=>$cdata->{mime_type},
			'format'=>"file",
			data=>$cdata->{thumb},  ################# filename may clash with main file
			attributes=>$cdata->{thumb_attributes}
		    };
		}
		# for large pics, also add a small size
		if ($cdata->{mime_type} =~ /image/) {
		    my $h = $attr{height};
		    my $w = $attr{width};
		    my $size = $h > $w ? $h : $w;
		    if ($size > 500) {
			$rev{view}{small} = 1;
		    }
		}
	    }
	    if ($content->{$key}{content}{description}) {
		if ($content->{$key}{content_data}{mime_type} =~ /image/) {
		    # assume it's a caption
		    $caption = $content->{$key}{content}{description};
		}
		else {
		    $description = $content->{$key}{content}{description};
		}
	    }
	}
	my $subcontent_id = &make_cnode(\%cnode,%rev);
	if ($caption || $description) {
	    my $newc = new ExSite::Content(id=>$subcontent_id);
	    $newc->meta_set("caption",$caption) if $caption;
	    $newc->meta_set("description",$description) if $description;
	    $newc->save();
	}
        print "- content $name\n";
	$old2new{"content $content->{$key}{content}{content_id}"} = $subcontent_id;
	$done{$cnode{name}} = 1;
    }
}

sub get_page_and_content {
    my $page = shift;
    my $pagedata = ref $page ? $page : $db3->fetch("page",$page);
    my @content = $db3->fetch_child("content","page",$pagedata->{page_id});
    my @cdata;
    my %cdata;
    foreach my $c (@content) {
	my @cdata = $db3->fetch_child("content_data","content",$c->{content_id},"content_data_id desc",1);
	$cdata{$c->{name}} = { content=> $c, content_data=>$cdata[0] };
    }
    return ($pagedata, \%cdata);
}

sub convert_accounts {
    foreach my $account ($db3->fetch_match("account",{section_id=>$section_id})) {
	my @invoice = $db3->fetch_match("receivable",{account_id=>$account->{account_id}});
	my @contact = $db3->fetch_match("contact",{account_id=>$account->{account_id}});
	next if (scalar @invoice == 0 && 
		 (! $account->{member_id} || scalar @contact == 0)); # no history
	$account->{name} = &utf8encode($account->{name});
	$account->{uid} = $account->{member_id};
	delete $account->{member_id};
	$account->{section_id} = $new_section_id;
	my $acct_id = $db->insert("account",$account); # keep account_id
	$uid2acct{$account->{uid}} = $acct_id;
	print "account $account->{name}\n";
	if ($acct_id) {
	    foreach my $contact (@contact) {
		&add_contact($contact);
	    }
	}
    }
}

sub add_contact {
    my $contact = shift;
    my %info_fields = (
	address => "address",
	city => "city",
	provstate => "provstate",
	country => "country",
	pcode => "pcode",
	phone1 => "phone",
	phone2 => "cell",
	fax => "fax",
	email => "email",
	web => "website"
	);
    my %info;
    foreach my $key (keys %info_fields) {
	if ($contact->{$key}) {
	    $info{$info_fields{$key}} = &utf8encode($contact->{$key});
	}
	delete $contact->{$key};
    }
    delete $contact->{location_id};
    delete $contact->{section_id};  ## ?
    $contact->{name} = &utf8encode($contact->{info});
    delete $contact->{info};
    $contact->{privacy} = $access{$contact->{privacy}};
    if (scalar keys %info) {
	my $contact_id = $db->insert("contact",$contact);
	if ($contact->{account_id}) { 
	    if ($acct2contact{$contact->{account_id}}{$contact->{type}}) {
		push @{$acct2contact{$contact->{account_id}}{$contact->{type}}}, $contact_id;
	    }
	    else {
		$acct2contact{$contact->{account_id}}{$contact->{type}} = [ $contact_id ];
	    }
	}
	foreach my $key (keys %info) {
	    $db->insert("contact_info",{contact_id=>$contact_id,name=>$key,value=>$info{$key}});
	}
	return $contact_id;
    }
    return undef;
}

sub convert_invoices {
    my $acct_id = shift;
    print "converting invoices...\n";
    foreach my $account ($db3->fetch_match("account",{section_id=>$section_id})) {
	my @invoice = $db3->fetch_match("receivable",{account_id=>$account->{account_id}});
	foreach my $invoice (@invoice) {
	    my @item = $db3->fetch_match("receivable_item",{receivable_id=>$invoice->{receivable_id}});
	    next if ($copy_invalid_finances && $invoice->{status} =~ /^inactive|canceled$/);
	    if (scalar @item > 0) {
		delete $invoice->{member_id}; #### not supported yet
		my $inv_id = $db->insert("receivable",$invoice); # keep receivable_id
		foreach my $item (@item) {
		    $item->{status} = "active";
		    $item->{uid} = $item->{member_id};
		    $item->{item} = &utf8encode($item->{item});
		    $item->{description} = &utf8encode($item->{description});
		    delete $item->{member_id};
		    if ($item->{objtype} && $item->{objid}) {
			if ($item->{objtype} eq "evt_reg") {
			    my ($reg,$fee,$fee_id,$evt_id);
			    $reg = $db3->fetch("evt_reg",$item->{objid});
			    if ($reg) { 
				$fee_id = $reg->{evt_fee_id};
				if ($fee_id) {
				    $fee = $db3->fetch("evt_fee",$fee_id);
				    if ($fee) {
					$evt_id = $fee->{evt_id};
					my $evt = $db3->fetch("evt",$evt_id);
					if ($evt && $evt->{parent}) {
					    $evt_id = $evt->{parent};
					}
				    }
				}
			    }
			    $item->{objtype} = "ticket";
			    $item->{objid} = $old2new{"evt_reg $item->{objid}"};
			    $item->{acctcode2} = $old2new{"evt $evt_id"};
			    $item->{acctcode3} = $old2new{"fee $fee_id"};
			}
			elsif ($item->{objtype} eq "member") {
			    my $member = $db3->fetch("member",$item->{objid});
			    my $profile_id = $old2new{"profile $item->{objid}"};
			    my $profile = $db->fetch("content",$profile_id);
			    $item->{objtype} = "content";
			    $item->{objid} = $old2new{"profile $item->{objid}"};
			    if ($profile) {
				$item->{acctcode2} = $profile->{parent};
				$item->{acctcode3} = $profile->{content_id};
			    }
			}
			elsif ($item->{objtype} eq "catalog_product") {
			    my $product = $db3->fetch("catalog_product",$item->{objid});
			    my $newproduct = $db->fetch("content",$old2new{"catalog_product $item->{objid}"});
			    $item->{objtype} = "content";
			    $item->{objid} = $old2new{"catalog_product $item->{objid}"};
			    if ($newproduct) {
				$item->{acctcode2} = $newproduct->{parent};
				$item->{acctcode3} = $newproduct->{content_id};
			    }
			}
			else {
			    # ? unknown purchase
			    delete $item->{objtype};
			    delete $item->{objid};
			}
		    }
		    else {
			delete $item->{objtype};
			delete $item->{objid};
		    }
		    $db->insert("receivable_item",$item);
		}
	    }
	}
	foreach my $payment ($db3->fetch_match("payment",{account_id=>$account->{account_id}})) {
	    next if ($copy_invalid_finances && $payment->{status} eq "canceled");
	    $payment->{uid} = $payment->{member_id};
	    delete $payment->{member_id};
	    $db->insert("payment",$payment);
	}
    }
}

sub add_metadata {
    my ($name,$value,$content_id) = @_;
    return $db->insert("metadata",
		{name=>$name,
		 value=> &utf8encode($value),
		 id=>$content_id
		});
}

sub utf8encode {
    my $text = shift;
    return $latin1_to_utf8 ?
	Encode::encode("utf8", Encode::decode("ISO-8859-1", $text)) :
	$text;
}
