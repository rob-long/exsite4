package ExSite::Captcha;
#-----------------------------------------------------------------------
#
#   Copyright 2001-2007 Exware Solutions, Inc.  http://www.exware.com
#
#   This file is part of ExSite WebWare (ExSite, for short).
#
#   ExSite is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   ExSite is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with ExSite; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#   Users requiring warranty coverage and/or support may arrange alternate
#   commercial licensing for ExSite, by contacting Exware Solutions 
#   via the website noted above.
#
#----------------------------------------------------------------------------

use strict;
use ExSite::Config;
use ExSite::Base;
use ExSite::Misc;
use ExSite::Crypt;
use ExSite::Input;
use ExSite::ML;
use Digest::MD5 qw(md5_hex);

use vars qw(@ISA);
@ISA = qw(ExSite::Base);

use vars qw(@RANK);

# some human-readable position words
@RANK = ( "first", "second", "third", "fourth", "fifth", 
	 "sixth", "seventh", "eighth", "ninth", "tenth");

sub new ($%) {
    my ($this,%opt) = @_;
    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;
    # copy options into object
    while (my ($key,$val) = each %opt) {
	$obj->{$key} = $val;
    }
    if ($obj->{textmode} && ! $obj->{mode}) {
	$obj->{mode} = "text";
    }
    $obj->initialize_object;
    return $obj;
}

# make : create a captcha for a form

sub make {
    my ($this,$key) = @_;

    # see if we are writing to a specific captcha DOM ID
    my $in = new ExSite::Input;
    $in->path_info();
    my @path = $in->path();
    my $captcha_id = shift @path;
    $this->{captcha_id} = ($captcha_id =~ /[:alpha:]/) ? $captcha_id : "captcha";

    my $mode = $this->get("mode") || $config{captcha}{mode};
    if ($mode eq "text") {
	return $this->captcha_text($key);
    }
    elsif ($mode eq "passive") {
	return $this->captcha_passive($key);
    }
    else {
	return $this->captcha_image($key);
    }
}

# pass : evaluate whether the agent has passed the captcha test

sub pass {
    my $this = shift;
    my $mode = $this->get("mode") || $config{captcha}{mode};
    if ($mode eq "text") {
	return $this->pass_interactive(@_);
    }
    elsif ($mode eq "passive") {
	return $this->pass_passive(@_);
    }
    else {
	return $this->pass_interactive(@_);
    }
}

# pass_interactive : evaluate solutions of interactive (image/text) captchas

sub pass_interactive {
    my ($this,$guess,$encoded_key) = @_;
    my $idata = ExSite::Input->new()->combine();
    # $guess is what the user/robot answered
    if (! $guess) {
	# see if we can find it in the form data
	my $field = $this->get("answer_field") || "captcha";
	$guess = $idata->{$field};
	return 0 if (! $guess);
    }
    # $encoded_key is the solution, encrypted
    if (! $encoded_key) {
	# see if we can find it in the form data
	my $solution = $this->get("solution_field") || "captcha_solution";
	$encoded_key = $idata->{$solution};
	return 0 if (! $encoded_key);
    }
    my $decoded_key = $this->decrypt($encoded_key);
    return $guess =~ /^$decoded_key$/i;   # allow any case
}

# pass_passive : evaluate whether agent is behaving like a real user

sub pass_passive {
    my ($this,$key) = @_;

    my $idata = ExSite::Input->new()->combine();

    if ($config{captcha}{passive_method} =~ /honeypot/) {
	# check the dummy field
	my $name = $this->get("name") || $config{captcha}{honeypot_name};
	if ($idata->{$name}) {
	    # agent fell into the honeypot
	    $this->error("Captcha: agent entered data into forbidden field; IP=$ENV{REMOTE_ADDR}");
	    return 0;
	}
    }

    if ($config{captcha}{passive_method} =~ /postkey/) {
	# now check the validity of their key
	my $capkey = $cookie{$config{captcha}{postkey_cookie}};
	if (! $capkey) {
	    # agent has no posting key
	    $this->error("Captcha: agent has no posting key; IP=$ENV{REMOTE_ADDR}");
	    return 0;
	}
	my @capkey = split(",",$capkey);
	my $crypt = new ExSite::Crypt;
	my ($agenthash,$agentkey,$agenttime,$rand);
	my ($error,$found,@newcapkey);
	foreach my $capkey (@capkey) {
	    ($agenthash,$agentkey,$agenttime,$rand) = split /;/,$crypt->decrypt($capkey);
	    if ($agentkey eq $key) {
		if (! $rand) {
		    # bad postkey format
		    $error = "Captcha: bad posting key format; IP=$ENV{REMOTE_ADDR}";
		}
		if ($agentkey ne $key) {
		    # wrong context - reusing another captcha
		    $error = "Captcha: invalid key (agent is reusing an old posting key); IP=$ENV{REMOTE_ADDR}";
		}
		if ($config{captcha}{expire} &&
		    time - $agenttime > (3600 * $config{captcha}{expire})) {
		    # postkey expired
		    $error = "Captcha: posting key expired; IP=$ENV{REMOTE_ADDR}";
		}
		if ($agenthash ne md5_hex($ENV{REMOTE_ADDR},$ENV{HTTP_USER_AGENT})) {
		    # different agent
		    $error = "Captcha: agent using someone else's posting key; IP=$ENV{REMOTE_ADDR}";
		}
	    }
	    else {
		# looks like a good postkey
		return 1;
	    }
	}

	if ($error) {
	    # fail
	    $this->error($error); # this is the last error
	    return 0;
	}
    }

    # pass
    return 1;
}

sub captcha_image {
    my ($this,$key) = @_;

    my $ml = new ExSite::ML;
    my $ie_sucks = int(rand(100000));  # to prevent caching on IE6
    if ($share{Page} && $share{Page}->is_publishing()) {
	# use ajax
	my $out .= $ml->script(undef,{type=>'text/javascript',
				      src=>"$config{server}{HTMLpath}/_ExSite/js/httprequest.js"});
	$out .= $ml->script("\ndocument.write(getRequestData('$config{server}{CGIpath}/$config{prog}{captcha}/$this->{captcha_id}/$ie_sucks?key='))\n",
			    {type=>'text/javascript'});
	$out .= $ml->noscript("You will not be able to submit this form without enabling Javascript.");
	return $out;
    }
    if (! $key) {
	$key = 
	    $this->get("key") ||
	    &randtext(5,"abcdefhijkmnpqrstuvwxwz2345678");
    }
    my $key_crypt = $this->encrypt($key);
    
    my $img_id = $this->get("image_id") || "captcha_image";
    my $solution = $this->get("solution_field") || "captcha_solution";
    my $answer = $this->get("answer_field") || "captcha";
    my $prompt = $this->get("prompt") || "Enter the text you see:";

    my $out = $ml->script(undef,{src=>"$config{server}{HTMLpath}/_ExSite/js/httprequest.js", type=>"text/javascript"});

    $out .= $ml->table(
	$ml->tr(
	    $ml->td(
		$ml->span(
		    $ml->img(undef,{src=>"$config{server}{CGIpath}/$config{prog}{captcha}?$key_crypt", height=>"40", width=>"100"}).
		    $ml->input(undef,{type=>"hidden", name=>$solution, value=>$key_crypt}),
		    {id=>$img_id}
		    )
	    ).
	    $ml->td("&nbsp;$msg{$prompt} ".
		    $ml->input(undef,{type=>"text", name=>$answer, size=>8}))
	),
	{cellspacing=>0, cellpadding=>0}
	);
    
    my $link = $ml->a($msg{"New image"}." &#8635;",{onclick=>"javascript:subRequestData('$this->{captcha_id}','$config{server}{CGIpath}/$config{prog}{captcha}/$this->{captcha_id}/$ie_sucks?key=')",style=>"cursor:pointer;"});
    my $url = "$config{server}{CGIpath}/$config{prog}{captcha}/$this->{captcha_id}/$ie_sucks?captchamode=text&amp;key=";
    $link .= $this->{no_text_captcha} ? "" : $ml->br.$ml->a($msg{"Can't see the image?"},{onclick=>"javascript:subRequestData('$this->{captcha_id}','$url')",style=>"cursor:pointer;"});
    
    $out .= $link;

    return $this->{captcha_id} eq "captcha" ?
	$ml->div($out,{class=>"captcha",id=>$this->{captcha_id}}) : $out;
}

sub make_captcha_image {
    my ($this,$cryptkey) = @_;
    # basic captcha configuration

    my $captcha_command = "convert -font [[font]] [[size]] [[text]] -background white -fill '[[color]]' [[distort]] $config{server}{HTMLroot}$config{server}{HTMLpath}/_ExSite/images/captcha.png -";

    my $x = $config{captcha}{start_x};
    my $y = $config{captcha}{start_y};

    my %param = (
		 font=>$config{captcha}{font},
		 size=>"-pointsize $config{captcha}{pointsize}",
		 color=>$config{captcha}{color},
		 );

    # get our captcha text

    my $plaintext;
    my $t = tied %token;
    if ($config{token}{captcha} && $t->enabled) {
	# don't just look it up directly, or we will inadvertently expire it
	my $token = $t->fetch($cryptkey);
	if (ref $token eq "HASH") {
	    $plaintext = $token->{value};
	}
    }
    else {
	my $c = new ExSite::Crypt;
	$plaintext = $c->decrypt($cryptkey);
	if ($config{captcha}{expire}) {
	    # trim the timestamp
	    $plaintext =~ s/;.*//;
	}
    }

    # generate commands to write the text on the image

    my @text = split //,$plaintext;
    foreach my $t (@text) {
	my $y2 = $y + int(rand(10))-5;
	$param{text} .= "-draw \"text $x,$y2 '$t'\" ";
	$x += $config{captcha}{charsize};
    }

    # distort?

    if ($config{captcha}{distort}) {
	$param{distort} = "-implode $config{captcha}{distort}";
    }

    # generate the full image processing command

    my $cmd = &substitute($captcha_command,\%param);

    my $imgdata = `$cmd`;
    return $imgdata;
}

sub captcha_passive {
    my ($this,$key) = @_;
    # passive captchas work best if you explicitly pass a key in;  this
    # prevents the passive captcha from being re-used in a different context
    my $out;
    if ($config{captcha}{passive_method} =~ /postkey/) {
	if ($share{Page} && $share{Page}->is_publishing()) {
	    $out .= $this->captcha_passive_static($key);
	}
	else {
	    $out .= $this->captcha_passive_dynamic($key);
	}
    }
    if ($config{captcha}{passive_method} =~ /honeypot/) {
	# also include a honeypot field in the form
	my $name = $this->get("name") || $config{captcha}{honeypot_name};
	$out .= "<div style=\"height:1px; overflow:hidden; padding:1px;\">
Office use only:<br>
<textarea name=\"$name\" rows=4 cols=60></textarea>
</div>\n";
    }
    return $out;
}

sub captcha_passive_dynamic {
    my ($this,$key) = @_;
    my $postkey = $this->get_post_key($key);
    # pass our captcha token to the user to hold on to
    if ($cookie{$config{captcha}{postkey_cookie}}) {
	my @postkey = split /,/,$cookie{$config{captcha}{postkey_cookie}};
	if (@postkey >= $config{captcha}{max_postkey}) {
	    shift @postkey;
	}
	push @postkey, $postkey;
	$cookie{$config{captcha}{postkey_cookie}} = join(",",@postkey);
    }
    else {
	$cookie{$config{captcha}{postkey_cookie}} = $postkey;
    }
    return "";
}

# Static captchas ask the server for a posting key;  of course any robot can
# be programmed to do the same thing.

sub captcha_passive_static {
    my ($this,$key) = @_;
    my $ml = new ExSite::ML;
    my $out .= $ml->script(undef,{type=>'text/javascript',
				  src=>"$config{server}{HTMLpath}/_ExSite/js/httprequest.js"});
    $out .= $ml->script(undef,{type=>'text/javascript',
			       src=>"$config{server}{HTMLpath}/_ExSite/js/misc.js"});
#    my $domain = $config{server}{host} ? 
#	".$config{server}{domain}" : 
#	$config{server}{domain}; 
    $out .= $ml->script("\nvar postkey = getRequestData('$config{server}{CGIpath}/$config{prog}{captcha}?postkey=$key');
var oldpostkey = get_cookie('$config{captcha}{postkey_cookie}');
var postkeys = oldpostkey ? oldpostkey.split(',') : [];
postkeys.push(postkey);
if (postkeys.length > $config{captcha}{max_postkey}) { postkeys.shift(); }
var newpostkey = postkeys.join(',');
set_cookie('$config{captcha}{postkey_cookie}', newpostkey);\n",
#set_cookie('$config{captcha}{postkey_cookie}', newpostkey, 0, '$domain');\n",
#document.cookie = '$config{captcha}{postkey_cookie}=' + oldpostkey + postkey + '; path=$config{server}{CGIpath}; domain=$config{server}{domain}'\n",
			{type=>'text/javascript'});
    $out .= $ml->noscript($msg{"You must enable javascript to use this form."});
    return $out;
}

sub get_post_key {
    my ($this,$key) = @_;
    my @capkey;
    # mashup some user data
    push @capkey, &md5_hex($ENV{REMOTE_ADDR},$ENV{HTTP_USER_AGENT});
    # add our contextual key
    push @capkey, $key;
    # add the system time
    push @capkey, time;
    # add a random number for extra entropy
    push @capkey, int(rand(10000))+1;
    # combine these into a single string and encrypt
    my $crypt = new ExSite::Crypt;
    return $crypt->encrypt(join(";",@capkey));
}

### WARNING: text captchas are English only

sub captcha_text {
    my ($this,$n) = @_;
    my ($challenge,$response);
    if (! $n) { $n = int(rand(4))+1; }
    if ($n == 1)    { ($challenge,$response) = $this->captcha_text1; }
    elsif ($n == 2) { ($challenge,$response) = $this->captcha_text2; }
    elsif ($n == 3) { ($challenge,$response) = $this->captcha_text3; }
    else            { ($challenge,$response) = $this->captcha_text4; }
    
    my $key_crypt = $this->encrypt($response);

    my $solution = $this->get("solution_field") || "captcha_solution";
    my $answer = $this->get("answer_field") || "captcha";
    
    return "<div class=\"captcha\">
<input type=\"hidden\" name=\"$solution\" value=\"$key_crypt\">
$challenge<br>
<input type=text name=\"$answer\" size=\"8\">
</div>\n";
}

# Text CAPTCHA 1: Enter selected letters of a specific word

sub captcha_text1 {
    my $this = shift;
    my ($challenge,$response);
    my (@cword, $iword, $ilength, $word, @letter, $nletter, $password, $npass);
  RESTART:
    @cword = $this->get_words($config{captcha}{word_set_size});
    while (! $word) {
	$iword = int(rand(scalar @cword));
	$word = $cword[$iword];
	$ilength = length $word;
    }

  REDO_PASS: @letter = (); $password = undef; $npass=0;
    foreach (1..$ilength) {
	if (rand(2.5) < 1) {
	    push @letter,$_-1;
	    $password .= substr($word,($_-1),1);
	}
	last if (@letter == $config{captcha}{max_password_size});
    }
    if (@letter < 2) {
	$npass ++;
	#print "*** $npass $word $password\n";
	goto RESTART if ($npass > 10);
	goto REDO_PASS;
    }
    $nletter = scalar @letter;

    $challenge = "Enter the ";
    foreach (1..$nletter) {
	$challenge .= $RANK[$letter[$_-1]];
	if ($_ == $nletter - 1) { $challenge .= " and "; }
	elsif ($_ != $nletter) { $challenge .= ", "; }
    }
    $challenge .= " letters of the ".
    ($iword == $#cword ? "last" : $RANK[$iword]).
    " word in the following list:<br>\n";
    $challenge .= join(" ",@cword)."\n";

    $response = $password;
    return ($challenge,$response);
}

# Text CAPTCHA 2: Solve an arithmetic problem

sub captcha_text2 {
    my $this = shift;
    my ($challenge,$response);
    my @op = ("+","-","&times;");
    my $n1 = int(rand(9))+1;
    my $n2 = int(rand(9))+1;
    my $op = $op[int(rand(scalar @op))];
    $challenge = "$n1 $op $n2 = ?";
    $response = eval("$n1$op$n2");
    return ($challenge,$response);
}

# Text CAPTCHA 3: Count the letters in a specific word

sub captcha_text3 {
    my $this = shift;
    my ($challenge,$response);
    my (@cword, $iword, $ilength, $word, @letter, $nletter, $password, $npass);

    @cword = $this->get_words($config{captcha}{word_set_size});
    $iword = int(rand(scalar @cword));
    $word = $cword[$iword];
    $ilength = length $word;

    $challenge = "How many letters are in the ".
	($iword == $#cword ? "last" : $RANK[$iword]).
	" word of the following list?<br>\n";
    $challenge .= join (" ",@cword);
    $response = $ilength;
    return ($challenge,$response);
}

# Text CAPTCHA 4: Which one of these is not like the other?

sub captcha_text4 {
    my $this = shift;
    my ($challenge,$response);
    my (@cword, $iword, $ilength, $word, @letter, $nletter, $password, $npass);

    my %category = (
		    animals => [qw(DOG CAT SHARK RABBIT SNAKE BEAR WHALE ELEPHANT CROCODILE SPIDER)],
		    colours => [qw(RED BLUE YELLOW GREEN PINK PURPLE BLACK WHITE BROWN)],
		    vehicles => [qw(CAR TRUCK BOAT TRAIN SHIP AIRPLANE ROCKET BICYCLE)],
		    names => [qw(BOB MARY JOHN BILL WENDY SUSAN PATRICK JOE MARTIN FRANK TAMMY)],
		    countries => [qw(CANADA FRANCE GERMANY CHINA JAPAN BRAZIL ITALY EGYPT NORWAY)],
		    food => [qw(BANANA CHEESE BREAD BEEF POTATO SALAD PASTA CAKE CORN APPLE)],
		    actions => [qw(RUN WALK SWIM JUMP DANCE SING LAUGH FIGHT)],
		    numbers => [qw(TWO THREE FOUR FIVE SIX SEVEN EIGHT NINE TEN ELEVEN TWELVE SIXTEEN TWENTY)],
		    planets => [qw(MERCURY VENUS EARTH MARS JUPITER SATURN URANUS NEPTUNE)],
		    geography => [qw(ISLAND RIVER MOUNTAIN LAKE VALLEY OCEAN BAY PENINSULA)],
		    );

    my @categories = keys %category;
    my ($c1,$c2);
    $c1 = $categories[int(rand(scalar @categories))];
    do { $c2 = $categories[int(rand(scalar @categories))]; } 
    until ($c1 ne $c2);
    
    my $rightword = $category{$c1}[int(rand(scalar @{$category{$c1}}))];
    my @wrongwords;
    while (@wrongwords < 4) {
	my $iword = int(rand(scalar @{$category{$c2}}));
	push @wrongwords, $category{$c2}[$iword];
	splice @{$category{$c2}},$iword,1;
    }
    my $rightpos = int(rand(scalar @wrongwords));
    splice @wrongwords,$rightpos,0,$rightword;
    
    $challenge = "Which one of these is not like the other?<br>\n".
	join(" ",@wrongwords);
    $response = $rightword;
    return ($challenge,$response);
}

sub get_words {
    my $this = shift;
    my ($nwords) = @_;
    my @word;
    open F,"<$config{captcha}{dictionary}";
    # Some dictionaries contain accented characters or words with
    # punctuation marks - strip all of these.
    @word = grep(/^[A-Za-z]+$/,<F>);
    close F;
    my $nword = scalar @word;
    my @cword = ();
    foreach (1..$nwords) {
	my $rand = int(rand($nword)) + 1;
	next if (length($word[$rand]) < 5);
	push @cword, $word[$rand];
    }
    chomp @cword;
    return @cword;
}

sub encrypt {
    my ($this,$key) = @_;
    my $t = tied %token;
    if ($config{token}{captcha} && $t->enabled) {
	# store the solution in the token table
	return $t->make($key,1,(3600*$config{captcha}{expire}));
    }
    else {
	# encrypt the solution right into the key
	if ($config{captcha}{expire}) {
	    $key .= ";".time;
	}
	my $c = new ExSite::Crypt;
	return $c->encrypt($key);
    }
}

sub decrypt {
    my ($this,$cipher) = @_;
    my $key;
    my $t = tied %token;
    if ($config{token}{captcha} && $t->enabled) {
	# solution is stored as a token
	$key = $token{$cipher};
    }
    else {
	# cipher is encrypted solution
	my $c = new ExSite::Crypt;
	my $plaintext = $c->decrypt($cipher);
	my ($timestamp,$now);
	if ($config{captcha}{expire}) {
	    ($key,$timestamp) = split /;/,$plaintext;
	    $now = time;
	    if (int(($now - $timestamp)/3600) >= $config{captcha}{expire}) {
		# captcha is expired; solution is no longer valid
		$key = undef;
	    }
	}
	else {
	    $key = $plaintext;
	}
    }
    return $key;
}

=pod

=head1 ExSite::Captcha

The captcha tool generates and processes "captchas" (Completely
Automated Public Turing test to tell Computers and Humans Apart).  The
following captcha modes are supported:

=over 4

=item * image

These use distorted images of text, requiring the user to transcribe the
text into plain-text form.  Some image captchas have been successfully
attacked programatically, but the ExSite captchas should still be sufficient
to filter out most nuisance bots.

=item * text

These use plain-text riddles, requiring the user to understand a question 
and provide a precise answer.  These captchas are relatively easy to defeat,
so we provide an extra degree of difficulty by randomly alternating between
several styles of question/answer, and relying in some cases on a dictionary
of tens of thousands of words as a source of challenge data.  Text captchas 
are useful as an accessible fallback for visually-impaired readers, or for 
browsers that do not support images.

=item * passive

Passive captchas require no interaction with the user.  They exploit
differences between typical bad robot and good user behaviours to
identify which posts are legitimate.  Basically, we give the user an
encrypted token that authorizes them to post the form; the token must
be returned with the form data or the form data will not be accepted.
Being encrypted, the token cannot be spoofed, and not being part of
the form data itself, naive automated posts will not include it.
However, it is not difficult to program a robot to request a token
first before posting, and then use that token to post, so this form of
captcha is not strong.  For smaller sites that do not attract
dedicated attacks, it is nevertheless highly effective at filtering
nuisance spam.  Large and popular sites may make it worthwhile for a
spammer to develop a targeted attack, in which case an image captcha
is a better option.

=back

=head1 Usage

Usage is best illustrated with some simple examples.

This CGI program generates and processes a simple form containing an
image captcha.  It will switch to a more accessible (but weaker) text
captcha on user request.

    #!/usr/bin/perl
    use strict;
    use ExSite::Config;
    use ExSite::Input;
    use ExSite::Captcha;
    
    &exsite_init;
    print "content-type: text/html\n\n";
    
    my $input = ExSite::Input->new()->combine();
    my $c = new ExSite::Captcha(mode=>$input->{captchamode});

    # use this instead to prevent switching to text captchas:
    # my $c = new ExSite::Captcha(no_text_captcha=>1);

    # evaluate the user's response
    if ($input->{captcha}) {
        if ($c->pass()) {
            print "<p>Thanks, that's the correct answer!</p>\n";
    	    exit;
        }
        else {
    	    print "<p>Sorry, that's not the correct answer.</p>\n";
        }
    }

    # output a new captcha
    my $captcha = $c->make();
    
    print <<END;
    <form method=POST>
    $captcha<br>
    <input type=submit>
    </form>
    END

This CGI program employs a passive captcha.  An automated form submission
must first acquire a posting key by visiting the form, and then must make 
the post using this key.

    #!/usr/bin/perl
    use strict;
    use ExSite::Config;
    use ExSite::Input;
    use ExSite::Captcha;
    
    &exsite_init;
    
    my $output;
    my $input = ExSite::Input->new()->combine();
    my $c = new ExSite::Captcha(mode=>"passive");
    
    # an arbitrary unique key for this captcha
    my $key = 123;
    
    # test the validity of the response
    if ($input->{data}) {
        # we have user input
        if ($c->pass($key)) {
            $output .= "<p>Thank you for your submission!</p>\n";
        }
        else {
            $output .= "<p>You appear to be a robot.  Your submission was not accepted.</p>\n";
        }
    }
    
    # output a new captcha
    my $captcha = $c->make($key);
    
    print "content-type:text/html\n\n";
    
    print <<END;
    $output
    <form method=POST>
    Data: <input type=text name=data><br>
    $captcha<br>
    <input type=submit>
    </form>
    END

These examples use the C<new()>, C<make()>, and C<pass()> methods,
explained below:

=head2 C<new()>

B<Usage:> C<my $captcha = new ExSite::Captcha(%opt);>

The C<new()> method accepts a number of optional parameters:

=over 4

=item mode

Set to one of "image", "text", or "passive" to get that style of
captcha.  You can set this to the value of the input parameter
"captchamode" to allow the user to switch captcha modes.  (This can
help the visually impaired switch from an image to a text captcha, at 
the cost of providing a weaker captcha.)

=item answer_field

The name of the form field containing the user's guess.
Defaults to "captcha".

=item solution_field

The name of the hidden form field containing the encrypted solution.
Defaults to "captcha_solution".

=item image_id

The ID of the SPAN element wrapping the captcha image.
Defaults to "captcha_image".

=item prompt

The text string prompting the user's input on image captchas.
Defaults to "Enter the text you see:".

=item no_text_captcha

Set this to a non-zero value to disable user-switching of the captcha
mode from image to text.

=back

=head2 C<make($key)>

B<Usage:> C<print $captcha-E<gt>make();>

C<make()> accepts an optional parameter C<$key>, the meaning of which
depends on the mode:

=over 4

=item image

the text string to encode in the image (max 5 chars)

=item text

the text captcha algorithm to use (1-4)

=item passive

an arbitrary value which can be used to associate this captcha with a
particular object.  For example, when replying to a post in a forum,
you can use the ID of the message being replied to as the captcha key.
This would prevent this captcha's post key from being reused on any
other message.

=back

=head2 C<pass()>

C<pass()> returns a true value if the agent has passed the captcha's
test for being a real user.  For interactive (image and text)
captchas, that means they entered a correct solution to the puzzle
they were given.  For passive captchas, that means they possessed a
valid posting key.

B<Usage:> C<if ($captcha->pass()) { ...>

This works in most cases for interactive captchas.  It will try to
find the user's guess and the encoded solution in the form data.

B<Usage:> C<if ($captcha->pass($guess,$encoded_solution)) { ...>

This variant passes the user's guess and the solution in explicitly.

B<Usage:> C<if ($captcha->pass($key)) { ...>

This variant is used with passive captchas; the key is the same key
you passed in C<make()>, above.

=head1 Expiring Captchas

Captchas have built-in time limits (by default, 24 hours).  To change
the number of hours a captcha is valid for, use a configuration
setting like:

    captcha.expire = 1     # 1 hour limit only

If you set the expire value to 0, then captchas will not expire and
will remain valid indefinitely.  However, this creates a loophole for
semi-automated attacks in whch a human solves the captcha once, and
then robots reuse that solution afterwards.  This attack is still
possible with time-limited captchas, but only for a brief time, making
it not worthwhile for most types of spam.

The timeout countdown begins from when the captcha is generated.
If the user waits too long to submit the form, the captcha may fail.

=head1 Requirements

The CGI program C<captcha.cgi> generates the captcha image in real-time.
It uses the C<convert> program (part of the ImageMagick suite) to write
the captcha text on top of a blank background (_ExSite/images/captcha.png).
By default the C<ps:Courier-Bold> font is used.  If not installed, another
font will need to be specified.

Text captchas use the system dictionary /usr/share/dict/words to pull
random word data out for some of the riddles.

Passive captchas require cookies to be enabled on the client browser.

Captchas published to static pages require javascript to be enabled on
the client browser.

=cut

1;

