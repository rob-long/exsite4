package ExSite::Dialog;
use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Input;

sub new ($%) {
	my ($this,%opt) = @_;
	my $obj = {};
	my $class = ref($this) || $this;
	bless $obj, $class;
	return $obj;
}
sub run{
	my $i = new ExSite::Input;
	my $ml = &get_obj("ML");
	if ($share{DB}->level < $config{form}{tinymce}{dialog}{access}){
		return "content-type: text/html\n\n".$ml->html($ml->head().$ml->body($ml->p("Access denied.")));
	}
	my $path = $i->path_info();
	if ($path =~ /Image/){
		return ExSite::Dialog::Image->new()->run($i);
	}elsif ($path =~ /Link/){
		return ExSite::Dialog::Link->new()->run($i);
	}elsif ($path =~ /Dyn/){
		return ExSite::Dialog::DynamicContent->new()->run($i);
	}
	return "content-type: text/html\n\n".$ml->html($ml->head().$ml->body($ml->p("Unknown Options")));
}

#########################################
package ExSite::Dialog::TinyMCE;
use strict;
use ExSite::Config;
use ExSite::Content;

sub new ($%) {
	my ($this,%opt) = @_;
	my $obj = {};
	my $class = ref($this) || $this;
	bless $obj, $class;
	return $obj;
}
sub conf{
	my ($this,$base,$new) = @_;
	if (ref ($new) =~ /array/i ){
		for(my $i = 0; $i < scalar(@$new); $i++){
			if (ref($new->[$i]) =~ /array|hash/i){
				$this->conf($base->[$i],$new->[$i]);
			}else{
				$base->[$i] = $new->[$i];
			}
		}
	}elsif (ref($new) =~ /hash/i){
		foreach my $key (keys(%$new)){
			if (ref($new->{$key}) =~ /array|hash/i){
				$this->conf($base->{$key},$new->{$key});
			}else{
				$base->{$key} = $new->{$key};
			}
		}
	}
	return;
}
sub css{
	my $ml = ExSite::Config::get_obj("ML");
	return $ml->style(".mce-menubtn span, div.mce-menubtn {line-height: 16px !important;} .mce-btn .mce-caret {margin-top: 6px !important;}");
}
sub jq_detect{
	return <<END;
var _stat_mce_load_jquery=false;function _mce_load_jquery(){if(typeof(jQuery)=='undefined'){if(!_stat_mce_load_jquery){_stat_mce_load_jquery=true;document.write("<scrip"+"t src='$config{jquery}'></scrip"+"t>");}setTimeout("_mce_load_jquery()",50);}};_mce_load_jquery();
END
}
sub setting{
	# $custom_opt: custom options overwrite default configurations
	# {
	#	editor_height: editor height
	#	editor_width: editor width
	#	link_simple: disable cms functions in link dialog
	#	editor=>{
	#		... follows the same data structure as $config{form}{tinymce}
	#	}
	# }
	# 
	my ($this,$custom_opt,$content_id,$section_id) = @_;
	my $c = new ExSite::Content(id=>$content_id);

	my $section_id = 0;
	my $i = new ExSite::Input;
	my $in = $i->combine;
	if ($in->{section_id}){
		$section_id = $in->{section_id};
	}
	if (!$section_id && $c->my_section){
		$section_id = $c->my_section->id;
	}

	my @disable_cmd;
	my %econfig = %{$config{form}{tinymce}};
	$this->conf(\%econfig,$custom_opt->{editor}) if ref($custom_opt->{editor}) =~ /hash/i;
	my %editor_setting =  %{$econfig{editor}};
	$editor_setting{script_url} = $config{server}{server}.$config{server}{HTMLpath}.$config{form}{tinymce}{path}."/tiny_mce.js";

	$editor_setting{height} = $custom_opt->{editor_height} if $custom_opt->{editor_height};
	$editor_setting{width} = $custom_opt->{editor_width} if $custom_opt->{editor_width};
	my $editor_mode = exists $econfig{mode}{toolbar}{$econfig{mode}{current}} ? $econfig{mode}{current}  : $econfig{mode}{default};

	# Link dialog
	my $dlglink_advanced = $editor_mode eq "basic" ? "basic" :  ($custom_opt->{link_simple} ? "basic" : (!$section_id ? "basic" : "full"));
	$editor_setting{plugin_link}{url} = sprintf("%s%s/%s/Link?id=%s&mode=%s",$config{server}{server},$config{server}{CGIpath},$config{prog}{dialog},$content_id,$dlglink_advanced);
	$editor_setting{plugin_link}{width} = $econfig{dialog}{dlglink}{popup}{$dlglink_advanced}{width};
	$editor_setting{plugin_link}{height} = $econfig{dialog}{dlglink}{popup}{$dlglink_advanced}{height};

	# Image dialog
	my $dlgimg_advanced = $editor_mode eq "basic" ? "basic" : ($section_id ? "full" : "basic");
	$editor_setting{plugins} .= ",dlgimg";
	$editor_setting{plugin_image}{url} = sprintf("%s%s/%s/Image?id=%s&mode=%s",$config{server}{server},$config{server}{CGIpath},$config{prog}{dialog},$content_id,$dlgimg_advanced);
	$editor_setting{plugin_image}{width} = $econfig{dialog}{dlgimg}{popup}{$dlgimg_advanced}{width};
	$editor_setting{plugin_image}{height} = $econfig{dialog}{dlgimg}{popup}{$dlgimg_advanced}{height};
	$editor_setting{plugin_image}{ajx_url} = "$config{server}{server}$config{server}{CGIpath}/$econfig{dialog}{dlgimg}{script}";
	$editor_setting{plugin_image}{section_id} = $section_id;

	# Dynamic content dialog
	$editor_setting{plugin_dyncontent}{img} = "$config{server}{server}$config{server}{HTMLpath}$config{form}{tinymce}{path}/plugins/dlgdyn/icon.gif";
	if ($editor_mode ne "basic"){
		if ($section_id){
			$editor_setting{plugins} .= ",dlgdyn";
			$editor_setting{plugin_dyncontent}{url} = sprintf("%s%s/%s/DynContent?id=%s",$config{server}{server},$config{server}{CGIpath},$config{prog}{dialog},$content_id);
			$editor_setting{plugin_dyncontent}{ajx_url} = "$config{server}{server}$config{server}{CGIpath}/$econfig{dialog}{dlgdyn}{script}";
			$editor_setting{plugin_dyncontent}{section_id} = $section_id;
		}
	}

	# Mailto dialog
	$editor_setting{plugins} .= ",dlgmailto";
	$editor_setting{plugin_mailto}{img} = "$config{server}{server}$config{server}{HTMLpath}$config{form}{tinymce}{path}/plugins/dlgmailto/icon.gif";
	my $icon_mailto = "$config{server}{HTMLpath}/_ExSite/_Modules/icon.gif";
	require ExSite::Module;
	my $mod = ExSite::Module::get_module("MailTo");
	if ($mod){
		$icon_mailto = $mod->icon($config{iconset});
	}
	$editor_setting{plugin_mailto}{plugin_img} = $icon_mailto;

	# Font drop down
	if ($econfig{editor}{font_formats}){
		$editor_setting{font_formats} = $econfig{editor}{font_formats};
	}

	# Menu
	$editor_setting{menu} = $econfig{mode}{toolbar}{$editor_mode}{menu};
	$editor_setting{menubar} = $econfig{mode}{toolbar}{$editor_mode}{menubar};

	# Toolbar
	for (my $i = 1;$i <= 4;$i++){
		$editor_setting{"toolbar".$i} =  (ref $econfig{mode}{toolbar}{$editor_mode}{"toolbar_row".$i} !~ /array/i) ? "" : join(",|,", map {$econfig{group}{$_} || ()} @{$econfig{mode}{toolbar}{$editor_mode}{"toolbar_row".$i}});
	}
	if ($editor_mode ne "basic"){
		$editor_setting{plugins} .= ",advlist";
	}

	return {conf=>\%econfig,init=>\%editor_setting};
}

#########################################
package ExSite::Dialog::Base;
use strict;
use ExSite::Config;
use ExSite::Section;
use ExSite::Content;

sub new ($%) {
	my ($this,%opt) = @_;
	my $obj = {};
	my $class = ref($this) || $this;
	bless $obj, $class;
	return $obj;
}
sub DB{
	return $share{DB};
}
sub ML{
	return ExSite::Config::get_obj("ML");
}
sub run{
	return;
}
sub section_id{
	my ($this) = @_;
	my $c = new ExSite::Content(id=>$this->content_id);
	return $c->my_section->id;
}
sub content_id{
	my ($this,$contentid) = @_;
	if (defined $contentid){
		$this->{content_id} = $contentid || 0;
	}
	return $this->{content_id} || 0;
}
sub content{
	my $this = shift;
	my $out = shift;
	return  "Expires: -1\nCache-Control: no-cache\nCache-Control: max-page=0, no-cache, no-store, must-revalidate\nPragma: no-cache\nContent-type: text/html\n\n".$out;
}
# Truncate text
sub truncate_text{
	# $text: text
	# $num: character limit
	my ($this,$text,$num) = @_;
	my $default = 150;
	my $cutoff = $num || $default;
	# Truncate the text
	if (length($text) > $cutoff){
		$text = substr($text,0,$cutoff);
		$text .= "...";
	}
	return $text;
}
#########################################
package ExSite::Dialog::DynamicContent;
use strict;
use ExSite::Config;
use ExSite::Module qw(&get_module &my_module_list);
use ExSite::Misc;
use JSON;

use ExSite::Dialog;
use base qw(ExSite::Dialog::Base);


sub run{
	my ($this,$INPUT) = @_;
	my $input = $INPUT->combine();
	my $ml = $this->ML();
	if ($input->{action} eq "geturl"){
		# icon url
		my $mod = ExSite::Module::get_module($input->{name});
		return "$config{server}{HTMLpath}/_ExSite/_Modules/icon.gif" if !$mod;
		return $this->content(ExSite::Module::icon($input->{name},$config{iconset}));
	# get module parameters
	}elsif ($input->{action} eq "getparam"){
		# Running DynContentParameter routine to create
		# the optional parameter input field for the dialog
		#
		# - the name of the input field has to be 'param'.
		#
		my $default = $ml->strong("Parameter (optional):").$ml->input(undef,{type=>"text",name=>"param",value=>""});
		my $param_input = $default;
		my $module = $input->{name} || "";
		if ($module){
			my $mod = ExSite::Module::get_module($module);
			$param_input = $mod ? ($mod->ioctl("DynContentParameter") || $default) : $default;
		}
		return $this->content($param_input);
	}
	return $this->content($ml->html($ml->head($ml->title("Web Application")).$ml->body($this->form($input->{section}))));
}
sub form{
	my ($this,$sectionid) = @_;
	my $ml = $this->ML();
	my @list;
	foreach my $mod (&ExSite::Module::my_module_list($sectionid)) {
	    my $name = exists $config{webtop}{module_name}{$mod} ? $config{webtop}{module_name}{$mod} : $mod;
	    next if (! $name);
	    push @list, $ml->option($name,{value=>$mod});
	}
	return $ml->p("No web application found.") if (scalar(@list) < 1);
	my %tdata = (
		tinymce_path=>"$config{server}{server}$config{server}{HTMLpath}$config{form}{tinymce}{path}",
		module_list=>join("",@list),
		dlg_file=>"$config{server}{server}$config{server}{CGIpath}/$config{prog}{dialog}$config{form}{tinymce}{dialog}{dlgdyn}{script}",
		section_id=>$sectionid,
		cgipath=>"$config{server}{CGIpath}",
		jquery=>"$config{jquery}",
	);
	my $template = <<END;
<!DOCTYPE html>
<html lang="en">
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<link rel="stylesheet" href="[[tinymce_path]]/skins/lightgray/skin.min.css">
</head>
<body>
<script src="[[jquery]]"></script>
<!-- Latest compiled and minified CSS -->
<link rel="stylesheet" href="//netdna.bootstrapcdn.com/bootstrap/3.0.2/css/bootstrap.min.css">
<!-- Optional theme -->
<link rel="stylesheet" href="//netdna.bootstrapcdn.com/bootstrap/3.0.2/css/bootstrap-theme.min.css">
<!-- Latest compiled and minified JavaScript -->
<script src="//netdna.bootstrapcdn.com/bootstrap/3.0.2/js/bootstrap.min.js"></script>
<script>
var dyndlg = {
	closeFlag : 0,
	close : function(){
		this.closeFlag = 1;
	},
	getDialogParam : function(id,module,param) {
		if (module == '') return;
		var h,w;
		jQuery.ajax({'url':'[[dlg_file]]','type':'GET','dataType':'html','async':false,'success':function(data){jQuery("#" + id).html(data);},'data':{'action':'getparam','name':module,'param':escape(param)}});
		h = jQuery("form#dyndlg").height() + 40;
		w = jQuery("form#dyndlg").width() + 15;
	},
	insert : function(){
		if (this.closeFlag){
			parent.tinymce.activeEditor.windowManager.close();
			return;
		}
		var ed = parent.tinymce.activeEditor, n = jQuery("#dyncontent").val(), p = '', u;
		jQuery("form#dyndlg :input").each(function(){
			var _i = jQuery(this).attr('name'), _v = new String(), _t = jQuery(this).attr('type');
			if ( _t == 'radio' || _t == 'checkbox'){
				if (jQuery(this).is(":checked")){
					_v = jQuery(this).val();
				}else{
					_v = '';
				}
			}else{
				_v = jQuery(this).val();
			}
			if (_i != 'dyncontent' && _i != 'insert' && _i != 'cancel' && _v){
				if (p) p += '&amp;';
				if (_i != 'param') p += _i + '=';
				_v = _v.replace(/(\\r\\n|\\n|\\r)/gm," ");
				p += _v;
			}
		});
		if (!n){
			alert('You must select a web application');
			return;
		}
		jQuery.ajax({'url':'[[dlg_file]]','type':'GET',data:{'action':'geturl','name':n},'dataType':'html','async':false,'success':function(data){
		u = data;
		}});
		m = '<img alt="' + n + '(' + p + ')" name="' + n + '" src="' + u + '" title="' + n + '" border="3" style="border-style:outset;">';
		ed.execCommand("mceInsertContent", false, m);
		parent.tinymce.activeEditor.windowManager.close();
	},
	init : function(){
		this.closeFlag = 0;
		var inst = parent.tinymce.activeEditor,elm;
		elm = inst.selection.getNode();
		elm = inst.dom.getParent(elm,'IMG');
		if (elm != null && elm.nodeName == 'IMG'){
			var n,p,t = new String(elm.getAttribute('alt'));
			t.replace(/\\n/gi," ");
			if (t.match(/\\w+\\(.*\\)/gi)){
				t.replace(/(\\w+)\\((.*)\\)/gi,function(m,f,s){n=f;p=s;});
			}
			if (n){
				jQuery("#dyncontent").val(n);
				dyndlg.getDialogParam('param_input',n,p)
			}
		}
	}
};
</script>
<div class="container">
	<form id="dyndlg" onsubmit="dyndlg.insert();return false;" style="display:inline-block;" role="form">
	<div class="form-group">
		<label class="control-label" for="dyncontent">Web Application</label>
		<select class="form-control" id="dyncontent" name="dyncontent" onChange="dyndlg.getDialogParam('param_input',this.value)">
			<option value="">== Select ==</option>
			[[module_list]]
		</select>
	</div>
	<div class="form-group">
		<label class="control-label">Options</label>
		<div id="param_input" class="form-control-static">
			<strong>Parameter (optional):</strong><input type="text" name="param" value="">
		</div>
	</div>
	<div class="form-group text-right">
		<button class="btn mce-btn mce-primary">Insert</button>
		<button class="btn btn-default active" onclick="dyndlg.close();">Cancel</button>
	</div>
	</form>
</div>
</body>
</html>
END
	return ExSite::Misc::substitute($template,\%tdata);
}

#########################################
package ExSite::Dialog::Image;
use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Image;
use ExSite::Content;
use MIME::Base64;

use ExSite::Dialog;
use base qw(ExSite::Dialog::Base);

sub run{
	my ($this,$INPUT) = @_;
	my $input = $INPUT->combine();
	$this->content_id($input->{id});
	my $ml = $this->ML;
	if ($input->{action} eq "getimagelist"){
		# get image/document list
		return $this->content($this->getImageList($input));
	}elsif ($input->{action} eq "getimage"){
		# get single image/document
		return $this->content($this->get_object("image"));
	}elsif ($input->{action} eq "geturl"){
		# get img url
		return $this->content($this->get_object("url"));
	}
	# process image/document upload
	return $this->content($ml->html($ml->head($ml->title("Image/Document Tool")).$ml->body(($input->{action} eq "upload_file" ? $this->upload($input) : "").$this->form($input))));
}
# javascript popup
sub alertPopup{
	my ($this,$msg) = @_;
	return $this->ML->script("alert('$msg');");
}
# process form data
sub upload{
	my $this = shift;
	my $data = shift;
	return $this->alertPopup("Error: File upload failed.  No library is selected.") if !$data->{library};
	return $this->alertPopup("Error: File upload failed.  No file is selected.") if !$data->{fileupload};
	my $filename;
	my $rawdata = undef;
	my $size = 0;
	my $mimedata = "";
	my $file = $data->{fileupload};
	my $continue = 1;
	# read upload data
	while ($continue){
		$continue = read($file,$rawdata,1024,$size);
		$size += $continue;
	}
	return $this->alertPopup("Error: File upload failed.  No file data was received.") if !$size;
	my @path = split /[:\\\/]/, $file;
	if ($path[-1]){
		$filename = ExSite::Misc::clean_filename($path[-1]);
	}
	my $fdata;
	if (ExSite::Misc::MimeType($filename) !~ /^image/i){
		$fdata = $filename."#".MIME::Base64::encode_base64($rawdata);
	}else{
		my $img = new ExSite::Image($filename,$rawdata);
		$img->shrink();
		$fdata = $img->encode;
	}
	my $cname = $filename;
	my $c = new ExSite::Content;
	$c = $c->new_content_obj(
		type=>"content",
		name=>$cname,
		parent=>$data->{library}
	);
	my @error;
	if ($c->id){
		$c->revise(format=>"file",data=>$fdata,view=>{normal=>1,thumbnail=>1});
	}
	if (ExSite::Config::AtError() > 0){
		my $_err = ExSite::Config::show_diagnostics("text");
		$_err =~ s/\\n//g;
		$_err =~ s/'/\\\'/g;
		push @error, $_err if $_err;
	}
	if (scalar(@error) <= 0){
		return $this->alertPopup("$filename has been uploaded successfully.");
	}else{
		my $error_message = join("\\n",@error);
		return $this->alertPopup($error_message);
	}
	return;
}
# create an image/document list
sub getImageList{
	my ($this,$data) = @_;
	my $ml = $this->ML();
	my $c = new ExSite::Content(id=>$this->content_id);
	my $list = $c->get_contents;
	my $selector;
	my $limit = 25;
	foreach my $cnt (@$list){
		next if (!$cnt->revision->is_file && !$cnt->revision->is_image);
		my $name = $cnt->name;
		my $ext = "";
		if ($name =~ /(.+)\.(.+)$/){
			$name = $1;
			$ext = $2;
		}
		my $filename = (length($name) > $limit ? substr($name,0,$limit)."..." : $name).($ext ? ".${ext}" : "");
		$selector .= $ml->option($filename,{value=>sprintf("%s:%s",$cnt->id,$cnt->name)});
	}
	return $ml->select($ml->option("== Select ==",{value=>""}).$selector,{id=>"obj_id",name=>"obj_id",onChange=>"dlgimg.showimage()",class=>"form-control"});
}
# Get library object
sub get_object{
	my ($this,$type) = @_;
	return "" if !$this->content_id;
	my $ml = $this->ML();
	my $no_preview = "No preview available";
	# Create a content object
	my $c = new ExSite::Content(id=>$this->content_id);
	my $out;
	if ($type eq "image"){
		my $mimetype = $c->revision->mime_type;
		if ($mimetype =~ /^(image|application)/i){
			if ($mimetype =~ /^image/i){
				$out .= $c->revision->get_thumb_html;
			}else{
				$out .= $ml->a($c->name,{href=>$c->get_view_url_dynamic,target=>"_blank"});
			}
		}else{
			$out .= $c->description || $no_preview;
		}
	}elsif ($type eq "url"){
		if ($c->revision->view->is_image){
			$out .= $c->get_view_url_dynamic;
		}else{
			$out .= "$config{server}{HTMLpath}/_ExSite/images/checker.png";
		}
	}else{
		$out .= $no_preview;
	}
	return $out;
}
sub form{
	my $this = shift;
	my $data = shift;
	my $db = $this->DB();
	my $ml = $this->ML();
	my $selectedlib = 0;
	my $c = new ExSite::Content(id=>$this->content_id);
	my $sectionid = 0;
	my $s = $c->my_section;
	$s = $s->get_content_obj;
	my $sectionid = $s->id;
	my @libs;
	if ($s){
		@libs = $s->fetch_libraries;
	}
	my $loclist = $ml->option("Current Page",{
		value=>$c->getdata("parent"),
		selected=>undef
	});
	$selectedlib = $c->getdata("parent");
	$loclist .= join("",map {
		my $cnt = new ExSite::Content(data=>$_);
		$cnt = $cnt->get_content_obj;
		my %opt = (value=>$cnt->id);
		$ml->option($cnt->label,\%opt)
	} @libs);

	my $allow_upload = $sectionid && $config{form}{tinymce}{dialog}{dlgimg}{allow_file_upload} ? 1 : 0;

	my %tdata = (
		dlg_file=>"$config{server}{server}$config{server}{CGIpath}/$config{prog}{dialog}$config{form}{tinymce}{dialog}{dlgimg}{script}",
		tinymce_path=>"$config{server}{server}$config{server}{HTMLpath}$config{form}{tinymce}{path}",
		jquery_js=>$config{jquery},
		insert_library_select=>$loclist,
		selected_lib=>$selectedlib,
		insert_image_attribute=>join("",map {$ml->option($_->{label},{value=>$_->{value}})} (({label=>"Left",value=>"left"},{label=>"Right",value=>"right"}), ($config{form}{htmleditor}{imgalign_all} ? ({label=>"Top",value=>"top"},{label=>"Bottom",value=>"bottom"}) : ()))),
		upload_library_select=>($allow_upload ? $loclist : ""),
		section_id=>($sectionid || 0),
		content_id=>$this->content_id,
		mode=>$data->{mode},
	);
	if ($data->{mode} eq "full"){
		$tdata{advance_mode} = 1;
	}
	if ($allow_upload  && $data->{mode} eq "full"){
		$tdata{allow_file_upload} = 1;
	}
	my $template = <<END;
<!DOCTYPE html>
<html lang="en">
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
</head>
<body>
<script src="[[jquery_js]]"></script>
<!-- Latest compiled and minified CSS -->
<link rel="stylesheet" href="//netdna.bootstrapcdn.com/bootstrap/3.0.2/css/bootstrap.min.css">
<!-- Optional theme -->
<link rel="stylesheet" href="//netdna.bootstrapcdn.com/bootstrap/3.0.2/css/bootstrap-theme.min.css">
<!-- Latest compiled and minified JavaScript -->
<script src="//netdna.bootstrapcdn.com/bootstrap/3.0.2/js/bootstrap.min.js"></script>
<link rel="stylesheet" href="[[tinymce_path]]/skins/lightgray/skin.min.css">
<style>
.numeric-field {
width: 100px !important;
}
</style>
<script>
var dlgimg = {
	closeFlag : 0,
	close : function(){
		this.closeFlag = 1;
	},
[[?advance_mode]]
	isImage : 0,
	showimage : function(){
		var id = jQuery("#obj_id").val();
		if (!id){
			return;
		}
		jQuery.ajax({'url':'[[dlg_file]]','type':'GET','dataType':'html','async':false,'success':function(data){var re = RegExp('img');if (re.test(data)){dlgimg.showAlignmentForm();}else{dlgimg.hideAlignmentForm();}jQuery("#disp").html(data);},'data':{'action':'getimage','id':id}});
	},
	getImageList : function(){
		var id = jQuery("#lib_id").val();
		this.hideAlignmentForm();
		this.clearPreviewBlock();
		jQuery.ajax({'url':'[[dlg_file]]','type':'GET','dataType':'html','async':false,'success':function(data){jQuery("#imageSelector").html(data);},'data':{'action':'getimagelist','id':id}});
	},
	elmAlignment : [
		{"name":"imagealignment","type":"disabled"},
		{"name":"imagenoncontent","type":"disabled"},
		{"name":"imageborderwidth","type":"disabled"},
		{"name":"imagenoncontent","type":"checked"},
		{"name":"imagedesc","type":"disabled"},
		{"name":"imageheight","type":"disabled"},
		{"name":"imagewidth","type":"disabled"}
	],
	hideAlignmentForm : function(){
		for(var i = 0;i < this.elmAlignment.length;i++){
			jQuery("#" + this.elmAlignment[i].name).attr(this.elmAlignment[i].type,true);
		}
		this.isImage = 0;
	},
	showAlignmentForm : function(){
		for(var i = 0;i < this.elmAlignment.length;i++){
			jQuery("#" + this.elmAlignment[i].name).attr(this.elmAlignment[i].type,false);
		}
		this.isImage = 1;
	},
	clearPreviewBlock : function(){
		jQuery("#disp").html('');
	},
	getContentID : function(val){
		var stringsplt = val.split(':');
		return stringsplt[0];
	},
	getContentName : function(val){
		var result,stringsplt;
		result = '';
		stringsplt = val.split(':');
		for(var i = 1; i < stringsplt.length; i++){
			result += stringsplt[i];
		}
		return result;
	},
	inputImgBorderWidth : function(obj){
		var elms = [
			{"name":"imageborderwidth","type":"disabled"},
			{"name":"imagealignment","type":"disabled"},
			{"name":"imagedesc","type":"disabled"},
			{"name":"imageheight","type":"disabled"},
			{"name":"imagewidth","type":"disabled"}
		];
		var st = obj.checked ? true : false;
		for(var i = 0; i < elms.length; i++){
			jQuery("#" + elms[i].name).attr(elms[i].type,st);
		}
	},
	insertImgDoc : function(){
		if (this.closeFlag){
			parent.tinymce.activeEditor.windowManager.close();
			return;
		}
		var oid = jQuery("#obj_id").val(); p_name = this.getContentName(oid);
		if (!p_name){
			alert('You must select an image/document');
			return;
		}
		var objId = this.getContentID(oid);
		jQuery.ajax({'url':'[[dlg_file]]','type':'GET','dataType':'html','async':false,'success':function(data){if (jQuery.browser.msie){jQuery('<img>').attr('src',data).ready(function(){dlgimg.doInsertImgDoc(p_name,data,this);});}else{jQuery('<img>').attr('src',data).load(function(){dlgimg.doInsertImgDoc(p_name,data,this);});}},'data':{'action':'geturl','id':objId}});
	},
	doInsertImgDoc : function(p_name,p_url,img){
		if (this.closeFlag){
			parent.tinymce.activeEditor.windowManager.close();
			return;
		}
		var ed = parent.tinymce.activeEditor,p_align,non_img,p_borderwidth,p_desc,p_width,p_height,p_alt,p;
		p_align = jQuery("#imagealignment").val();
		non_img = jQuery("#nonimagecontent").is(":checked") ? 1 : 0;
		p_borderwidth = jQuery("#imageborderwidth").val() || 0;
		p_desc = new String(jQuery("#imagedesc").val() || '').replace("'", "\\\'").replace('"',"&quot;").replace("<","&lt;").replace(">","&gt;");
		var re = new RegExp('checker');
		if (re.test(p_url)){
			img.width = 100;
			img.height = 50;
		}
		p_width = jQuery("#imagewidth").val() || '';
		p_height = jQuery("#imageheight").val() || '';
		p_alt = 'content(' + p_name + ')';
		if (dlgimg.isImage > 0 && non_img < 1){
			p_alt = '[' + '[' + p_name + ']' + ']';
		}
		p = '<img alt="' + p_alt + '" src="' + p_url + '" title="' + (p_desc == '' ? p_name : p_desc) + '"' + (p_width ? ' width="' + p_width + '"' : '') + (p_height ? ' height="' + p_height + '"' : '');
		p += p_align != '' ? ' class="' + (p_align == 'left' ? 'alignLeft' : 'alignRight' ) + '" align="' + p_align + '"' : '';
		p += (!isNaN(p_borderwidth) ? ' border="' + p_borderwidth + '"' : '') + '>';
		ed.execCommand("mceInsertRawHTML", false, p);
		parent.tinymce.activeEditor.windowManager.close();
	},
[[/?advance_mode]]
[[?allow_file_upload]]
	insertFile : function() {
		var err = new Array();
		if (!jQuery("#library").val())
			err.push('No library selected');
		if (!jQuery("#fileupload").val())
			err.push('No file selected');
		if (err.length > 0){
			alert("Error:\\n" + err.join("\\n"));
			return false;
		}
		return true;
	},
[[/?allow_file_upload]]
	insertUrl : function() {
		var p_url = jQuery("#img_url").val();
		if (!p_url){
			alert('You must enter an image url');
			return;
		}
		var ed = parent.tinymce.activeEditor,tmpImg = new Image(),p_align = jQuery("#url_imagealignment").val(),p_borderwidth,p_desc,p_width,p_height,p;
		tmpImg.src = p_url;
		p_borderwidth = jQuery("#url_imageborderwidth").val() || 0;
		p_desc = new String(jQuery("#url_image_desc").val() || '').replace("'", "\\\'").replace('"',"&quot;").replace("<","&lt;").replace(">","&gt;");
		p_width = jQuery("#url_imagewidth").val() || tmpImg.width;
		p_height = jQuery("#url_imageheight").val() || tmpImg.height;
		p = '<img src="' + p_url + '" title="' + p_desc + '"' + (p_width > 0 ? ' width="' + p_width + '"' : '') + (p_height > 0 ? ' height="' + p_height + '"' : '') + (typeof(p_align) != 'undefined' ? ' align="' + p_align + '" class="' + (p_align == 'left' ? 'alignLeft' : 'alignRight') + '"' : '') + (!isNaN(p_borderwidth) ? ' border="' + p_borderwidth + '"' : '') + '>';
		ed.execCommand("mceInsertContent", false, p);
		parent.tinymce.activeEditor.windowManager.close();
	}[[?advance_mode]],
	init : function(){
		this.closeFlag = 0;
		jQuery("#lib_id").val([[selected_lib]]);
		this.getImageList();
		var input_style = {
			'background-color' : '#f0f0ee',
			'border' : 'none'
		};
		jQuery(":input[type='checkbox']").css(input_style);
	}
[[/?advance_mode]]
};
jQuery(document).ready(function(){
	dlgimg.init();
	jQuery("#img_prop_link").click(function(){
		if (jQuery("#img_prop").is(":visible")){
			jQuery("#img_prop").addClass("hide");
			jQuery("#img_toggle").removeClass("glyphicon-chevron-up");
			jQuery("#img_toggle").addClass("glyphicon-chevron-down");
		}else{
			jQuery("#img_prop").removeClass("hide");
			jQuery("#img_toggle").removeClass("glyphicon-chevron-down");
			jQuery("#img_toggle").addClass("glyphicon-chevron-up");
		}
	});
});
</script>
<div class="container">
<br>
[[?advance_mode]]
<div id="content">
	<ul id="tabs" class="nav nav-tabs" data-tabs="tabs">
		<li class="active"><a href="#imgdoc" data-toggle="tab">Image/Document</a></li>
		<li><a href="#url" data-toggle="tab">URL</a></li>
[[/?advance_mode]]
[[?allow_file_upload]]
		<li><a href="#upload" data-toggle="tab">File Upload</a></li>
[[/?allow_file_upload]]
[[?advance_mode]]
	</ul>
	<div id="my-tab-content" class="tab-content">
		<div class="tab-pane active" id="imgdoc">
			<div class="container">
			<form id="img_frm" onSubmit="dlgimg.insertImgDoc();return false;" action="#" role="form" class="form-horizontal">
				<div class="form-group">
					<label class="control-label" for="lib_id">Location</label>
						<select id="lib_id" name="lib_id" onChange="dlgimg.getImageList()" class="form-control"><option value="">== Select ==</option>[[insert_library_select]]</select>
				</div>
				<div class="form-group">
					<label class="control-label" for="obj_id">Image/Document</label>
					<span id="imageSelector"><select id="obj_id" name="obj_id" onChange="dlgimg.showimage()" class="form-control"><option value="">== Select ==</option></select></span>
				</div>
				<div class="form-group">
					<label>Image Properties</label> <a id="img_prop_link" style="cursor:pointer;"><span id="img_toggle" class="glyphicon glyphicon-chevron-down"></span></a>
				</div>

				<div id="img_prop" class="hide container">

				<div class="form-group">
					<label class="control-label" for="imagedesc">Description</label>
					<input type="text" id="imagedesc" name="imagedesc" value="" class="form-control">
				</div>
				<div class="form-group">
					<label class="control-label">Dimension</label>
					<div class="input-group">
						<input class="form-control numeric-field" type="text" id="imagewidth" name="imagewidth" value="" size="4">
						x
						<input class="form-control numeric-field" type="text" id="imageheight" name="imageheight" value="" size="4">
					</div>
				</div>
				<div class="form-group">
					<label class="control-label">Alignment</label>
					<select id="imagealignment" name="align" class="form-control"><option value="">None</option>[[insert_image_attribute]]</select>
				</div>
				<div class="form-group">
					<label class="control-label" for="imageborderwidth">Border Width</label>
					<input class="form-control numeric-field" type="text" id="imageborderwidth" name="imageborderwidth" value="0">
				</div>
				<div class="form-group">
					<div class="checkbox">
						<label>
							<input id="nonimagecontent" type="checkbox" name="nonimagecontent" value="1" onClick="dlgimg.inputImgBorderWidth(this)"> Non-image content
						</label>
					</div>
				</div>

				</div>

				<div class="form-group">
					<label class="control-label">Image Preview</label>
					<div id="disp" style="margin:0; width:100%; height:100px; overflow:auto;"></div>
				</div>
				<div class="form-group text-right">

					<button class="btn mce-btn mce-primary">Insert</button>
					<button class="btn btn-default active" onclick="dlgimg.close();">Cancel</button>
				</div>
			</form>
			</div>
		</div>
[[/?advance_mode]]
		<div class="tab-pane" id="url">
		<div class="container" style="padding-left: 0px;">
			<br>
			<form id="url_frm" onSubmit="dlgimg.insertUrl();return false;" action="#" role="form" class="form-horizontal">
				<div class="form-group">
					<label class="control-label col-xs-2" for="img_url">URL</label>
					<div class="col-xs-10">
						<input class="form-control" id="img_url" name="img_url" value="">
					</div>
				</div>
				<div class="form-group">
					<label class="control-label col-xs-2" for="image_desc">Description</label>
					<div class="col-xs-10">
						<input class="form-control" type="text" id="url_image_desc" name="imagedesc" value="">
					</div>
				</div>
				<div class="form-group">
					<label class="col-xs-2 control-label">Dimension</label>
					<div class="col-xs-10">
						<div class="input-group">
							<input class="form-control numeric-field" type="text" id="url_imagewidth" name="imagewidth" value="" size="4">
							x
							<input class="form-control numeric-field" type="text" id="url_imageheight" name="imageheight" value="" size="4">
						</div>
					</div>
				</div>
				<div class="form-group">
					<label class="control-label col-xs-2" for="imagealignment">Alignment</label>
					<div class="form-input col-xs-10">
						<select class="form-control" id="url_imagealignment" name="align"><option value="">None</option>[[insert_image_attribute]]</select>
					</div>
				</div>
				<div class="form-group">
					<label class="control-label col-xs-2" for="imageborderwidth">Border Width</label>
					<div class="col-xs-10">
						<input class="form-control numeric-field" type="text" id="url_imageborderwidth" name="imageborderwidth" value="0" size="2">
					</div>
				</div>
				<div class="form-group text-right">
					<button class="btn mce-btn mce-primary">Insert</button>
					<button class="btn btn-default active" onclick="dlgimg.close();">Cancel</button>
				</div>
			</form>
		</div>
		</div>
[[?allow_file_upload]]
		<div class="tab-pane" id="upload">
		<div class="container">
			<form id="upload_frm" method="post" enctype="multipart/form-data" action="[[dlg_file]]" onSubmit="return dlgimg.insertFile();" role="form" class="form-horizontal">
			<input type="hidden" name="action" value="upload_file">
			<input type="hidden" name="id" value="[[content_id]]">
			<input type="hidden" name="mode" value="[[mode]]">
			<div class="form-group">
				<label class="control-label" for="library">Location</label>
				<select class="form-control" name="library" id="library">[[upload_library_select]]</select>
			</div>
			<div class="form-group">
				<label class="control-label" for="fileupload">File</label>
				<input type="file" id="fileupload" name="fileupload">
			</div>
			<div class="form-group text-right">
				<button class="btn mce-btn mce-primary">Upload</button>
				<button class="btn btn-default active" onclick="dlgimg.close();">Cancel</button>
			</div>
			</form>
		</div>
		</div>
	</div>
[[/?allow_file_upload]]

</div>
</div>

</body>
</html>
END
	return ExSite::Misc::substitute($template,\%tdata);
}

#########################################
package ExSite::Dialog::Link;
use strict;
use ExSite::Config;
use ExSite::Misc;
use ExSite::Section;

use ExSite::Dialog;
use base qw(ExSite::Dialog::Base);

sub run{
	my ($this,$INPUT) = @_;
	my $input = $INPUT->combine();
	$this->content_id($input->{id});
	my $ml = $this->ML();
	my $dlg_mode = $input->{mode};
	if ($input->{action} eq "getpagelist"){
		return $this->content($this->getPageList($input));
	} elsif ($input->{action} eq "getlib"){
		return $this->content($this->getlib($this->content_id,$input->{name}));
	} elsif ($input->{action} eq "geturl"){
		return $this->content($this->geturl($this->content_id,$input->{url}));
	} elsif ($input->{action} eq "getcontentname"){
		return $this->content($this->getcontentname($this->content_id,$input->{url}));
	}
	return $this->content($ml->html($ml->head($ml->title("Insert/Edit Link")).$ml->body($this->form($dlg_mode,$input,$this->fetch_page($input)))));
}
sub getcontentname{
	my ($this,$contentid,$url) = @_;
	my $newurl = $url;
	if ($newurl =~ /^.*?name=(.+?)(&(.*?))?$/){
		$newurl =~ s/^.*?name=(.+?)(&(.*?))?$/$1/gis;
	}
	if ($newurl =~ /\[\[.+?\]\]/){
		$newurl =~ s/\[\[(.+?)\]\]/$1/gis;
	}
	return $newurl;
}
sub geturl{
	my ($this,$contentid,$url) = @_;
	my $newurl;
	{
		$url =~ /^.*?href=(\"|')?([^>]+?)(\s|\"|').*$/gis;
		$newurl = $2;
	}
	return $newurl;
}
sub getlib{
	my ($this,$contentid,$name) = @_;
	my $libid = 0;
	if ($contentid && $name){
		my $c = new ExSite::Content(id=>$contentid);
		my $found = $c->find($name);
		$found = $found->get_content_obj;
		$libid = $found->id;
	}
	return $libid;
}
# Fetch pages
sub fetch_page{
	my ($this,$query) = @_;
	my $c = new ExSite::Content(id=>$this->content_id);
	$c->load;
	my $s = $c->my_section;
	if ($s){
		my @pages = $s->get_all_pages;
		return \@pages;
	}
	return [];
}
# create a library drop down list
sub getLibrarySelector{
	my ($this,$in) = @_;
	my $ml = $this->ML();
	my $len = 50;
	my $c = new ExSite::Content(id=>$this->content_id);
	my $s = $c->my_section;
	$s = $s->get_content_obj;
	my @libs;
	if ($s){
		@libs = $s->fetch_libraries;
	}
	my @options = ($ml->option("Current Page",{value=>$c->getdata("parent")}));
	foreach my $l(@libs){
		my $l = new ExSite::Content(data=>$l);
		$l = $l->get_content_obj;
		push @options, $ml->option($this->truncate_text($l->label,$len),{value=>$l->id});
	}
	return $ml->select($ml->option("== Select Location ==",{value=>""}).join("",@options),{id=>"lib_id",name=>"lib_id",onChange=>"dlglnk.getLibraryList()",class=>"form-control"});
}
# Image/document drop down list
sub getPageList{
	my ($this,$in) = @_;
	my $ml = $this->ML();
	my $c = new ExSite::Content(id=>$in->{id});
	$c = $c->get_content_obj;
	my @content_list = $c->get_contents;
	my @options;
	foreach my $cl (@content_list){
		next if (!$cl->revision->is_file && !$cl->revision->is_image);
		push @options, $ml->option($this->truncate_text($cl->label),{value=>sprintf("[[%s]]",$cl->name)});
	}
	return $ml->select($ml->option("== Select Image/Document ==",{value=>""}).join("",@options),{name=>"obj_id",onChange=>"dlglnk.selectLibrary()",class=>"form-control"});
}
sub form{
	my ($this,$mode,$in,$links) = @_;
	my $ml = $this->ML();
	my $section_id = $this->section_id;
	my $len = 47;
	my @links = map {
		my $p = new ExSite::Page(data=>$_);
		$p = $p->get_content_obj;
		{id=>$p->id,url=>$p->name,text=>(length($p->label) > $len ? substr($p->label,0,$len)."..."  : $p->label)." (".$p->name.")"}
	} sort {uc($a->{name}) cmp uc($b->{name})} @$links;

	my %template_data = (
		tinymce_path=>"$config{server}{server}$config{server}{HTMLpath}$config{form}{tinymce}{path}",
		jquery_js=>$config{jquery},
		url=>($in->{url} || ""),
		select_library=>$this->getLibrarySelector($in),
		httprequest_js=>"$config{server}{server}$config{server}{HTMLpath}/_ExSite/js/httprequest.js",
		page_list=>(scalar(@$links) > 0 ? "var pageref = new Array();".join("",map {"pageref[\"".$_->{url}."\"] = '".$_->{id}."';"} @links) : ""),
		enable_cms_cmd=>($section_id ? 1 : 0),
		dlg_file=>"$config{server}{server}$config{server}{CGIpath}/$config{prog}{dialog}$config{form}{tinymce}{dialog}{dlglink}{script}",
		section_id=>($section_id || 0),
		content_id=>$this->content_id,
		select_internal_page=>$ml->option("==".(scalar @links > 0 ? "Select Internal Page" : "No Pages Found")."==",{value=>""})
	);
	if ($in->{mode} eq "full"){
		$template_data{advance_mode} = 1;
	}
	map { $template_data{select_internal_page} .= $ml->option($this->truncate_text($_->{text},$len),{value=>"{{$_->{url}}}"}); } @links;

	my $template = <<END;
<!DOCTYPE html>
<html lang="en">
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
</head>
<body>
<script src="[[jquery_js]]"></script>
<!-- Latest compiled and minified CSS -->
<link rel="stylesheet" href="//netdna.bootstrapcdn.com/bootstrap/3.0.2/css/bootstrap.min.css">
<!-- Optional theme -->
<link rel="stylesheet" href="//netdna.bootstrapcdn.com/bootstrap/3.0.2/css/bootstrap-theme.min.css">
<!-- Latest compiled and minified JavaScript -->
<script src="//netdna.bootstrapcdn.com/bootstrap/3.0.2/js/bootstrap.min.js"></script>
[[?advance_mode]]<script src="[[httprequest_js]]"></script>[[/?advance_mode]]
<link rel="stylesheet" href="[[tinymce_path]]/skins/lightgray/skin.min.css">
<script>
[[?advance_mode]]
[[page_list]]
[[/?advance_mode]]
var dlglnk = {
	closeFlag : 0,
	close : function(){
		this.closeFlag = 1;
	},
	setAttrib : function (elm, attrib, value) {
		var valueElm = document.forms.dialog_form.elements[attrib.toLowerCase()];
		var dom = parent.tinymce.activeEditor.dom;
		if (typeof(value) == "undefined" || value == null) {
			value = "";
			if (valueElm)
				value = valueElm.value;
		}
		// Clean up the style
		if (attrib == 'style') value = dom.serializeStyle(dom.parseStyle(value), 'a');
		dom.setAttrib(elm, attrib, value);
	},
	setAllAttribs : function (elm) {
		var href = new String(document.forms.dialog_form.linkURL.value);
[[?advance_mode]]
		if (jQuery("input[name='link_to']:checked").val() == 'url'){
[[/?advance_mode]]
			if (!href.match(/^#/ && !href.match(/^mailto:/i))){
				if (!href.match(/^http/i) && !href.match(/^\\//)){
					href = 'http://' + href;
				}
			}
[[?advance_mode]]
		}
[[/?advance_mode]]
		var target = jQuery("input[type='checkbox'][name='newwindow']").is(":checked") == true ? '_blank' : "";
		this.setAttrib(elm, 'href', href);
		this.setAttrib(elm, 'target', target == '_self' ? '' : target);
		// Refresh in old MSIE
		if (parent.tinymce.isMSIE5)
			elm.outerHTML = elm.outerHTML;
	},
	insertAction : function () {
		if (this.closeFlag){
			parent.tinymce.activeEditor.windowManager.close();
			return;
		}
		var inst = parent.tinymce.activeEditor;
		var elm, elementArray, i, url, txt;
		elm = inst.dom.getParent(inst.selection.getNode(), 'a[href]');
		url = document.forms.dialog_form.linkURL.value;
		// Remove element if there is no href
		if (!url) {
			inst.execCommand("unlink");
			parent.tinymce.activeEditor.windowManager.close();
			return;
		}
		inst.execCommand("mceBeginUndoLevel");
		// Create new anchor elements
		if (elm == null) {
[[?advance_mode]]
			if (jQuery("input[name='link_to']:checked").val() == 'url'){
[[/?advance_mode]]
			if (!url.match(/^#/) && !url.match(/^mailto:/i)){
				if (!url.match(/^http/i) && !url.match(/^\\//)){
					url = 'http://' + url;
				}
			}
[[?advance_mode]]
			}
[[/?advance_mode]]
			var is_aElm = /^<a [^>]+>[^<]+<\\/a>\$/.test(inst.selection.getContent());
			var linkattrs = {
				'href' : url
			};
			if(jQuery("input[type='checkbox'][name='newwindow']").is(":checked") == true){
				linkattrs.target = '_blank';
			}
			if (!is_aElm){
				inst.insertContent(inst.dom.createHTML('a', linkattrs, inst.selection.getContent()));
			} else {
				inst.execCommand('mceInsertLink', false, linkattrs);
			}
		} else {
			this.setAllAttribs(elm);
			inst.selection.select(elm);
		}
		// Don't move caret if selection was image
		inst.focus();
		inst.selection.select(elm);
		parent.tinymce.activeEditor.windowManager.close();
	},
[[?advance_mode]]
	getUrl : function(){
		switch(this.link_type){
		case 'imgdoc':
			return this.default_imgdoc;
			break;
		case 'page':
			return this.default_page;
			break;
		default:
			return this.default_url
			break;
		}
	},
	isImgDocObject : 0,
	default_url : '',
	default_page : '',
	default_imgdoc : '',
	default_lib : 0,
	link_type : '',
	enable_cms_op : [[enable_cms_cmd]],
	getLibraryList : function (){
		var list = getRequestData('[[dlg_file]]?action=getpagelist&id=' + document.forms.dialog_form.lib_id.value);
		document.getElementById('imageSelector').innerHTML = list;
	},
	selectMade : function () {
		var choice = document.forms.dialog_form.linkSelect.options[document.forms.dialog_form.linkSelect.selectedIndex];
		if (choice.value) {
			document.forms.dialog_form.linkURL.value = choice.value;
		}
	},
	selectLibrary : function (){
		this.isImgDocObject = 1;
		var choice = document.forms.dialog_form.obj_id.options[document.forms.dialog_form.obj_id.selectedIndex];
		if (choice.value){
			document.forms.dialog_form.linkURL.value = choice.value;
		}
	},
	resetType : function (){
		this.isImgDocObject = 0;
	},
	linktoUpdate : function (val){
		this.link_type = val || 'url';
		if (!this.enable_cms_op){
			this.link_type = 'url';
		}
		this.select_linkto_radio(this.link_type);
		switch(this.link_type){
		case 'imgdoc':
			document.getElementById('div_url').style.display = 'none';
			document.getElementById('div_internal_page').style.display = 'none';
			document.getElementById('div_image_document').style.display = 'block';
			document.forms.dialog_form.link_url.value = '';
			if (this.default_lib){
				for(var i = 0; i < document.forms.dialog_form.lib_id.length; i++){
					if (document.forms.dialog_form.lib_id.options[i].value == this.default_lib){
						document.forms.dialog_form.lib_id.selectedIndex = i;
						break;
					}
				}
			}
			this.getLibraryList();
			if (this.default_imgdoc){
				var selected_val = '\\[\\[' + this.default_imgdoc + '\\]\\]';
				for(var i = 0; i < document.forms.dialog_form.obj_id.length; i++){
					if (document.forms.dialog_form.obj_id.options[i].value == selected_val){
						document.forms.dialog_form.obj_id.selectedIndex = i;
						document.forms.dialog_form.linkURL.value = selected_val;
						break;
					}
				}
			}
			this.link_type = 'imgdoc';
			break;
		case 'page':
			document.getElementById('div_url').style.display = 'none';
			document.getElementById('div_image_document').style.display = 'none';
			document.getElementById('div_internal_page').style.display = 'block';
			document.forms.dialog_form.link_url.value = '';
			if (this.default_page){
				var selected_val = '{{' + this.default_page + '}}';
				for(var i = 0; i < document.forms.dialog_form.linkSelect.options.length; i++){
					if (document.forms.dialog_form.linkSelect.options[i].value == selected_val){
						document.forms.dialog_form.linkSelect.selectedIndex = i;
						document.forms.dialog_form.linkURL.value = selected_val;
						break;
					}
				}
			}
			this.link_type = 'page';
			break;
		default:
			document.getElementById('div_image_document').style.display = 'none';
			document.getElementById('div_internal_page').style.display = 'none';
			document.getElementById('div_url').style.display = 'block';
			document.forms.dialog_form.link_url.value = this.default_url || '';
			this.link_type = 'url';
			break;
		}
	},
	select_linkto_radio : function (radio_val){
		for(var i = 0; i < document.forms.dialog_form.link_to.length; i++){
			if (document.forms.dialog_form.link_to[i].value == radio_val){
				document.forms.dialog_form.link_to[i].checked = true;
			}else{
				if (!this.enable_cms_op){
					document.forms.dialog_form.link_to[i].disabled = true;
				}
				document.forms.dialog_form.link_to[i].checked = false;
			}
		}
		if (!this.enable_cms_op){
			var inactive_color = '#666666';
			document.getElementById("label_link_page").style.color = inactive_color;
			document.getElementById("label_link_imgdoc").style.color = inactive_color;
		}
	},
[[/?advance_mode]]
	init : function (){
		this.closeFlag = 0;
		var inst = parent.tinymce.activeEditor,elm,action,link_url;
		elm = inst.selection.getNode();
		a_elm = inst.dom.getParent(elm, 'a[href]');
		action = 'insert';
		if (elm != null && elm.nodeName == 'A'){
			action = "update";		
			if ((a_elm.target).match(/_blank/i)){
				document.forms.dialog_form.newwindow.checked = true;
			}
		}
		link_url = unescape(inst.dom.getAttrib(a_elm,'href'));
		if (action == "update"){
[[?advance_mode]]
			if (link_url.match(/content.cgi/i) || link_url.match(/^\\[(\\|)?\\[.+?\\](\\|)?\\]/)){
				if (link_url.match(/^\\[(\\|)?\\[.+?\\](\\|)?\\]/)){
					link_url.replace(eval(/\\|/g),'');
				}
				var ajax_imgdoc_url = '[[dlg_file]]?action=getcontentname&id=[[content_id]]&url=' + escape(link_url);
				var imgdoc_name = getRequestData(ajax_imgdoc_url);
			this.default_imgdoc = imgdoc_name;
				var fetch_lib_url = '[[dlg_file]]?action=getlib&id=[[content_id]]&name=' + this.default_imgdoc;
				this.default_lib = getRequestData(fetch_lib_url);
				this.linktoUpdate('imgdoc');
			}else if (link_url.match(/^\\{(\\|)?\\{.+?\\}(\\|)?\\}/)){
				var cms_page = link_url;
				cms_page = cms_page.replace(eval(/\\|/g),'');
				cms_page = cms_page.replace(eval('/^{{(.+?)}}\$/'),"\$1");
				var page_name;
				if (cms_page.match(/^\\d+\$/)){
					for (var x in pageref){
						if (pageref[x] == cms_page){
							page_name = x;
							break;
						}
					}
				}else{
					page_name = cms_page;
				}
				if (page_name){
					this.default_page = page_name;
					this.linktoUpdate('page');
				}else{
					this.linktoUpdate('url');
				}
			}else{
				this.default_url = link_url;
				this.linktoUpdate('url');
			}
[[/?advance_mode]]
[[!advance_mode]]
			document.forms.dialog_form.link_url.value = link_url;
[[/!advance_mode]]
		}
	}
};
jQuery(document).ready(function(){dlglnk.init();});
</script>
<body>
<form id="dialog_form" onsubmit="dlglnk.insertAction();return false;" action="#">
<div class="container">
[[?advance_mode]]
	<div class="form-group">
		<label>Type</label>
		<div class="radio">
			<label>
			<input type="radio" value="url" name="link_to" onclick="dlglnk.linktoUpdate('url')" checked><span id="label_link_uri">URL</span>
			</label>
		</div>
		<div class="radio">
			<label>
			<input type="radio" value="page" name="link_to" onclick="dlglnk.linktoUpdate('page')"><span id="label_link_page">Internal Page</span>
			</label>
		</div>
		<div class="radio">
			<label>
			<input type="radio" value="imgdoc" name="link_to" onclick="dlglnk.linktoUpdate('imgdoc')"><span id="label_link_imgdoc">Image/Document</span>
			</label>
		</div>
	</div>
[[/?advance_mode]]
	<div class="form-group">
		<label>To</label>
[[?advance_mode]]
		<div class="form-inline">
			<div id="div_internal_page" style="display: none;">
				<select class="form-control" name="linkSelect" onChange="dlglnk.selectMade()">[[select_internal_page]]</select>
			</div>
			<div id="div_image_document" style="display:none;">
				[[select_library]]
				<div id="imageSelector">
					<select class="form-control" name="obj_id"><option value="">== Select Image/Document ==</option></select>
				</div>
			</div>
		</div>
[[/?advance_mode]]
		<div id="div_url" style="display: block;">
			<input class="form-control" type="text" id="link_url" name="linkURL" value="[[url]]" size="50"[[?advance_mode]] onChange="dlglnk.resetType()"[[/?advance_mode]]>
		</div>
		<div class="checkbox">
			<input type="checkbox" name="newwindow"> Open this link in a new window
		</div>
	</div>
	<div class="form-group text-right">
		<button class="btn mce-btn mce-primary">Insert</button>
		<button class="btn btn-default active" onclick="dlglnk.close();">Cancel</button>
	</div>
</div>
</form>
</body>
</html>
END
	return ExSite::Misc::substitute($template,\%template_data);
}
1;
