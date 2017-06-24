#-----------------------------------------------------------------------
#
#   Copyright 2001-2004 Exware Solutions, Inc.  http://www.exware.com
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

package ExSite::Config;
use strict;
use myConfig;
use ExSite::Store;
use ExSite::Cookie;
use ExSite::Message;

#=====================================================================
# Exported names:

BEGIN {
    use Exporter;
    use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

    $VERSION = "4.0";

    @ISA = qw(Exporter);

    @EXPORT      = qw(%config %share %session %store %cookie %msg %token
		      &exsite_init &exsite_close 
		      &insert_js &insert_css
		      &get_obj &get_languages &preference
		      &diagnostic &OnError &AtError
		      );

    @EXPORT_OK   = qw(&read_exsite_conf 
		      &fetch_diagnostics &show_diagnostics 
		      &install_handlers);

}

use vars (@EXPORT, @EXPORT_OK);

#=====================================================================
# Non-Exported names:

use vars qw(
	    %server_config %site_config %auth_config 
	    %form_config %report_config %log_config
	    %crypt_config %prog_config %content_config
	    %search_config 
	    );

##################################################################
################ static configuration            #################
##################################################################

# static configuration parameters are valid for every site setup.
# They may still be overridden in particular scripts, by setting
# the given parameters to a new value.

#======================================================================
# SITE CONFIGURATION:
# parameters that define the website as a whole

%site_config = (

    # site name - used as a default title
    name => "ExSite",

    # site ID (no spaces) - used as a cookie prefix
    id => "ExSite",

    # identity cookie name
    identity_cookie => "ExSiteID",
    cookiepath => "/",

    # site logo - optional <IMG ...> tag for login.cgi
    logo => "",

    # sysadm's email, eg. "webmaster\@yourdomain.com"
    administrator => undef,

);

#======================================================================
# AUTHENTICATION CONFIGURATION
# parameters controlling, login, authorization, etc.

%auth_config = (

    # authentication type (fixed, none, cookie, crypt, session)
    type => "cookie",

    # define the password storage method: 
    # cleartext - no encryption
    # des - password hashed with system crypt() function
    # md5 - password hashed with Digest::MD5
    # md5+ - multi-pass password hash using Digest::MD5
    # crypt - password encrypted using ExSite::Crypt (reversible)
    password_storage_method => "cleartext",

    # password recovery method
    # reminder - password emailed to user (not all storage methods allow this)
    # reset - password is changed and then emailed to user
    # undef - use reminder if possible, and reset otherwise
    password_recover_method => undef,

    # enforce password strength on admin forms
    strong_passwords => 0,
    # base password strength
    base_pwd_strength => 5,

    # system salt - can improve crypto of some things with extra salt
    salt => undef,

    # authentication scope
    # if local, users can only log into their own section
    # if global, users can log in to any section
    scope => "local",

    # define the tables and columns where login and authentication
    # information can be found
    user_table => "user",
    group_table => "content",
    user_login_column => "login",
    user_pwd_column => "password",
    user_access_column => "access",
    user_uid_column => "uid",
    user_gid_column => "gid",
    user_sort_column => "name",
    user_name_column => "name",
    user_email_column => "email",

    # named access levels
    level => {
	root => 9,
	admin => 8,
	manager => 7,
	executive => 5, # >=5, actually
	visitor => 4,   # <=4, actually
	member => 2,
	user => 1,
	public => 0,
    },

    # what user level is permitted to link to records they don't own?
    foreign_link_level => 7,

    # login targets 
    # WARNING: reconfigure these if changing $config{prog}
    login_destination => [ "/",
			   "/",
			   "/",
			   "/",
			   "/",
			   "/",
			   "/",
			   "ex.cgi/admin",
			   "ex.cgi/admin",
			   "ex.cgi/admin",
			   ],

    # login form
    login_prompt => "Login",
    password_prompt => "Password",

    # include a "forgot login?" function?
    forgot_login => 1,
    forgot_prompt => "Forgot your login/password?",

    # include a "Remember Me" feature?
    remember_me => 1,
    remember_prompt => "Remember me on this computer",

    # how long do durable cookies last?
    long_cookie_duration => "2 weeks",

    # warn user on logout?  (leave off if you use IE6)
    logout_warning => 1,

    # logging (best if user.last_login and/or user.login_count are defined)
    log_login => 0,

    # clearing session
    logout_kills_session => 1,
    login_kills_session => 0,

################ FIXME
    # check http referer on database peeks (eg. view, peek)
    referer_check => 1,
    # ditto, but for logged-in-users (set to 0 to skip referer check for 
    # members - useful to exclude robots only from database peeks)
    member_referer_check => 1,
    # allow admins to bypass check
    owner_referer_check => 0,
    # min access level for file views
    file_access => 5,

    # password_access:
    # set to the access level that should be able to see password values
    # in reports and forms; note that password values are not necessarily 
    # the same as the actual password (eg. not with hashed passwords)
    password_access => 9,

    # TRUSTED CONNECTIONS
    # Do not trust connections by users of [trust_level] or higher
    # unless they are coming from an IP that matches pattern in 
    # [trusted_hosts]. Untrusted connections are downgraded to one 
    # less than the trust level. Note that trust is tested when entering 
    # admin screens (eg. home.cgi, ctrl-panel.cgi), but not necessarily
    # when accessing normal pages. (Thus authkeys should continue to 
    # work from any location when using normal pages.)
    trust_level => 9,
    trusted_hosts => '^192\.168\.',

    # View keys
    # keys normally grant admin privileges to content; view keys simply grant
    # permission to view content. A view key is just a content_key with no
    # role defined. Enable that feature here:
    view_keys => 0,

    # email templates for password recovery
    email => {
	nouser => "Sorry, there is no user named [[login]].",	 
	twousers => "ERROR: there is more than one user named [[login]].",	 
	pleasecall => "Please contact the site administrator at [[admin]] for assistance.",	 
	missingemail => "Sorry, there is no email address recorded for the user [[login]].",	 
	email_subject => "Login instructions for [[site_title]]",	 
	email_body => "Here are login instructions for [[user]] for the website [[site_title]]:\n",	 
	email_instructions => "Login: [[login]]\nPassword: [[password]]",	 
	noaccess => "You have an old account, but its access has been disabled. To renable this account, contact your site administrator, at [[admin]].",
	reset_body => "A password reset was requested for [[user]] on the website [[site_title]].\n\nIf you did not make this request, you can ignore this email and your password will not be affected.\n\nTo reset your password, click on the link provided or paste the complete URL into your browser.",	 
	reset_instructions => "Reset password for user [[user]]:\n[[reset_url]]",	 
	reset_sent => "Your password has been reset, and the new password has been emailed to [[email]].  You should change this password after logging in.",	 
	email_error => "We found an account, but your login information (username, password, or access level) is incomplete.  Please contact your site administrator for assistance, at [[admin]]",	 
	notmyemail => "Instructions have been emailed to [[email]]. If this is not your current e-mail address, then please contact the site administrator at [[admin]] for assistance.",	 
    },
);

#======================================================================
# FORM CONFIGURATION
# parameters controlling form layout

%form_config = (

    # input field separator character
    sepchar => '#',

    # multiple-input separator character
    multi_sep => '; ',

    # maximum input field width
    max_cols => 60,
    # maximum rows in a textarea input
    max_rows => 10,

    # stack set checkboxes with more than this number of values
    stack_checkboxes => 4,           # more than this # of checkboxes
    stack_maxchar_per_button => 20,  # individual label longer than this
    stack_maxchar_total => 40,       # total labels longer than this

    # form mode:
    # "cgi" to have forms processed by CGI programs (eg. doform.cgi)
    # "exsite" to have forms processed by WebDB DCD
    mode => "cgi",

    # include a key (encrypted timestamp) to assist in abuse detection
    key => 0,

    #---------------------------------
    # dates & times
    #---------------------------------

    # default date settings for undefined dates: "today" or "null"
    default_date => "today",

    # if using a date picker, the earliest pickable date
    date_picker_start_date => "2000-01-01",

    # date input format, "simple", "picker", or "select"
    date_input_format => "select",

    # date selectors ("select" or "text")
    day => "text",
    year => "text",

    # year range in year selectors (+/- this value)
    year_range => 10,
    #year_uprange => 5,
    #year_downrange => 50,

    # hour selectors can be based on a 12 or 24 hour clock
    clocktype => 12,

    # minute step size in minute selectors
    minstep => 15,

    # validation range for years (year values must be within this number
    # of years from the present)
    validate_year_range => 100,

    # can timestamp fields be edited?
    editable_timestamps => 0,

    # AM/PM labels
    am => "AM",
    pm => "PM",

    #---------------------------------
    # foreign key inputs
    #---------------------------------

    # display of foreign key selectors
    # set to 1 to include foreign key id in selector
    # set to 0 to use only general description of foreign record
    show_foreign_key_id => 1,

    # maximum number of foreign keys in a select tag before switching
    # to a regular text input.  Set to 0 for no maximum.
    max_foreign_key_select => 500,

    #---------------------------------
    # data handling options
    #---------------------------------

    # trim leading/trailing whitespace from form data before 
    # inserting/updating?

    trim_whitespace => 0,

    # tinymce settings

    editor => "tinymce",

	tinymce => {
		# Tinymce path
		path=>"/_ExSite/tiny_mce",
		file=>"tinymce.min.js",
		# Dialog settings
		dialog=>{
			# Access level requirement
			access=>5,
			dlgimg=>{
				script=>"/Image",
				allow_file_upload=>1,
				# Popup window dimension
				popup=>{
					full=>{width=>520,height=>450},
					basic=>{width=>520,height=>350},
				},
			},
			dlglink=>{
				script=>"/Link",
				# Popup window dimension
				popup=>{
					full=>{width=>480,height=>300},
					basic=>{width=>480,height=>180},
				},
			},
			dlgdyn=>{
				script=>"/DynContent",
			},
		},
		# Editor modes
		mode=>{
			# Current mode
			current=>"standard",
			default=>"standard",
			# Define tool groups to show in the tool bar
			toolbar=>{
				basic=>{
					toolbar_row1=>["undo","textstyle","list","link","image","mailto"],
					toolbar_row2=>[],
					toolbar_row3=>[],
					toolbar_row4=>[],
					menubar=>0,
					menu=>[]
				},
				standard=>{
					toolbar_row1=>["undo","textstyle","list","link","image","mailto"],
					toolbar_row2=>[],
					toolbar_row3=>[],
					toolbar_row4=>[],
					menubar=>"edit insert format view table list",
					menu=>{
						edit=>{
							title=>"Edit",
							items=>"undo redo | cut copy paste pastetext | selectall | searchreplace | code"
						},
						format=>{
							title=>"Formats",
							items=>"e_header e_block e_inline e_align | e_indent e_outdent | e_fontselect e_fontsizeselect | e_forecolor e_backcolor | e_special | removeformat"
						},
						insert=>{
							title=>"Insert",
							items=>"e_dlgimg e_dlglink e_dlgdyn media | e_dlglink_unlink | charmap hr anchor pagebreak insertdatetime nonbreaking"
						},
						table=>{
							title=>"Table",
							items=>"inserttable tableprops deltetable | cell row column"
						},
						list=>{
							title=>"List",
							items=>"e_numlist e_bullist"
						}
					},
				},
			},
		},
		# Tool groups
		group=>{
			textstyle=>"bold,italic",
			alignment=>"alignleft,aligncenter,alignright,alignjustify",
			clipboard=>"pasteword",
			table=>"tablecontrols",
			list=>"bullist,numlist",
			format=>"block_format,inline_format",
			indent=>"outdent,indent",
			undo=>"undo,redo",
			link=>"e_dlglink,e_dlglink_unlink,anchor",
			html=>"removeformat,code,snippet",
			font=>"fontselect,fontsizeselect",
			color=>"forecolor,backcolor",
			exsite=>"e_dlgdyn",
			special=>"hr,charmap,nonbreaking",
			layer=>"insertlayer,moveforward,movebackward,absolute",
			attribute=>"styleprops",
			direction=>"ltr,rtl",
			datetime=>"insertdate,inserttime", 
			image=>"e_dlgimg", 
			expert=>"advhr,attribs,media,cleanup,pastetext",
			header=>"header_format",
			mailto=>"e_dlgmailto"
		},
		# Tinymce settings
		editor=>{
			width=>"700",
			height=>"512",
			theme=>"modern",
			plugins=>"autolink,lists,charmap,hr,anchor,pagebreak,visualblocks,visualchars,code,media,nonbreaking,table,directionality,emoticons,paste,textcolor,dlglink,format,searchreplace",
			element_format=>"html",
			convert_fonts_to_spans=>1,
			fontsize_formats=>"8pt 10pt 12pt 14pt 18pt 24pt 36pt",
			font_formats=>"Serif=serif;Sans-serif=sans-serif;Monospace=monospace",
			entity_encoding=>"raw",
			force_p_newlines=>0,
			forced_root_block=>"p",
			extended_valid_elements=>"iframe[src|width|height|name|align|frameborder]",
			convert_urls=>0	,
			exsite_style_formats=>"Warning=warn;Help=help;Error=error"
		},
    },


    # file upload limits (in btyes)
    # "file" type is capped by field size (64K, which is reasonable)
    # "bigfile" type allows up to 16MB, which is probably unreasonable
    # for web uploads.  Furthermore DB engines like MySQL limit query
    # sizes so that you can't actually insert large files into a SQL
    # record (MySQL limit is typically 1 MB).  Set the actual bigfile 
    # size limit here:

    bigfile_maxsize => 1048576,  # 1 MB

    # Add extra span tags around form labels and inputs for CSS purposes.
    # If this is disabled, css classes are applied directly to label and
    # input tags.

    css_span => 1,

);

#======================================================================
# REPORT CONFIGURATION
# parameters controlling report formatting

%report_config = (

    # currency character
    currency_char => '$',

    # maximum number of records to report at a time
    page_length => 20,

    # use compact css if this number of columns or more
    compact_columns => 10,

    # for table reports, this flag determines whether each row is classified 
    # as A or B for the purposes of highlighting alternate lines.  Note that 
    # turning this flag on does not by itself highlight lines;  you must also 
    # setup your stylesheet to recognize the A/B classes of <TR>.  This 
    # setting will override $reportrecordtag->{table}->[0].
    highlight_alternate_lines => 0,

    # report link mode:
    # "cgi" to have db_ops linked to CGI programs (eg. webdb.cgi)
    # "exsite" to have db_ops linked back to the page (ie. to WebDB DCD)
    linkmode => "cgi",
### FIXME

    # foreign key linking permissions
    # when reporting foreign keys, cross-link to the foreign record if the
    # viewer has this permission on the foreign record
    link_to_foreign_key_perm => "read",

    # if primary display columns of a table include foreign keys, this 
    # setting will expand those foreign keys to readable form when 
    # building record labels
    show_foreign_keys_in_record_labels => 0,
### IS THIS USED???

    # if there is more than one primary display column for a table, but only
    # one is requested, this setting selects either the first or last
    use_first_key => 0,

    # email format:
    # "plain" displays the email using a regular mailto: URI
    # "obfuscated" uses javascript to obfuscate the address from spambots
    email => "plain",

    # dynamic reports - use jquery plugin for more interactive reports
    dynamic => 0,
    # default page length (0 for default)
    dynamic_page_length => 0,

    # sorting
    case_insensitive_sort => 0,

    # display this when not permitted to view a value
    permission_denied => "(no permission to view this data)",

    #---------------------------------
    # reporting of text data
    #---------------------------------

    text => {
	
	# allow HTML tags found in normal text

	honor_html => 0,

	# if HTML is allowed, allow only non-structural tags, to prevent
	# layouts from being damaged (ie.no tables or divs)

	safe_html => 1,

	# treat newlines as meaningful in normal text

	honor_nl => 0,

    },

    # date/time reporting

    date => {
	date => "date",
	time => "time",
	datetime => "datetime2",
	timestamp => "datetime2",
    },

);

#======================================================================
# SERVER CONFIGURATION
# this stuff varies between sites, so the following defaults are
# mostly just placeholders for configuration data to follow.
# The auto flag determines whether autoconfiguration is done by
# default.  Set it to 1 in exsite.conf if you want autoconfiguration.

%server_config = (
    db => { 
	name=>"exsite", 
	server=>"localhost", 
	user=>"exsite", 
	type=>"sql", 
	charset=>"",  # set to UTF-8 if your DB uses UTF-8 encoding
	map=>"map" 
	},
    map => { name=>"dbmap", type=>"text" },
    HTMLroot => "/var/www/html",
    HTMLpath => "",
    CGIroot => "/var/www/cgi-bin",
    CGIpath => "/cgi-bin",
    fileroot => "/var/www/files",
    protocol => "http",
    host => "localhost",
    domain => "localdomain",
    port => "",
    server => "http://localhost.localdomain",
    rootserver => undef,
    temppath => "/tmp",
    imgdir => "/images",
    securepath => "/usr/local/bin:/bin:/usr/bin:/usr/X11R6/bin",
    auto => 0,
);

#======================================================================
# LOG CONFIGURATION
# parameters controlling event logging

%log_config = (

    # Each parameter refers to the logging level for a particular log file.
    # Log levels go from 0 (no logging) to 3 (log everything).
    # Log files must exist and be writable by the webserver.

    # db - database log file
    # 1: log database errors
    # 2: log database modifications
    # 3: log database connections & selects
	       
    db => 0,

    # cms - content management system audit trail
    # 1: log publicly-visible changes
    # 2: log all website, page, and content updates
    # 3: log all cms operations

    cms => 0,

    # general - general ExSite diagnostics
    # 1: log errors
    # 2: log warnings
    # 3: log info messages

    general => 0,

    # audit - things that change system state
    # log levels are ignored on audit, any non-zero value enables it

    audit => 0,
    
    # cron
    # log levels are ignored on cron, any non-zero value enables it

    cron => 0,

    # the log files themselves... (paths are relative to cgi directory)

    logfile => {
	db => "db.log",
	cms => "cms.log",
	general => "general.log",
	audit => "audit.log",
	cron => "cron.log",
	post => "post.log",	
    },

);

#======================================================================
# CRYPTO CONFIGURATION 

%crypt_config = (

    # CRYPTOGRAPHY:
    # ExSite can automatically encrypt and decrypt data going to and from
    # the database, if the column has "crypt" datatype.  Crypt fields are
    # treated same as text fields, but the data is encrypted according
    # to the following options:

    # encryption mode can be:
    # "strong" - best security, good for storing critical data
    # "fast" - trades security for speed; 2-3 times faster than strong
    #          mode; good for obfuscating data communicated over http, 
    #          but not for secure storage.

    default_mode => "strong",

    # keys for coding/decoding
    # It is good practice to define different keys for fast and strong
    # encryption.  Otherwise the regular key will be used.

    key_fast => "fast dummy pass-phrase",
    key_strong => "strong dummy pass-phrase",
    key => "dummy pass-phrase",

    # number of mixing rounds (higher is better)

    nround_fast => 4,
    nround_strong => 32,

    # decryption rules:
    # admin => only administrator can view plaintext
    # owner => owner of record can view plaintext

    access => "admin",

);

##======================================================================
# PROGRAM CONFIGURATION 

%prog_config = (
    admin            => "ex.cgi/admin",
    app              => "ex.cgi/app",
    captcha          => "ex.cgi/captcha",
    ctrlpanel        => "ex.cgi/admin",
    dcd              => "ex.cgi/dcd",
    debug            => "ex.cgi/debug",
    dialog           => "ex.cgi/dialog",
    dispatch         => "ex.cgi/dispatch",
    doform           => "ex.cgi/doform",
    echo             => "ex.cgi/echo",
    file             => "ex.cgi/file",
    getdata          => "ex.cgi/peek",
    help             => "ex.cgi/help",
    home             => "ex.cgi/admin",
    login            => "ex.cgi/login",
    logout           => "ex.cgi/logout",
    page             => "ex.cgi/page",
    getdata          => "ex.cgi/peek",
    peek             => "ex.cgi/peek",
    post             => "ex.cgi/post",
    publish          => "publish.cgi",
    test             => "ex.cgi/test",
    viewcontent      => "ex.cgi/view",
    view             => "ex.cgi/view",
    ex               => "ex.cgi",
);

#======================================================================
# SEARCH CONFIGURATION 

%search_config = (

    # scope = local (search current section only) or global (search all)

    scope => "local",

    # do not index the words in the following file

    stopwords => "stopwords.txt",

    # should we index numbers?

    index_numbers => 1,

    # when indexing numbers, ignore those below a certain value;
    # this ignores all 1- and 2-digit numbers

    min_number => 100,

    # default maximum number of results to report

    maxresult => 25,

    # threshold (minimum weight) of indexed terms

    threshold => 1,

    # automatically reindex pages and sites when they are published

    reindex_on_publish => 0,

    # no results message

    no_results => "Nothing relevant was found.",

    # do we index archived pages?

    index_archived => 0,

    # disable searching certain types

    skip => {
        content => 1,
        comment => 1,
        alias => 1,
        library => 1,
        template => 1,
    } 

);

#======================================================================
# CONTENT CONFIGURATION 

%content_config = (

    # VIEWS
    # viewsize - sort views by relative size

    viewsize => { 
        large => 5, 
        normal => 4, 
        small => 3, 
        thumbnail => 2, 
        icon => 1 
    },

    # viewdim - optimal dimensions (eg. for images) of each view
    viewdim => { 
        large => 1024, 
        normal => 512, 
        small => 256, 
        thumbnail => 100, 
        icon => 16, 
    },

    # viewprefix - used for making filenames
    viewprefix => { 
        large => "lg_", 
        normal => "", 
        small => "sm_", 
        thumbnail => "th_", 
        icon => "icon_" 
    },

    # altview - view preferences, if requested view not available
    altview => {
        large => ["large","normal","small","thumbnail","icon"],
        normal => ["normal","small","large","thumbnail","icon"],
        small => ["small","normal","thumbnail","icon","large"],
        thumbnail => ["thumbnail","icon","small","normal","large"],
        icon => ["icon","thumbnail","small","normal","large"],
    },

    # allowed metadata
    
    metadata => {
        '_' => { }, # generic metadata
        '_DC' => {  # Dublin Core metadata
            'DC.Title' => { datatype => "text" },
            'DC.Creator' => { datatype => "text" },
            'DC.Subject' => { datatype => "text" },
            'DC.Description' => { datatype => "text" },
            'DC.Publisher' => { datatype => "text" },
            'DC.Contributor' => { datatype => "text" },
            'DC.Date' => { datatype => "text" },
            'DC.Type' => { datatype => "text" },
            'DC.Format' => { datatype => "text" },
            'DC.Identifier' => { datatype => "text" },
            'DC.Source' => { datatype => "text" },
            'DC.Language' => { datatype => "text" },
            'DC.Relation' => { datatype => "text" },
            'DC.Coverage' => { datatype => "text" },
            'DC.Rights' => { datatype => "text" },
        },
        # special metadata
        content => {
            caption => { datatype => "text", size => 60 },
        },
        section => {
            description => { datatype => "text", size => 200 },
            keywords => { datatype => "string" },
        },
        page => {
            description => { datatype => "text", size => 200  },
            keywords => { datatype => "string" },
        },
        blog => {
            author => { datatype => "string" },
        },
        article => {
            author => { datatype => "string" },
            abstract => { datatype => "text", size => 400  },
            footnote => { datatype => "text", size => 200  },
            #canonical => { datatype => "string" },
        },
        comment => {
            author => { datatype => "string" },
        },
        product => {
            #description => { datatype => "text", size => 300 },
            part_number => { datatype => "string" },
            shipping_size => { datatype => "decimal" },
            acctcode => { datatype => "int" },
        },
        catalog => {
            shopping_cart => { datatype => "list:shopping_cart" },
        },
        location => {
            longitude => { datatype => "decimal" },
            latitude => { datatype => "decimal" },
        },
        form => {
            notify => { datatype => "string", size=>60, label => "Email responses to" },
        },
        question => {
            format => { datatype => "list:form_input_format" },
            datatype => { datatype => "list:form_input_datatype" },
            preset => { datatype => "string" },
            placeholder => { datatype => "string" },
            size => { datatype => "int", size=>8 },
            maxlen => { datatype => "int", size=>8 },
            min => { datatype => "int", size=>8 },
            max => { datatype => "int", size=>8 },
            step => { datatype => "int", size=>8 },
            options => { datatype => "text", size=>200 },
        },
        fee => {
            maximum_registrations => { datatype => "int", size=>8, },
            hide_from_fees => { datatype => "string" },
        },
        album => {
            viewer => { datatype => "list:album_viewer" },
            delay => { datatype => "decimal", size=>10, label=>"Transition delay (s)" },
            duration => { datatype => "decimal", size=>10, label=>"Transition duration (s)" },
        },
        profile => {
            organization => { datatype => "string" },
            title => { datatype => "string" },
            honorific => { datatype => "list:honorific" },
            subscribe => { datatype => "list:yn", label=>"Consent to receive emails?" },
        },
    },

    # contextual metadata - inherit metadata definitions from parent objects
    # eg. two catalogs could define different metadata rules for their products

    contextual_metadata => 0,

    # flags
    
    flags => {
        '_' => { }, # generic flags
        # special metadata
        #event => [ "notify_admin" ],
        article => [ "sticky" ],
        #comment => [ "sticky" ],
        fee => [ "enable waitlist when sold out",
                 "create address cards for guests",
                 "instant registration if possible",
                 "time exclusive",
                 "includes complimentary registrations",
                 "no guests",
                 "allow multiple" ],
        form => [ "captcha", 
                  "robot counter-measures", 
                  "prepopulate with user data",
                  "confirmation screen" ],
        question => [ "required", "checked", "stack" ],
        album => [ "titles","captions", "controls" ],
    },

#    tree_columns => "content_id,parent,template,master,type,name,language,status,ctime,hide,access",
    tree_columns => "content_id,parent,template,master,type,name,language,status,ctime,hide,access,url,publish,ptime",
    #tree_columns => "content_id,parent,template,master,type,name,language,status",
    tree_order => "coalesce(sortkey,''),content_id",  # ordering of tree nodes
    inline_css => 0,                         # place CSS in <style> block
    preformatted_plaintext => 1,             # place plaintext in <pre> blk
    img_title => undef,                      # image title can be name,
                                             #   description, or undef
    keywords_from_tags => 0,                 # generate keyword list from tags
    ajax_method => "dispatch",               # dispatch or regular

    # FORMATS - different templates for displaying content
    # naming convention:
    # {type} - used by show()
    # {type}_summary - used by summary(), index()
    # {type1}_{type2}_summary - used by summary(), index() for type2s in type1s

    format => {
        link => "<a class='contentLink [[type]]Link' href='[[url]]>[[title]]</a>",
        content => "<div class='content [[type]]'><h1 id='[[type]][[id]]' class='contentTitle [[type]]Title'>[[title]]</h1>\n[[html]]\n[[tools]]\n[[index]]</div>\n",
        summary => "<div class='contentSummary [[type]]Summary'><a class='contentLink' href='[[url]]'>[[title]]</a>\n<div class='contentDescription [[type]]Description'>[[description]]</div>\n</div>\n",
        thumb => "<div class='[[type]]Thumb'><a class='[[type]]Link' href='javascript:popup_image(\"[[url]]\")'><div class='[[type]]Thumbnail'>[[html_thumbnail]]</div><div class='[[type]]Caption'>[[title]]</div>\n</a>\n</div>\n",
        listing => "<div class='[[type]]Listing'>[[icon]]<a class='contentLink [[type]]Link' href='[[url]]'>[[title]]</a> <span class='fileInfo'>[[info]]<span></div>\n",
# full-size photo on top of the article
#        article => "<div class='articlePath'>[[navpath]]</div>\n<div class='article'><h1 id='article[[id]]' class='articleTitle'>[[title]]</h1>\n<div class='articleAbout'>[[info]]</div>\n[[_IMG:html]]<div class='articleBody'>[[html]]</div>\n[[tags]][[tools]]</div>\n",
# small photo float right, popup to full-size photo (requires bootstrap.js)
        article => "<div class='articlePath'>[[navpath]]</div>\n<div class='article clearfix'><h1 id='article[[id]]' class='articleTitle'>[[title]]</h1>\n<div class='articleAbout'>[[info]]</div>\n[[image]]<div class='articleBody'>[[html]]</div>\n[[tags]][[tools]]</div>\n",
        article_summary => "<div class='article'><h2 id='article[[id]]' class='articleTitle'>[[title]]</h2>\n<div class='articleAbout'>[[info]]</div>\n[[_IMG:html]]<div class='articleBody'>[[html]]</div>\n[[tools]]</div>\n",
        article_comment => "<div class='comment'><a name='Comment[[id]]'></a><div class='commentAbout'><div class='commentAuthor'>From: <span class='commentAuthor'>[[author]]</span></div>\n<div class='commentDate'>Posted on: <span class='commentDate'>[[date]]</span></div></div>\n<div class='commentBody'>[[html]]</div>\n[[?attachments]]<div class='commentAttachments'>[[attachments]]</div>\n[[/?attachments]][[tools]]</div>\n",
        article_link => "<p><a href='[[url]]'>[[title]]</a>[[?date]], posted on [[date]][[/?date]][[?author]], by [[author]][[/?author]]</p>\n",
        article_archive_link => "<p class='articleLink'><a href='[[purl]]'>[[title]]</a> <span class='articleAbout'>[[?date]]Posted on [[date]][[/?date]][[?author]], by [[author]][[/?author]]</span>",
        product => "<div class='Product'>[[navpath]]<h1>[[title]]</h1>[[image]]<div class='productDescription'>[[html]]</div>[[?price]]<div class='productPrice'>[[price]]</div>[[/?price]]<div class='productTools'>[[tools]]</div>[[secondary_gallery]]</div>",
        product_summary => "<div class='Product'><a href='[[url]]'><h2>[[title]]</h2></a><div class='productThumb'>[[_IMG:html_thumbnail]]</div><div class='productDescription'>[[description]]</div>[[?price]]<div class='productPrice'>[[price]]</div>[[/?price]]</div>",
        event => "<div class='Event'>[[navpath]]<h1>[[title]]</h1>\n[[event_date]]\n[[image]]<div class='eventDescription'>[[html]]</div>\n[[tools]]\n[[index]]\n</div>",
        library => "<div class='Library'><h1>[[title]]</h1>[[html]][[index]]</div>",
    },

    # subtype options

    blog => {
        format => "article_index",
        index_age => 90,
        max_index => 10,
        min_index => 3,
        sort => "id",
        stickiness => "temporary", # or permanent (which is slower)
    },
    index => {
        sort => "label",
#        heading => "Items tagged with <em>[[keyword]]</em>",
    },
    keyword => {
#        sort => "label",
        heading => "Items tagged with <em>[[keyword]]</em>",
    },
    comment => {
        moderate => 1, # sends a moderation/notification message to admin
        status => 4, # initial status of posts (submitted)
        allow_cms_tags => 0,
        allow_cms_links => 0,
        #remove_quote_char => 0,
        emoticons => 1,
	emoticon_re => ['>:-?\)', '(:-?\)|\(-?:)', '(:-?\(|\)-?:)', 
			':-?D', ':-?[Oo]', ';-?[\)D]', ':-?P ' ],
        emoticon_img => {
	      '(:-?\)|\(-?:)' => "emoticon_smile.png",
	      '(:-?\(|\)-?:)' => "emoticon_unhappy.png",
	      ':-?D' => "emoticon_grin.png",
	      ':-?[Oo]' => "emoticon_surprised.png",
	      ';-?[\)D]' => "emoticon_wink.png",
	      ':-?P ' => "emoticon_tongue.png",
	      '>:-?\)' => "emoticon_evilgrin.png",
	},

    },
);

#======================================================================
# GENERAL CONFIGURATION 

%config = (

    #---------------------------------
    # HTML output options:
    #---------------------------------

    # doctype of system screens - default to HTML 5
    # If you use XHTML, be sure to set the markup rules (below) to enable XML syntax.

    doctype => '<!DOCTYPE html>',

    # The character set used for admin screens and the editor.  UTF-8 allows
    # for native representation of most languages; ISO-8859-1 is a common
    # alternative, but is only good for Western European Languages.

    charset => "UTF-8",

    # webtop help link

    help_url => "http://support.exsitewebware.com",

    # webtop icon set (blank for default/classic)

    iconset => '',

    # standard jquery library

    jquery=>"http://ajax.googleapis.com/ajax/libs/jquery/3.2.1/jquery.min.js",
    jqueryui=>"http://ajax.googleapis.com/ajax/libs/jqueryui/1.12.1/jquery-ui.min.js",

    # The default language

    default_language => "English",

    # highlight any missing message translations

    highlight_missing_sysmsg => 1,

    # Default thumbnail size (max edge length in pixels)

    thumbnail_size => 100,

    # Maximum image size (max edge length in pixels)

    max_image_size => 1600,

    # DATABASE OPTIONS
    # handling of database images
    # set true if ExSite::Report::show_data should display images inline
    # set false if ExSite::Report::show_data should display a link to the image

    show_images => 1,

    # maximum upload file size
    # NB: form.bigfile_maxsize limits the size of a file that can be loaded
    # into a bigfile DB record.  This parameter, on the other hand, limits 
    # the size of a file that can be uploaded through a web form for other
    # reasons (eg. publish straight to disk).

    max_upload_size => 16000000,

    # maximum tree size (in nodes)
    # This is mostly to prevent node loops in trees.

    max_tree_size => 10000,

    # space character conversion for URLs

    spacechar => "_",

    # mail notifications
    # method can be "sendmail" or "Net::SMTP" (preferred)
    # sendmailpath only used for "sendmail" method
    # bcc can be used to send copies of all notifications to an archive PO box
    # set bulklevel and bulkserver to route mail through alternate servers
    # if the volumn of messages is high

    mail => {
	method => "Net::SMTP",
        sendmailpath => "/usr/lib/sendmail",
	bcc => undef,
	server => "localhost",
	bulkserver => "localhost",
	bulklevel => 2,  # max number of messages to send thru regular server
        dummy_html_part => 0,  # create an HTML part for plain text emails sent in multipart mode
    },

    # section handling by CMS

    section => {
        standalone_subdir_404 => 0,       # standalone subdirs give 404
    },

    # page handling by CMS

    page => {
	suffix => '\.(html?|php|asp)',    # allowed filename suffixes
	dynamic_method => "path",         # id, path
        dyn_publish_method => "none",     # none, redirect, template
	editmode => "MySite",             # editable page prev. handler
	static_urls => 0,                 # always use static urls?
	static_url_type => "full",        # full, relative
	dynamic_url_type => "relative",   # full, relative
        default_to_index => 1,            # go to index if dyn path not found
        no_index_filename => 0,           # don't specify index.html in urls
    },

    # captchas

    captcha => {
	mode => "image",                         # default captcha type

	# image captchas
	font => "ps:Courier-Bold",               # font to use
	pointsize => 30,                   	 # size of text
	color => "#333366",                      # color of text
	distort => ".25",                        # distortion factor
	start_x => 5,                            # start position of text
	start_y => 30,                           # "
	charsize => 19,                          # character width

	# passive captchas
	passive_method => "postkey,honeypot",    # passive captcha methods
	postkey_cookie => "postkey",             # name of postkey cookie
	honeypot_name => "comment",              # honeypot field
	max_postkey => 3,

	# text captchas...
	dictionary => "/usr/share/dict/words",   # source of words
	word_set_size => 5,                      # number of words in a challenge
	max_password_size => 2,                  # number of characters required in a response

	# time-sensitive
	expire => 24,                            # set to >0 to prevent re-use
	                                         # after that many hours
    },

    # content filters

    wordfilter => {
	mode => "off",                           # off, auto, custom
	method => "reject",                      # reject, censor, semi-censor
	file => "badwords.txt",                  # file in conf
	censor_string => "[censored]",           # used for action=censor
	censor_char => "*",                      # used for action=semi-censor
	threshold => 1,                          # read level to act on
	override => 3,                           # access level to ignore
    },

    # handling of database operations
    # each operation has the following parameters:
    #   approve: the low-level operation that needs to be approved by DB::approve
    #   url: the script that executes the operation
    #   img: the image for the operator icon
    #   img_width, img_height: the dimensions of the image
    #   label: the text string to use if the image is not present
    #   table: 1 means operation can be performed on whole tables
    #          (otherwise, op is restricted to individual records)
    # Each url is passed ?tab=<table>[&id=<record>]
    #
    # WARNING: reconfigure these if changing $config{prog}

    db_ops => {
	edit => { approve=>"update", url=>"?action=edit", 
		  img=>"edit12.gif", level=>3,
		  img_width=>12, img_height=>13, label=>"edit", table=>0 },
	copy => { approve=>"insert", url=>"?action=copy", 
		  img=>"copy12.gif", level=>3,
		  img_width=>12, img_height=>13, label=>"copy", table=>0 },
	delete => { approve=>"delete", url=>"?action=delete", 
		  img=>"rm12.gif", level=>3,
	          img_width=>12, img_height=>13, label=>"delete", table=>0 },
	new => { approve=>"insert", url=>"?action=new", 
		  img=>"new12.gif", level=>3,
		  img_width=>12, img_height=>13, label=>"add new", table=>1 },
	view => { approve=>"read", url=>"?action=view", 
		  img=>"view12.gif", level=>1,
		  img_width=>12, img_height=>13, label=>"view details", table=>0 },
	list => { approve=>"read", url=>"?action=list", 
		  img=>"list12.gif", level=>1,
		  img_width=>12, img_height=>13, label=>"list", table=>1 },
	report => { approve=>"read", url=>"?action=report", 
		  img=>"list12.gif", level=>3,
		  img_width=>12, img_height=>13, label=>"list", table=>1 },
	searchquery => { approve=>"read", url=>"?action=query", 
		  img=>"search12.gif", level=>1,
		  img_width=>12, img_height=>13, label=>"search", table=>1 },
    },

    db_ops_grps => {
	#all => [ "list", "view", "search", "edit", "copy", "new", "delete" ],
	all => [ "list", "view", "searchquery", "edit", "copy", "new", "delete" ],
	all_edit => ["edit", "copy", "delete"],
	all_view => ["list", "view", "search"],
	link => ["view"],  # kludge to support old "link" args
    },

    # preferred order for displaying db operators, when more than one is shown
    # ops not in this list will not be displayed at all.

    #db_ops_order => [ "list", "view", "search", "edit", "copy", "new", "delete" ],
    db_ops_order => [ "list", "view", "searchquery", "edit", "copy", "new", "delete" ],

    icon => {
        generic => "page.png",
        image => "image.png",
    },

    # include the other configuration hashes here

    site => \%site_config,
    auth => \%auth_config,
    form => \%form_config,
    report => \%report_config,
    log => \%log_config,
    crypt => \%crypt_config,
    prog => \%prog_config,
    search => \%search_config,
    content => \%content_config,
    server => \%server_config,  # conditional

    # CACHE

    cache => {
	max_size => 1000000,    # only cache items under 1 MB
	persistent => 1,        # try to save cache beyond the current request
#	querytype => {
#	    get_columns => 1,
#	    get_key => 1,
#	    count => 1,
#	    fetch => 1,
#	    fetch_match => 1,
#	    fetch_all => 1,
#	    fetch_child => 1,
#	    fetch_m2m => 1,
#	    select => 1,
#	},
    },

    # SESSIONS

    session => {
	max_idle => 3600,       # purge sessions after this much idle time
        secure => 0,            # enable anti-hijacking features
    },

    # markup rules

    markup => {
	xml => 0,               # use XML syntax
	minattr => 1,           # minimize attributes, if possible
	safe_content => 1,      # assume contents are HTML-safe
	safe_attributes => 1,   # assume attributes are HTML-safe
	nl => 1,                # append a NL char to end of element
    },

    # CRON

    cron => {
	day => 0,               # which day to run weekly tasks
	hour => 0,              # which hour to run daily tasks
    },

    # TOKENS

    token => {
	type => "store",        # store or db
	captcha => 0,           # use for captchas
	short_url => 1,         # use for short URLs,
	authtoken => 0,         # use for authtokens
	secure_query => 0,      # use for secure query strings
	secure_query_duration => 2592000, # 30 days
    },

    # Timezones

    timezone => {
        auto => 0,             # autoconf server timezone to detect DST
        server => "-0800",      # default server timezone
        home => undef,          # offset of website owner from server timezone
    },

    #---------------------------------
    # kill switches
    #---------------------------------

    # kill - prevents page.cgi from generating pages
    # killurl - redirect killed page.cgi requests to this URL

    kill => 0,
    killurl => undef,

    # busy - prevents page.cgi from generating pages if load is too high
    # busyurl - when busy, redirect requests to this URL
    # busyload - the 1-minute load average threshold that triggers redirects
    # NOTE: we check /proc/loadavg for the load value; this feature only
    # works on systems that have this file.

    busy => 0,
    busyurl => undef,
    busyload => 10,

    # throttle - delay requests if rate is excessive
    # rate - rate (req/s) at which to throttle requests (0 to disable)
    # threshold - interval (s) at which recent requests are considered potentially abusive
    # min - minimum number of abusive requests to trigger throttle
    # url - redirect to this URL when being throttled
    # history - number of recent requests to track
    #
    # WARNING: if you set the rate to less than 0.1, the 10 s automatic
    # refresh of the default throttle page will keep them in perpetual 
    # refresh hell.  0.2 req/s is okay for users, 2 req/s is okay for sites.
    throttle => {
	user => {
	    rate => 0,
	    threshold => 10,
	    min => 4,
	    url => undef,
	    history => 10,
	},
	system => {
	    rate => 0,
	    threshold => 2,
	    min => 10,
	    url => undef,
	    history => 20,
	},
    },

    # webtop
    webtop => {
        # access level required to reach webtop
        access => 5,
        # restrict non-sysadmins to a whitelist of allowed modules
        whitelist => undef,
        # should we add a section selector to the webtop?
        # set to Y to add an unset selector, or to a section ID to add a 
        # preset selector
        section_selector => 0,
        # where to send users who are denied webtop access 
        # (menu, login_destination)
        deny => "login_destination",
        # popup style:
        # popup - opens control panels in simple popup window
        # tab - opens control panels in a new tab (actually a new window, but
        #       some browsers are configured to open new windows in tabs)
        popup_style => "popup",
        # categories
        categories => [ "Overview", "CMS", "Applications", "Events", "Social", "Ecommerce", "System", "Database" ],
        headings => {
            CMS => "Content Management",
            Ecommerce => "E-commerce",
            Events => "Event Management",
            Social => "Social &amp; Communications",
        }, 
        # NOTE: the "Ecommerce" category is also supported, but not enabled
        # by default
        # allow manual renaming of modules, eg.
        # webtop.module_name.Foo = Bar
        # If a module is renamed to undef/nothing, it should not be shown.
        module_name => { BaseDCD=>undef },
        # colors may be used for grouping/color-coding of apps
        color => {
            CMS => "#8acfcf",
            Applications => "#c3cf8a",
            Overview => "#7d5b54",
            System => undef,
            Database => undef,
            Ecommerce => "#cebc4e", 
            Events => "#659696",
            Social => "#cf8aa1",
        }, 
    },

);

#### end of static configuration


##################################################################
################ setup and configuration routines ################
##################################################################

sub server_autoconf {
    $config{server}{HTMLroot} = $ENV{DOCUMENT_ROOT};
    $ENV{SCRIPT_NAME} =~ m:^.*/([^/]+)$:;
    my $script_name = $1;
    $ENV{SCRIPT_FILENAME} =~ /^(.*)\/$script_name$/;
    $config{server}{CGIroot} = $1;
    my $script_re = join('|',values %{$config{prog}},'[\w-]+\.cgi');
    $config{server}{CGIpath} = ($ENV{SCRIPT_NAME} =~ /^(.*)\/($script_re)$/)? $1 : "";
    $config{server}{protocol} = exists $ENV{HTTPS} ? "https" : "http";
    $config{server}{HTMLpath} = $config{server}{CGIpath};
    ### FIXME: support other cgi paths
    $config{server}{HTMLpath} =~ s/\/cgi(-bin)?\//\//;
    $config{server}{HTMLpath} =~ s/\/cgi(-bin)?$/\//;
    if ($config{server}{HTMLpath} eq "/") {
	$config{server}{HTMLpath} = "";
    }
    if (! $config{server}{fileroot}) {
	$config{server}{fileroot} = $config{server}{CGIroot};
	$config{server}{fileroot} =~ s/\/cgi(-bin)?$/\/files/;
    }
    $ENV{HTTP_HOST} =~ /^((.+?)\.)?(.*?\..*?)(:\d+)?$/;
    $config{server}{host} = $2;
    $config{server}{domain} = $3;
    $config{server}{port} = $4;
}

sub read_exsite_conf {
    my ($file,$key) = @_;
    if (! $file) { $file = "exsite.conf"; }
    if ($key && ! exists $config{$key}) { $config{$key} = {}; }
    my @confpath = ("./conf", "ExSite", ".");
    foreach my $dir (@confpath) {
	if (-e "$dir/$file") {
	    if (open CONF,"<$dir/$file") {
		foreach (<CONF>) {
		    next if (/^\#/);
		    next if (/^\s*$/);
		    chomp;
		    my ($param,$value,$append);
		    if (/\+=/) { 
			($param,$value) = split /\s*\+=\s*/,$_,2;
			$append = 1;
		    }
		    else {
			($param,$value) = split /\s*=\s*/,$_,2;
			$append = 0;
		    }
		    $value =~ s/\\n/\n/g;
		    my @param = split /\./,$param;
		    # -. prefix will set global conf when there is a key
		    # NB: this is NOT cached by the store
#		    my $conf = ($key && $param[0] ne "-") ? $config{$key} : \%config;
		    my $conf = $key ? $config{$key} : \%config;
		    foreach my $par (@param[0..$#param-1]) {
			if (! exists $conf->{$par}) {
			    $conf->{$par} = {};
			}
			# this will crash if not a hash ref
			$conf = $conf->{$par};
		    }
		    if ($append) {
			# append parameter to list
			if (! exists $conf->{$param[-1]}) {
			    $conf->{$param[-1]} = [$value];
			}
			else {
			    if (ref $conf->{$param[-1]} ne "ARRAY") {
				my $tmplist = [ $conf->{$param[-1]} ];
				$conf->{$param[-1]} = $tmplist;
			    }
			    push @{$conf->{$param[-1]}},$value;
			}
		    }
		    else {
			# simple parameter
			$conf->{$param[-1]} = $value;
		    }
		}
		close CONF;
	    }
	}
    }
}

# Preferences
#
# Preferences are localized configuration settings - specific to a
# certain context (eg. for a section, or a user).  They are stored in 
# the attributes table.
#
# If no preference is found, the system configuration setting is used.
#
# confname is a configuration setting, eg. "foo.bar"
# @context is a list of table/record ID pairs, eg. page 10, section 1.
# If no context is given, we assume the current section (based on the
# page we are looking at).  We search for an attribute named $confname, 
# attached to any of the table/record pairs in the context.

sub preference {
    my ($confname,@context) = @_;
    # confname = group.subgroup.name
    my @confname = split /\./,$confname;
    if (@context == 0) {
	# default context is current section
	my $this_section = $share{DB}->this_site();
	if ($this_section) {
	    @context = ( "content", $this_section->{content_id} );
	}
    }
    while (@context) {
	my $context_type = shift @context;
	my $context_id = shift @context;
	if ($context_type && defined $context_id) {
	    if (! $share{config}{$context_type}{$context_id}) {
		# fixme: check the store
		# fixme: would it be better to simply cache all attributes
		# instead of just the ones for this context?
		my @attr = $share{DB}->fetch_match("attribute",
						   {tablename=>$context_type,
						    id=>$context_id});
		foreach my $attr (@attr) {
		    $share{config}{$context_type}{$context_id}{$attr->{name}} = $attr->{value};
		}
		# fixme: recache in the store
	    }
	    if (exists $share{config}{$context_type}{$context_id}{$confname}) {
		return $share{config}{$context_type}{$context_id}{$confname};
	    }
	}
    }
    # return system setting
    my $conf = \%config;
    while (my $name = shift @confname) {
	return undef if (ref $conf ne "HASH");
	$conf = $conf->{$name};
    }
    return $conf;
}

############################################################
################ initialization and shutown ################
############################################################

sub exsite_init {

    # reset share hash
    %share = (
	      diagnostics => [],
	      ENV => {},
	      );

    # debug reconfigs
    if ($ENV{EXSITE_DEBUG}) { 
	if ($ENV{SCRIPT_NAME} =~ /publish\.pl/) {
	    # when debugging, we run publish.pl directly
	    $config{prog}{publish} =~ s/publish\.cgi/publish\.pl/; 
	}
    }

    # set up the data store
    &exsite_init_store;

    # load configurations
    &exsite_init_config;

    # fill cookie jar
    &exsite_init_cookie;

    # load translations
    &exsite_init_msg;

    # initalize session
    &exsite_init_session;

    # setup tokens - optional feature for now
    if (eval 'require ExSite::Token') {
	tie %token, 'ExSite::Token';
    }

    # save our original environment state in case we need to tamper with it
    $share{ENV}{SCRIPT_NAME} = $ENV{SCRIPT_NAME};
    $share{ENV}{QUERY_STRING} = $ENV{QUERY_STRING};
    $share{ENV}{PATH_INFO} = $ENV{PATH_INFO};
    $share{ENV}{REQUEST_METHOD} = $ENV{REQUEST_METHOD};

    # timezone config
    if ($config{timezone}{auto}) {
	if (! $store{timezone}) {
	    my $tz = `date +%z`;
	    chomp $tz;
	    $tz =~ /^([\-\+]\d+)$/;
	    $store{timezone} = $1;
	}
	$config{timezone}{server} = $store{timezone};
    }

    # localized initialization
    &my_exsite_init(\%config,\%share,\%session,\%store,\%cookie,\%msg,@_);

    # untaint our publication directories
    {
	$config{server}{HTMLroot} =~ /^((\/[\w\.-]+)+)$/;
	$config{server}{HTMLroot} = $1;
    }
    {
	$config{server}{HTMLpath} =~ /^((\/[\w\.-]+)*)$/;
	$config{server}{HTMLpath} = $1;
    }
    {
	$config{page}{suffix} =~ /^(.+)$/;
	$config{page}{suffix} = $1;
    }
    # untaint our secure path
    {
	$config{server}{securepath} =~ /^(((\.|(\/\w+)+):)+(\/\w+)+)$/;
	$config{server}{securepath} = $1;
	#$ENV{PATH} = $config{server}{securepath};
    }
}

sub exsite_init_store {
    # set up the data store
    my ($store_conf,$st);
    eval { 
	$store_conf = &Local::store_conf() 
	    or die 'no store configuration';
    };
    if (! $@ && ref $store_conf eq "HASH") {
	# looks like we have a data store; try connecting to it
	$st = tied %store;  # might still be tied in a persistent perl setup
	if (! $st) { 
	    # not tied, so re-tie it
	    $st = tie %store, 'ExSite::Store', $store_conf;
	}
    }
    else {
	# persistent store not enabled
	# Note that %store contents may persist in some environments 
	# (eg. Persistent Perl);  however we cannot rely on these contents
	# because it is local to the process, not the server (ie. if another
	# process changes the store contents, those changes are not reflected
	# here.)  Therefore we must clear the store on each request.
	%store = ();
    }
}

sub exsite_init_config {
    if (! $config{_loaded}) {
	# %config not preloaded - must reload from scratch

	# load any extra configuration from conf files
	&read_exsite_conf();

	# store configuration persistently
	$config{_loaded} = 1;
	my $st = tied %store;
	if ($st) { $st->put("config:",\%config,0); }
    }

    # run autoconfiguration, in case of flexible URLs/domains
    if ($config{server}{auto}) {
	&server_autoconf;
    }

    # build the server address from the various config params
    if ($config{server}{host}) {
	$config{server}{server} = "$config{server}{protocol}://$config{server}{host}.$config{server}{domain}$config{server}{port}";
    }
    else {
	$config{server}{server} = "$config{server}{protocol}://$config{server}{domain}$config{server}{port}";
    }

    # patch up our db_ops urls, in case we've rewritten our script names
    foreach my $op (keys %{$config{db_ops}}) {
	$config{db_ops}{$op}{url} = $config{prog}{webdb}.$config{db_ops}{$op}{url};
    }
}

sub exsite_init_cookie {
    # set up the cookie hash now that we have some server info
    if (! $config{site}{cookiepath}) {
	# default to send cookies only to CGI programs
	# set site.cookiepath to "/" if you need cookies on your
	# static pages, or you are doing URL rewrites
	$config{site}{cookiepath} = $config{server}{CGIpath};
    }
    my $domain = $config{server}{host} ? 
	".$config{server}{domain}" : 
	$config{server}{domain}; 
    tie %cookie, 'ExSite::Cookie',
        $config{site}{cookiepath},
        $domain,
        $config{auth}{long_cookie_duration};
}

sub exsite_init_msg {
    # setup system messages
    tie %msg, 'ExSite::Message', $config{default_language}, $config{highlight_missing_sysmsg}, \%share, \%store;
}

sub exsite_init_session {
    my $st = tied %store;
    if ($st) {
	# session management is automatically enabled if there is 
	# a persistent data store
	require ExSite::Session;
	tie %session, 'ExSite::Session';
    }
}

sub exsite_close {
    # localized clean-up;
    &my_exsite_close(@_);

    # flush the session
    if (tied %session) { untie %session; }

    # flush the cache
    if ((ref $share{Cache}) =~ /Cache/) { $share{Cache}->flush; }

    # shut down the store
    if (tied %store) { untie %store; }

    # close primary database
    if ($share{DB}) { $share{DB}->close(); }

    # wait for any child processes to wrap up
    do {} until (wait == -1);
}

# %share contains shareable data for the current page request; when generating 
# multiple pages in succession, we will want to reset it. However, some items 
# should be kept for the sake of efficiency.

sub reset_share {
    foreach my $item (keys %share) {
	# keep items whose state does not change
	next if ($item =~ /^(DB|Cache|content|config|ENV|identity|diagnostics|publish|querylib|Cache_revision|Cache_metadata)$/);
	next if ($item =~ /^dbmap:/);
	delete $share{$item}
    }
}

# insert_js: add JS, if not already added
# $js can be a script, a path to a JS file, or a JS name from _ExSite/js

sub insert_js {
    my $out;
    while (my $js = shift) {
	my $name = lc $js;
	$name =~ s/\.js$//;
	my $ml = &get_obj("ML");
	if (! $share{js}{$name}) {
	    # not yet added to page
	    $share{js}{$name} = 1;
	    if ($name =~ /\/?[\w\-\.]+$/) {
		# jquery shortcuts
		if ($name eq "jquery") {
		    $out .= $ml->script(undef,{src=>$config{jquery}});
		}
		elsif ($name eq "jqueryui") {
		    $out .= $ml->script(undef,{src=>$config{jqueryui}});
		}
		# bootstrap shortcuts
		elsif ($name eq "bootstrap") {
		    $out .= $ml->script(undef,{type=>'text/javascript',src=>"$config{server}{HTMLpath}/_ExSite/js/bootstrap.min.js"});
		}
		elsif ($name eq "tooltip") {
		    $out .= $ml->script('
$(function () {
  $(\'[data-toggle="tooltip"]\').tooltip()
})
',{type=>"text/javascript"});
		}
		elsif ($name eq "popover") {
		    $out .= $ml->script('
$(function () {
  $(\'[data-toggle="popover"]\').popover()
})
',{type=>"text/javascript"});
		}
		elsif ($name eq "dropdown") {
		    $out .= $ml->script('
$(function () {
  $(\'.dropdown-toggle\').dropdown()
})
',{type=>"text/javascript"});
		}
		# other files
		elsif ($js =~ /\//) {
		    # file includes path
		    $out .= $ml->script(undef,{src=>$js});
		}
		else {
		    if ($js !~ /\.js$/) { $js .= ".js"; }
		    $out .= $ml->script(undef,{src=>"$config{server}{HTMLpath}/_ExSite/js/$js"});
		}
	    }
	    else {
		$out .= $ml->script($js);
	    }
	}
    }
    return $out;
}

# insert_css: add stylesheet, if not already added
# $css can be CSS code, a path to a CSS file, or a CSS name from _ExSite/css

sub insert_css {
    my $out;
    while (my $css = shift) {
	my $name = lc $css;
	$name =~ s/\.css$//;
	my $ml = &get_obj("ML");
	if (! $share{css}{$name}) {
	    # not yet added to page
	    $share{css}{$name} = 1;
	    if ($name =~ /\/?[\w\-\.]+$/) {
		# looks like a filename
		if ($css =~ /\//) {
		    # file includes path
		    $out .= $ml->link(undef,{rel=>"stylesheet",type=>"text/css",href=>$css});
		}
		else {
		    if ($css !~ /\.css$/) { $css .= ".css"; }
		    $out .= $ml->link(undef,{rel=>"stylesheet",type=>"text/css",href=>"$config{server}{HTMLpath}/_ExSite/css/$css"});
		}
	    }
	    else {
		$out .= $ml->style($css);
	    }
	}
    }
    return $out;
}

##################################################################
################ object management                ################
##################################################################

sub get_obj {
    my ($type,$id) = @_;

    if ($id) {

	# instantiate an object of this type and ID

	my $obj;
	if ($share{DB}) {
	    if (! $share{DB}{map}->is_mapped($type)) {
		# unknown table/type, load submaps in hopes that it is part of an
		# optional plugin module that hasn't been loaded yet
		$share{DB}{map}->load_submaps();
	    }
	    my $class = $share{DB}{map}->get_table_attr($type,"class");
	    if ($class) {
		if ($class eq "ExSite::Content") {
		    # subtype is unknown; let Content class figure it out
		    my $c = new ExSite::Content();
		    return $c->get_content_obj($id);
		}
		else {
		    # object has a specialized class
		    $class =~ /^((ExSite|Modules)::.*)$/;
		    my $safe_class = $1;
		    if (eval "require $safe_class") {
			$obj = eval "new $safe_class(id=>$id)";
			return $obj if ($obj);
			&diagnostic("$class: $@");
		    }
		    else {
			&diagnostic("$class: $@");
		    }
		}
	    }
	}
	if (! $obj) {
	    # setup as a generic object
	    return new ExSite::Object(type=>$type,id=>$id);
	}
    }
    else {

	# no id - looking for a predefinded object in $share

	if ($share{$type}) {
	    if ((ref $share{$type}) =~ /$type/) {
		return $share{$type};
	    }
	    # error: no such object, and the %share spot is occupied
	    return undef;
	}
    
	# no object found in %share;  look for class in ExSite
	if (eval "require ExSite::$type") {
	    my $o = eval "new ExSite::$type";
	    if ($o) {
		$share{$type} = $o;
		return $o;
	    }
	}

	# hm, nothing in ExSite;  look for class in Modules
	if (eval "require Modules::$type") {
	    my $o = eval "new Modules::$type";
	    if ($o) {
		$share{$type} = $o;
		return $o;
	    }
	}
    }
    
    # nothing found
    return undef;
}

##################################################################
################ language management              ################
##################################################################

sub get_languages {
    my $all = shift;  # includes default version, if true;
    my @version;
    if ($all) {
	push @version, $config{default_language};
    }
    if ($share{DB}) {
	push @version, split /\|/, $share{DB}{map}->regexp("list:language");
    }
    return @version;
}

##################################################################
################ diagnostics                      ################
##################################################################

sub diagnostic {
    my @log;
    while (@_) {
	my $message = pop;
	my $msg;
	if (ref $message) {
	    $msg = $message;
	}
	else {
	    $msg = {
		message => $message,
		type => "general",
		level => 3,
	    };
	}
	$msg->{type}  or $msg->{type} = "general";
	$msg->{level} or $msg->{level} = 3;
	my $severity = 
	    $msg->{level} == 1 ? "info" : 
	    $msg->{level} == 2 ? "warning" :
	    "error";
	# logging
	if ($msg->{level} >= 4 - $config{log}{$msg->{type}}) {
	    # log in %share and to disk
	    push @{$share{diagnostics}}, $msg;
	    push @log, $msg;
	}
	elsif ($msg->{level} >= 3) {
	    # always log level 3 diagnostics for internal error trapping
	    push @{$share{diagnostics}}, $msg;
	}
    }
    # log to disk

    while (@log) {
	my $msg = pop @log;
	my $type = $msg->{type};
	my $logfile = $config{log}{logfile}{$type} || "exsite.log";
	&log($msg->{message},$logfile);
    }
}

sub log {
    my ($msg,$logfile) = @_;
    $logfile or $logfile = "exsite.log";
    if (-w $logfile) {
	$logfile =~ /^([-\w]+\.log)$/;
	my $secure_logfile = $1;
	if ($secure_logfile) {
	    if (open LOG, ">>$secure_logfile") {
		my ($time,$user,$op);
		$time = localtime;
		# don't use my_name(), as it will cause an infinite loop
		$user = exists $share{identity} ? $share{identity}{name} : "nobody";
		if (! $user) { $user = "unknown"; }
		$op = $ENV{REQUEST_URI};
		print LOG "$time\t$user\t$op\t$msg\n";
		close LOG;
		### FIXME: maintain an open logfile connection for better perf
	    }
	}
    }
}

# tell us if errors have occurred
# (can optionally specify a level and type)

sub OnError {
    my ($level,$type) = @_;
    $level or $level = 3;
    foreach my $msg (@{$share{diagnostics}}) {
	if ($type) {
	    return 1 if ($msg->{type} eq $type && $msg->{level} >= $level);
	}
	else {
	    return 1 if ($msg->{level} >= $level);
	}
    }
    return 0;
}

# Get the current diagnostic count
# $lastcount = returns the difference from the lastcount
# $level = counts only diagnostics of this level or higher
#
# To get the total error count from the start of the request:
# my $errcnt = &AtError();
#
# To test if any errors have appeared since the last check:
# if (&AtError($errcnt)) { # new errors occurred }

sub AtError {
    my ($lastcount,$level) = @_;
    $level or $level = 3;
    $lastcount or $lastcount = 0;
    if ($lastcount < 0) { $lastcount = 0; } # backwards-compat kludge
    my $count = 0;
    foreach my $msg (@{$share{diagnostics}}) {
	$count++ if ($msg->{level} >= $level);
    }
    return $count - $lastcount;
}

# warning: meaning of $type is not the same as ExSite::Base::fetch_diagnostics
sub fetch_diagnostics {
    my ($level,$type) = @_;
    my @message;
    $level or $level = 3;
    foreach my $msg (@{$share{diagnostics}}) {
	next if ($type && $type ne $msg->{type});
	next if ($level && $level > $msg->{level});
	push @message, $msg->{message};
    }
    return @message;
}

sub show_diagnostics {
    my ($format,$level,$type) = @_;
    my @diag = &fetch_diagnostics($level,$type);
    if (@diag > 0) {
	$format or $format = "HTML";
	if ($format =~ /HTML/i) {
	    my $ml = &get_obj("ML");
	    my $out;
	    foreach my $d (@diag) {
		$out .= $ml->div(join($ml->br, split(/\n/,$d)),{class=>"error"});
	    }
	    return $out ? $ml->div($out,{class=>"errors"}) : $out;
	}
	else {
	    return join("\n",@diag);
	}
    }
    return undef;
}

##################################################################
################ handlers                         ################
##################################################################

sub install_handlers {
    my $this = shift;
    my $db = $share{DB};
    if ($this == $db) {
	# standard CMS handlers here
	$db->handler("setup_querylib",\&CMS_setup_querylib);
	$db->handler("select_foreign_key",\&CMS_select_foreign_key);
    }
    # additional handlers unique to this installation 
    &my_handlers($this,@_);
}

# handler for foreign key selection on CMS tables

sub CMS_select_foreign_key {
    my ($this, $table, $rec, $col, $ftable) = @_;
    # ignore, if not using the CMS database
    if ($this->{db}{name} eq $config{server}{db}{name}) {
	if ($col eq "section_id") {
	    return $share{DB}->my_sites();
	}
	elsif ($table eq "content" && $this->{action} !~ /search/) {
	    my $c = new ExSite::Content(id=>$rec);
	    if (! exists $share{content}{subtype}) {
		$c->get_subtypes();
	    }
	    if ($col eq "template") {
		# select only from active templates
		return $this->fetch_match("content",{type=>$c->isubtype("template"),status=>0});
	    }
	    if ($col eq "parent") {
		# suggest only active content from the current section 
		# of appropriate types for this content to nest under
		my $t = $c->get_content_tree();
		my $s = $c->my_section();
		my @allow = map { $_->{content_type_id} } $this->get_query("allowed types to post under",$c->subtype());
		my @parent;
		foreach my $allowed_type (@allow) {
		    if ($allowed_type eq $c->isubtype("section")) {
			push @parent, $s->get();
		    }
		    else {
			push @parent, $t->find({type=>$allowed_type,status=>0},$c->my_section->id);
		    }
		}
		# no labels in data :(
		foreach my $p (@parent) { $p->{label} = $p->{name}; }
		return \@parent;
	    }
	}
    }
    return undef;
}

# The querylib is a library of SQL custom queries;  we prepopulate this with
# some useful queries used by the base CMS system.

sub CMS_setup_querylib {
    my $this = shift;
    # ignore, if not using the CMS database
    if ($this->{db}{name} eq $config{server}{db}{name}) {
	my $db = $share{DB};
	# all content data to build a navigation tree
#	$db->set_query("content tree",
#		       sql=>"select $config{content}{tree_columns} from content order by $config{content}{tree_order}",
#		       nparam=>0,
#		       keys=>"content");
	# keyword indexes
#	$db->set_query("names of keyword tags",
#		       sql=>"select kw.name from content ind,content kw,content tag where kw.parent=ind.content_id and tag.parent=kw.content_id and ind.type=? and kw.type=? and tag.type=? and tag.master=?",
#		       nparam=>4,
#		       keys=>"content");
	# allowed content types under a node
#	$db->set_query("allowed content types",
#		       sql=>"select t.content_type_id,t.name from content_type t,content_type u,content_rel r where u.content_type_id=r.under and t.content_type_id=r.type and u.name=?",
#		       nparam=>1,
#		       keys=>["content_type","content_rel"]);
	# authorities (executive users) over content
	$db->set_query("all authorities",
		       sql=>"select distinct user.* from user,content_key where content_key.uid=user.uid and user.access>4",
		       nparam=>0,
		       keys=>["user","content_key"]);
	# all groups that a user belongs to
	$db->set_query("user groups",
		       sql=>"select g.* from usergroup g,groupkey gkey where gkey.gid=g.gid and gkey.uid=?",
		       nparam=>1,
		       keys=>["usergroup","groupkey"]);
	# all users in a group
	$db->set_query("users in group",
		       sql=>"select u.* from user u,groupkey gkey where gkey.gid=? and gkey.uid=u.uid",
		       nparam=>1,
		       keys=>["user","groupkey"]);
	# all sites
	$share{DB}->set_query("all sites",
			      sql=>"select c.* from content c,content_type t where c.type=t.content_type_id and t.name='section'",
			      nparam=>0,
			      mode=>"r",
			      keys=>["content","content_type"]);
	# my sites
	$share{DB}->set_query("my sites",
			      sql=>"select c.* from content c,content_key k,content_type t where c.content_id=k.content_id and c.type=t.content_type_id and t.name='section' and k.type='grant' and k.uid=?",
			      nparam=>1,
			      mode=>"r",
			      keys=>["content","content_key","content_type"]);
	# all revisions
#	$share{DB}->set_query("all revisions",
#			      sql=>"select revision_id,content_id,mime_type,ptime from revision order by revision_id",
#			      nparam=>0,
#			      mode=>"r",
#			      keys=>["revision"]);
	# all revisions
#	$share{DB}->set_query("content with no revisions",
#			      sql=>"select content.content_id from content left join revision on revision.content_id=content.content_id where revision.revision_id is null",
#			      nparam=>0,
#			      mode=>"r",
#			      keys=>["content","revision"]);
#	$share{DB}->set_query("popular content",
#			      sql=>"select content_id,sum(value) popularity from content_like group by content_id order by popularity desc",
#			      nparam=>0,
#			      mode=>"r",
#			      keys=>["content_like"]);

    }
}

1;

=pod

=head1 ExSite::Config - ExSite configuration and initialization

C<Config.pm> contains general configuration parameters,
site-specific setup data, and global variables used throughout
the ExSite system.

This file is designed so that it never has to be modified.  To set
configuration variables, use an "exsite.conf" file, which will be
loaded automatically, overriding the presets below.  This file can be
placed in C<cgi-bin/>, or C<cgi-bin/conf/>.  Special configuration 
routines and functions can be defined in the module C<myConfig.pm>.

=head2 Usage:

C<use ExSite::Config;>

This is required in all ExSite programs.  In addition, every program
should also include the following first line of executable code:

C<&exsite_init;>

=head2 Configuration Management

The system defines six global configuration hashes, described below.
These are exported to all programs that use C<ExSite::Config>.

=over 4

=item C<%config>

C<%config> is used for system constants that do not normally change.

The system constants in C<%config> are read first from the hard-coded
values in Config.pm, and then from the local configuration file 
"exsite.conf", which can override the former values.  
Modifications to the site configuration should be made 
in exsite.conf, not in Config.pm.

Specific configuration parameters are described in the ExSite
Configuration documentation, or in Config.pm.

Any module or other package can read its own configuration file(s)
into C<%config>, by calling: C<read_exsite_conf($file,$key)>. The
configurations will be read from C<$file>, and prefixed with the
namespace C<$key>.

In a plain CGI setup, C<%config> is re-read on each request, so
configuration changes are picked up immediately.  In a setup with
any sort of persistence (eg. persistent data store, persistent perl)
C<%config> will remain defined from the previous request, and
you will need to clear or restart your store or persistent perl to 
refresh C<%config>. See C<%store>, below, for more info.

=item C<%share>

C<%share> is used as a general-purpose shared-memory area for the current
request.  C<%share> is cleared on each page request.

The C<%share> hash is used for sharing data between widely separated
modules and routines.  The primary difference between C<%config> and
C<%share> is that the former is regarded as constant (values stay
the same from request to request), while the latter is volatile
(values vary from request to request).

The differences are not especially significant for normal CGI setups,
since C<%config> must be reloaded on each request anyway.  But in a
persistent perl or persistent data store configuration, C<%config> may
only be configured once, whereas C<%share> will be cleared and rebuilt
on every request.  (If you do not follow this convention, you may have
problems when switching to use persistence.)

C<%share> is cleared every time C<&exsite_init()> is called.
C<%share> will be used to store pointers to the current database and
page objects (C<$share{DB}> and C<$share{Page}>, respectively), plus
any other shareable data placed there by localization routines and
content modules.

=item C<%session> 

C<%session> stores semi-persistent data for a particular user.  That
is, it remembers data between different page requests, but clears the
data after a certain amount of time has passed with no activity.  The
C<%session> hash only holds data for the current user; other sessions'
data are not available.  This is a useful mechanism for temporarily
preserving a visitor's state.  Sessions last for 1 hour by default,
but are automatically renewed if used.  In other words, if no activity
is detected under a session for one hour, the session will be
terminated.

Session management is automatically enabled if you are using the
persistent data store (C<%store>).  Actual session records are created
only if data is written to C<%session>, however.  That is, there is no
persistent record of a session if nothing is ever written into
C<%session>.  The number of session records indicates the number of
users who have session data that is being tracked, not necessarily the
total number of users active on the site.

C<%session> will will automatically be populated with data previously
written to that user's session.  (See C<ExSite::Session> for technical
details.)  These data include C<_mtime> and C<_ctime>, which are
timestamp values (Unix system times) of the last modification of the
session data, and the creation time of the session.

B<Warnings:>
If persistent storage is not enabled, sessions are not especially
useful, as they will not remember data between requests.  However,
there is no harm in reading or writing to C<%session> in this case, and
it will behave as a normal hash variable.

(You can also use C<%cookie> to store semi-persistent data.
C<%session> is more secure, powerful, and reliable if enabled, since
the data is stored on the server, and can store complex structures.
Note that when a session is initiated, the session ID is stored in
C<%cookie>, so both are in fact needed to make proper use of
sessions.)

=item C<%cookie> 

C<%cookie> is used for session-like variables that are tracked
client-side rather than server-side.  As the name implies, these
variables are stored as cookies in the user's browser.  The C<%cookie>
hash automatically acquires all of the relevant cookies, and can be
inspected to view the values of those cookies at any time.

Changing/setting cookie values is also easy; simply assign a new
value to a cookie name, eg.

    $cookie{name} = $value;

The appropriate HTTP headers will be printed to ensure that the new
cookie data is sent to the client browser for storage.

B<Warnings:>
Because cookies are stored as simple text strings on the client browser,
cookie values should also be simple text strings.  Do not store 
references or objects in cookies.

Because browsers can disregard cookies, and cookies can be manually
deleted or edited at any time, there is no guarantee that cookies will
in fact persist, nor that they will not be tampered with.  They are
also transmitted in cleartext, so are vulnerable to snooping.  That
means that C<%cookie> is a useful convenience, but not a secure place
for storing data.  Sensitive data should be encrypted before being
placed into a cookie.  For example:

=over 4

=item ExSite identity cookie

In "cookie" mode, it stores DES-encrypted password to validate the user 
identity.  In "crypt" mode, it stores TEA-encrypted username and access
level.

=item ExSite session ID

The session ID is a 16-character random text string. This
makes active session IDs hard to guess, and fairly secure from a
keyspace attack.  However, it is not very secure from a spoofing
attack if an active session ID is sniffed from unencrypted network 
traffic ('session hijacking').

=back

=item C<%store>

The persistent data store is a place to store globally persistent
dynamic data.  While C<%config> stores parameters that do not change,
C<%store> stores data that is regularly modified but needs to be
available to future requests.  C<%store> is the underlying mechanism
behind sessions, database caches, and configuration caches.

The persistent data store is optional; by default it is not enabled,
and C<%store> is just a normal hash whose values are cleared on each
request.  (Which means that sessions and caches do not store data
beyond the current request.)  If the persistent store is enabled (see
the docs for C<ExSite::Store>) you automatically get the benefit of file
caching, database caching, and sessions.  You do not need to interact
directly with C<%store> to gain these features; ExSite manages that on
your behalf.

Items can be placed in the store with an expiry time (which can be 0
for no limit).  Items past their expiry time are automatically purged
from the store.

=item C<%msg>

The C<%msg> hash is a simple Internationalization facility.  By default
it simply echoes its key back as a value.  If you have a language other
than English defined as your default language, however, then it will
attempt to return an appropriate translation of the key instead.  By this
means, a line such as:

    print $msg{'Hello World'};

will print out the "Hello World" message in whatever language the 
system is defined to use (assuming that an appropriate dictionary 
is installed).

=back

=head1 Setup and Configuration Routines

=head2 server_autoconf()

This routine attempts to set the various server configuration
parameters (ie. file paths and machine names) automatically, by
inferring them from the server environment.  It works for simple
system configurations, but may get confused by unusual server
setups.  In the latter case, disable autoconfiguration by setting
C<server.auto = 0> in your configuration file.  You will then need
to specify the various server parameters manually.

B<Warning:> auto-configuration may fail when testing CGI programs from
the command line for testing/debugging purposes, because it may infer
different paths than the web server uses.  If you need to have correct
configuration, then either hard-code your configurations in
exsite.conf, or set some environment variables on your command line to
resemble the server environment.  The following environment variables
are used for auto-configuration: DOCUMENT_ROOT, SCRIPT_NAME,
SCRIPT_FILENAME, HTTPS, HTTP_HOST.

=head2 read_exsite_conf()

This routine loads configuration values from files.  By default 
it looks for "exsite.conf" files in the conf, ExSite and . directories.
An alternate filename can be given.  By default configuration values 
are read straight into the root of C<%config>, but a starting key can 
be given, eg. C<&read_exsite_conf("MyModule.conf","MyModule")> will
read the values in MyModule.conf into C<$config{MyModule}{...}>.

Configuration files contain parameters and values, separated by "=" 
(with any amount of whitespace around the "=".  Values extend from the 
first non-whitespace character after the "=", to the end of line.
Simple parameters are placed directly into C<%config>'s keys.  
Parameters of the form "a.b.c" are stored as C<$config{a}{b}{c}>. 
Config array references can be created using "+=" to set the values
in the array.

Example exsite.conf settings:

    trim_whitespace = 0
    form.style=list
    db_ops.new.url = append.cgi

=head2 exsite_init()

This routine configures ExSite, and performs any local initializations.
This routine is called automatically at the start of all
generic CGI scripts, and should be called by custom scripts
as well.

Local initialization can be done in C<&myConfig::my_exsite_init>,
which is called automatically from here.

=head2 exsite_close()

Call this at the end of every ExSite program to ensure that 
files, caches, sessions, etc. are properly flushed.

=head2 get_obj()

There are a handful of global objects that ExSite commonly works with.
The most common are the primary database object, and the current page
being constructed.  These are normally stored in %share to make them 
available to all components.

You can use get_obj() to fetch a predefined object safely.  That is,
it will return the predefined object if it exists, and it will create
the object if it does not exist.

Example:

C<my $db = &get_obj('DB');>

=head2 install_handlers()

Handlers allow plug ins or other subsystems to register special 
business logic that should take precedence over the default logic
in certain cases.

The ExSite base system has to do this in a few cases for its content
management tables, which have their own logic that differs from the
generic database handling.  Otherwise, it is expected that most 
handlers will be site-specific (registered in myConfig::my_handlers() )
or plug-in-specific (registered from the plug-in module in 
Modules/).

=cut

