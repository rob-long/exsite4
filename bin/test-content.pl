#!/usr/bin/perl -d

# test content

### TODO:
# - build restricted-access pages as public, member, and admin

use strict;
use Test::More 'no_plan';
use ExSite::Config;
use ExSite::Misc;
use ExSite::Form;
use ExSite::Module;
use ExSite::Section;
use ExSite::Page;
use ExSite::Template;
use ExSite::Library;

my $section_id = shift @ARGV;

# fake Apache env
my $cwd = `pwd`;
chomp $cwd;
my @cwd = split /\//,$cwd;
$ENV{SCRIPT_NAME} = "/cgi/ex.cgi";
$ENV{SERVER_NAME} = "www.foo.com";
$ENV{SCRIPT_FILENAME} = "$cwd/ex.cgi";
$ENV{REQUEST_URI} = "/cgi/ex.cgi";
$ENV{PATH_INFO} = "/page";
pop @cwd;
push @cwd, "html";
$ENV{DOCUMENT_ROOT} = join "/",@cwd;

&exsite_init;
(tied %cookie)->publish_mode();
my $db = new ExSite::Form;
my (%siteurl,%sitepath);
my (%tested,%url,%path,%diskpath);
my ($section,%page,%servpage,%filename,@version);
my $content = new ExSite::Content();

my @languages = &ExSite::Config::get_languages(1);
my @site = $section_id ? 
    ( scalar $db->fetch("content",$section_id) ) :
    $db->fetch_match("content",{type=>1});
foreach my $s (@site) {
    print "\n===> $s->{title}\n\n";
    &test_section($s);
}

sub test_content {
    my ($c,$name,$id) = @_;
    $id or $id = $c->id;
    return if $tested{$id};
    my $filename = $c->name();
    $name or $name = $c->subtype()." $id ($filename)";
    my @err = $section->validate();
    ok(scalar @err == 0,"no validation errors on $name");
    if (@err > 0) {
	print "VALIDATION ERROR: ",(join "\nVALIDATION ERROR: ",@err),"\n";
    }
    ok($c->title,"$name has a title");
    ok($c->title,"$name has a label");
    my $path = $c->path();
    ok(! exists $path{$path},"unique path for $name");
    $path{$path} = 1;
    my $url = $c->get_url_canonical();
    ok(! exists $url{$url},"unique URL for $name");
    $url{$url} = 1;
    my $dpath = $c->diskpath() . "/" . $c->filename();
    my $filename = $c->filename();
    ok(! exists $diskpath{$dpath},"unique diskpath for $name");
    $diskpath{$dpath} = 1;
    ok($filename !~ /test/,"$name is not test data");
    $tested{$id} = 1;

    # path - check for loops
    my $path = $c->content_path();
    ok($path,"path to $name has no loops");

    if ($c->subtype_attr("displaytype") eq "formatted") {
	# displays like a page, test templates
	my $t = $c->template();
	my $tid = $t->id;
	ok($tid,"$name has template set");
	
	if ($t->ok) {
	    is($t->subtype(),"template","$name has a proper template");
	    if ($t->subtype eq "template") {
		my %template;
		while ($tid) {
		    if (exists $template{$tid}) {
			fail("no template loop on $name");
			last;
		    }
		    $template{$tid} = 1;
		    $t = $t->template();
		    $tid = $t->id;
		}
	    }
	}

    }
}

sub test_section {
    my $data = shift;
    $section = new ExSite::Section(data=>$data);
    my $sid = $section->id;
    my $name = "section $sid (".$section->title().")";

    &test_content($section,$name,$sid);
    ok($section->is_static,"$name is static");
    # fetch service pages
    my @licence = $db->fetch_match("service",{section_id=>$section->id});
    my @serv;
    foreach my $l (@licence) {
	push @serv, $l if ($l->{page_id});
    }
    %servpage = &keywise("content_id",\@serv);
    delete $servpage{0}; # module license only

    # test pages
    my @page = $section->get_all_pages();
    foreach my $p (@page) {
	&test_page($p);
    }

    # any service pages left untested??
    my @servid = keys %servpage;
    ok(scalar @servid == 0,"no unused service pages ".join(",",@servid));

    # test templates
    my @templ = $section->fetch_content($section->isubtype("template"));
    foreach my $t (@templ) {
	&test_template($t);
    }

    # test libraries
    my @lib = $section->fetch_content($section->isubtype("library"));
    foreach my $l (@lib) {
	&test_library($l);
    }

    # translations
    &test_translations(@page);

    # posts
    &test_posts();

    &test_plugins($section);
}

sub test_page {
    my $p = $section->get_content_obj(shift);
    $share{Page} = $p;
    delete $share{diagnostics};
    my $pid = $p->id;
    my $filename = $p->name();
    my $name = $p->subtype()." $pid ($filename)";
    &test_content($p,$name,$pid);

    my $body = $p->my_content("body");
    my $bodyhtml;
    if (defined $body) {
	$bodyhtml = $body->get_html();
	ok($bodyhtml,"$name body has HTML content");
    }
    if ($p->subtype eq "page" && ! defined $body) {
	fail("$name has a body");
    }
    ok($p->name() !~ /\.html?$/,"$name does not have a suffix");

    # EXAMINE HTML
    my $html = $p->expand();
    &test_html($html,$name,$p);

    if ($servpage{$pid}) {
	is($p->getdata("publish"),"dynamic","service page for $servpage{$pid}{name} is dynamic");
	if (defined $body) {
	    $bodyhtml =~ /<!--(\&+)(\w+)\((.*)\)-->/;
	    is($1,"&","non-AJAX service oyster on $name");
	    is($2,$servpage{$pid}{name},"body oyster matches service on $name");
	    is($3,"","service oyster has blank params on $name");
	}
	delete $servpage{$pid};
    }

    # error check
    if (&AtError(0)) {
	fail("no errors logged on $name");
	print &ExSite::Config::show_diagnostics("text",3),"\n";
    }
}

sub test_html {
    my ($html,$name,$p) = @_;
    ok($html,"$name has HTML");
    return if (! $html);
    ok($html =~ /<!DOCTYPE HTML/i,"HTML doctype on $name");
    ok($html =~ /<title>.+<\/title>/i,"$name has a title");
    my $i = 0;
    while ($html =~ /ex\.cgi\/app/) {
	$i++;
	$html =~ s/ex\.cgi\/app/DCD-CGI/;
    }
    if ($i > 0) {
	ok($p->is_static,"AJAX plugins on static pages only; $name");
	ok($i < 3,"no more than 2 AJAX plugins on one page; $name");
    }
    $i = 0;
    while ($html =~ /ex\.cgi\/view/) {
	$i++;
	$html =~ s/ex\.cgi\/view/CONTENT-CGI/;
    }
    ok($i==0,"no unpublished content on $name");
    $i = 0;
    while ($html =~ /ex\.cgi\/peek/) {
	$i++;
	$html =~ s/ex\.cgi\/peek/GETDATA-CGI/;
    }
    ok($i==0,"no dynamic data views on $name");
    # mailto:
    ok($html !~ /href=.?mailto:\w/i,"no mailto: links on $name");
}

sub test_template {
    my $data = shift;
    delete $share{diagnostics};
    my $t = new ExSite::Template(data=>$data);
    my $tid = $t->id;
    my $filename = $t->name;
    my $name = "template $tid ($filename)";
    &test_content($t,$name,$tid);

    my %contents = $t->get_contents_as_hash();
    my $ncont = scalar keys %contents;
    ok($ncont > 0,"$name has content");
    if ($ncont) {
	if (! $data->{template}) {
	    ok(exists $contents{page},"base $name has page object");
	}
	my $nedit = 0;
	foreach my $c (values %contents) {
	    $nedit++ if ($c->getdata("content_role") =~ /editorial/);
	}
	ok($nedit < 8,"$name has fewer than 8 editorial objects");
	if ($nedit > 3) {
	    ok($nedit / $ncont < 0.5,"fewer than half of content objects in $name are editorial");
	}
    }

    # EXAMINE HTML
    my $html = $t->expand();
    &test_html($html,$name,$t);
    # error check
    if (&AtError(0)) {
	fail("no errors logged on $name");
	print &ExSite::Config::show_diagnostics("text",3),"\n";
    }
}

sub test_library {
    my $data = shift;
    my $l = new ExSite::Library(data=>$data);
    my $lid = $l->id;
    my $filename = $l->name();
    my $name = "library $lid ($filename)";
    &test_content($l,$name,$lid);
    ok($filename !~ /test/i,"$name is not a test library");
    my @contents = $l->get_contents();
    ok(scalar @contents > 0,"$name has content");
}

sub test_translations {
    my @page = @_;
    # test translations
    my %language;
    my (%alt,%master,%vers,%page);
    foreach my $p (@page) {
	my $lang = $p->{language} || $config{default_version};
	$language{$lang}++;
	if ($lang ne $config{default_version}) {
	    $alt{$lang}{$p->{content_id}} = $p;
	    $master{$lang}{$p->{master}} = $p;
	}
    }
    ok(scalar @languages == scalar keys %vers,"languages in use match defined languages");
    foreach my $l (@languages) {
	next if ($l eq $config{default_version});
	foreach my $pdata (values %{$alt{$l}}) {
	    my $p = new ExSite::Page(data=>$pdata);
	    my $filename = $p->name();
	    my $name = "translated page ".$p->id." ($filename)";
	    my $master = $p->master();
	    ok($master && $master->ok,"$name has master");
	    next if (! $master || ! $master->ok);
	    ok(! $master->language(),"master is $config{default_version}");
	    my @content = $p->get_contents();
	    ok(scalar @content > 0,"$name has content objects");
	    foreach my $c (@content) {
		ok($c->has_revisions(),"$name $c->{name} has revisions");
	    }
	}
    }
    foreach my $pdata (values %{$alt{$config{default_version}}}) {
	my $p = new ExSite::Page(data=>$pdata);
	foreach my $v (@version) {
	    next if ($v eq $config{default_version});
	    ok(exists $master{$v}{$p->id},"master page ".$p->id." has $v version");
	}
    }
}    

sub test_posts {
    if (-e "test_post.csv") {
	open F, "test_post.csv";
	foreach my $data (<F>) {
	    chomp;
	    my ($page_id,$login,$path,$query,$postdata) = split /,/;
	    delete $share{identity};
	    delete $share{diagnostics};
	    delete $ENV{PATH_INFO};
	    $ENV{PATH_INFO} = $path if $path;
	    delete $ENV{QUERY_STRING};
	    $ENV{QUERY_STRING} = $query if $query;
	    $ENV{CONTENT_LENGTH} = length $postdata;
	    open POST, ">post.dat";
	    print POST $postdata;
	    close POST;
	    $ENV{CGI_INPUT_FILE} = "post.dat";
	    $ENV{REQUEST_METHOD} = "POST";

	    {
		my $p = new ExSite::Page(id=>$page_id);
		$db->do_login($login) if $login;
		
		my $pid = $p->id;
		my $filename = $p->name();
		my $name = "page $pid ($filename)";

		# generate page
		my $html = $p->expand();
		
		# check for errors
		if ($@) {
		    fail("perl error posting to $name: $@");
		}
		if ($!) {
		    fail("system error posting to $name: $!");
		}
		if (&ExSite::Config::AtError(0)) {
		    fail("ExSite error posting to $name:");
		    print ExSite::Config::show_diagnostics("text",3);
		}
		$@ = undef;
		$! = undef;
	    }
	}
    }
    unlink "post.dat";
}

sub test_plugins {
    my ($section) = @_;
    my $sid = $section->id;
    my @mod = &ExSite::Module::module_list();
    foreach my $modname (@mod) {
	delete $share{diagnostics};
	my $m = &ExSite::Module::get_module($modname,undef,$section);
	if (&AtError(0)) {
	    fail("no errors logged in $modname");
	    print &ExSite::Config::show_diagnostics("text",3),"\n";
	}
	ok(ref $m,"launch $modname");
	if (ref $m) {
	    if ($m->ioctl("isService")) {
		# look for appropriate service pages
		my @service = $db->custom_query("select s.*,p.language,p.name from service s,content p where s.name=? and p.content_id=s.page_id",$modname);
		my %vserv = &keywise("language",\@service);
		foreach my $v (@languages) {
		    if ($v eq $config{default_version}) {
			ok($vserv{undef}||$vserv{''},"$modname has $config{default_version} service page");
		    }
		    else {
			ok($vserv{$v},"$modname has $v service page");
		    }
		}
	    }
	}
    }
}
