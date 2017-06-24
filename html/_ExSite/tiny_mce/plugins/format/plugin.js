tinymce.PluginManager.add('format', function(editor, url) {
	var b_items = new Array(
		{text: 'Header 1',value:'h1',textStyle:'font-weight:bold; font-size:2em;'},
		{text: 'Header 2',value:'h2',textStyle:'font-weight:bold; font-size:1.5em;'},
		{text: 'Header 3',value:'h3',textStyle:'font-weight:bold; font-size:1.3em;'},
		{text: 'Header 4',value:'h4',textStyle:'font-weight:bold; font-size:1em;'},
		{text: 'Header 5',value:'h5',textStyle:'font-weight:bold; font-size:0.8em;'},
		{text: 'Header 6',value:'h6',textStyle:'font-weight:bold; font-size:0.7em;'},
		{text: 'Paragraph',value:'p'},
		{text: 'Address',value:'address',textStyle: 'font-style:italic;'},
		{text: 'Preformatted',value:'pre',textStyle: 'white-space:pre;font-family:monospace;'},
		{text: 'Blockquote',value:'blockquote'},
		{text: 'DIV',value:'div'}
	);

	editor.addButton('block_format', {
		type : 'listbox',
		text : 'Block Format',
		tooltip : 'Block Format',
		fixedWidth: true,
		values : b_items,
		onPostRender : change_block(b_items),
		onselect : function(e){
			do_format_toolbar('block',e);
		}
	});

	var h_items = new Array(
		{text: 'Header 1',value:'h1',textStyle:'font-weight:bold; font-size:2em;'},
		{text: 'Header 2',value:'h2',textStyle:'font-weight:bold; font-size:1.5em;'},
		{text: 'Header 3',value:'h3',textStyle:'font-weight:bold; font-size:1.3em;'},
		{text: 'Header 4',value:'h4',textStyle:'font-weight:bold; font-size:1em;'},
		{text: 'Header 5',value:'h5',textStyle:'font-weight:bold; font-size:0.8em;'},
		{text: 'Header 6',value:'h6',textStyle:'font-weight:bold; font-size:0.7em;'}
	);

	editor.addButton('header_format', {
		type : 'listbox',
		text : 'Header',
		tooltip : 'Header',
		fixedWidth: true,
		values : h_items,
		onPostRender : change_block(h_items),
		onselect : function(e){
			do_format_toolbar('block',e);
		}
	});

	var i_items = new Array(
		{icon:'bold',text:'Bold',value:'strong'},
		{icon:'italic',text:'Italic',value:'em'},
		{icon:'strikethrough',text:'Strikethrough',value:'del'},
		{icon:'underline',text:'Underline',value:'ins'},
		{icon:'superscript',text:'Superscript',value:'sup'},
		{icon:'subscript',text:'Subscript',value:'sub',textStyle:'vertical-align: sub;font-size: smaller;'},
		{icon:'code',text:'Code',value:'code'},
		{text:'Abbrevation',value:'abbr'},
		{text:'Acronym',value:'acronym'},
		{text:'Cite',value:'cite'},
		{text:'Definition',value:'dfn'},
		{text:'Keyboard',value:'kbd'},
		{text:'Quote',value:'q'},
		{text:'Sample',value:'samp'},
		{text:'Variable',value:'var'}
	);

	editor.addButton('inline_format', {
		type : 'listbox',
		text : 'Inline Format',
		tooltip : 'Inline Format',
		fixedWidth: true,
		values : i_items,
		onPostRender : change_inline(i_items),
		onselect : function(e){
			do_format_toolbar('inline',e);
		}
	});
	editor.addMenuItem('e_inline',{
		text: 'Inline',
		context : 'format',
		menu : [
			{icon:'bold',text:'Bold',onclick: function() {do_format('inline','strong');}},
			{icon:'italic',text:'Italic', onclick: function() {do_format('inline','em');}},
			{icon:'strikethrough',text:'Strikethrough', onclick: function() {do_format('inline','del');}},
			{icon:'underline',text:'Underline', onclick: function() {do_format('inline','ins');}},
			{icon:'superscript',text:'Superscript', onclick: function() {do_format('inline','sup');}},
			{icon:'subscript',text:'Subscript', onclick: function() {do_format('inline','sub');},textStyle:'vertical-align: sub;font-size: smaller;'},
			{icon:'code',text:'Code', onclick: function() {do_format('inline','code');}},
			{text:'Abbrevation', onclick: function() {do_format('inline','abbr');}},
			{text:'Acronym', onclick: function() {do_format('inline','acronym');}},
			{text:'Cite', onclick: function() {do_format('inline','cite');}},
			{text:'Definition', onclick: function() {do_format('inline','dfn');}},
			{text:'Keyboard', onclick: function() {do_format('inline','kbd');}},
			{text:'Quote', onclick: function() {do_format('inline','q');}},
			{text:'Sample', onclick: function() {do_format('inline','samp');}},
			{text:'Variable', onclick: function() {do_format('inline','var');}}
		]
	});
	editor.addMenuItem('e_header',{
		text: 'Header',
		context : 'format',
		menu : [
			{text: 'Header 1', onclick: function() {do_format('block','h1');},textStyle:'font-weight:bold; font-size:2em;'},
			{text: 'Header 2', onclick: function() {do_format('block','h2');},textStyle:'font-weight:bold; font-size:1.5em;'},
			{text: 'Header 3', onclick: function() {do_format('block','h3');},textStyle:'font-weight:bold; font-size:1.3em;'},
			{text: 'Header 4', onclick: function() {do_format('block','h4');},textStyle:'font-weight:bold; font-size:1em;'},
			{text: 'Header 5', onclick: function() {do_format('block','h5');},textStyle:'font-weight:bold; font-size:0.8em;'},
			{text: 'Header 6', onclick: function() {do_format('block','h6');},textStyle:'font-weight:bold; font-size:0.7em;'}
		]
	});
	editor.addMenuItem('e_block',{
		text: 'Block',
		context : 'format',
		menu : [
			{text: 'Paragraph', onclick: function() {do_format('block','p');}},
			{text: 'Address', onclick: function() {do_format('block','address');},textStyle: 'font-style:italic;'},
			{text: 'Preformatted', onclick: function() {do_format('block','pre');},textStyle: 'white-space:pre;font-family:monospace;'},
			{text: 'Blockquote', onclick: function() {do_format('block','blockquote');}},
			{text: 'DIV', onclick: function() {do_format('block','div');}}
		]
	});
	function change_inline(items){
		return function(){
			var self = this;
			editor.on('click', function(e) {
				var value = null;
				for(var j = 0; j < items.length; j++){
					if (e.toElement.nodeName.toLowerCase() == items[j].value.toLowerCase()){
						value = items[j].value;
						break;
					}
				}
				if (value) {
					self.value(value);
				}else{
					self.value('');
				}
			});
		};
	}
	function change_block(items){
		return function(){
			var self = this;
			editor.on('nodeChange', function(e) {
				var value = null;
				for(var i = 0; i < e.parents.length; i++){
					if (value){
						break;
					}
					for(var j = 0; j < items.length; j++){
						if (e.parents[i].nodeName.toLowerCase() == items[j].value.toLowerCase()){
							value = items[j].value;
							break;
						}
					}
				}
				if (value) {
					self.value(value);
				}else{
					self.value("");
				}
			});
		};
	}
	function do_format_toolbar(type,e){
		var tag = e.control.settings.value;
		var elm = editor.dom.getParent(editor.selection.getNode()),s = editor.selection.getContent();
		if (/WebKit/.test(navigator.userAgent)){
			elm = editor.dom.getParent(editor.selection.getStart());
		}
		switch(type){
			case 'inline':
				editor.formatter.register(tag,{inline:tag});
				if (new String(elm.nodeName).toLowerCase() == tag){
					editor.formatter.toggle(new String(elm.nodeName).toLowerCase());
					return;
				}
				if (s){
					editor.formatter.apply(tag);
				}
				break;
			case 'block':
				if (new String(elm.nodeName).toLowerCase() == tag){
					editor.formatter.toggle(new String(elm.nodeName).toLowerCase());
					return;
				}
				if (!s || /<[a-z][\s\S]*>/i.test(s)){
					editor.formatter.apply(tag);
				}else{
					var ins = '<' + tag + '>' + s + '</' + tag + '>';
					editor.execCommand('mceInsertRawHTML',false,ins);
				}
				break;
			default:
				break;
		}
	}
	function do_format(type,tag){
		var elm = editor.dom.getParent(editor.selection.getNode()),s = editor.selection.getContent();
		if (/WebKit/.test(navigator.userAgent)){
			elm = editor.dom.getParent(editor.selection.getStart());
		}
		switch(type){
			case 'inline':
				editor.formatter.register(tag,{inline:tag});
				if (new String(elm.nodeName).toLowerCase() == tag){
					editor.formatter.toggle(new String(elm.nodeName).toLowerCase());
					return;
				}
				if (s){
					editor.formatter.apply(tag);
				}
				break;
			case 'block':
				if (new String(elm.nodeName).toLowerCase() == tag){
					editor.formatter.toggle(new String(elm.nodeName).toLowerCase());
					return;
				}
				if (!s || /<[a-z][\s\S]*>/i.test(s)){
					editor.formatter.apply(tag);
				}else{
					var ins = '<' + tag + '>' + s + '</' + tag + '>';
					editor.execCommand('mceInsertRawHTML',false,ins);
				}
				break;
			default:
				break;
		}
	}


	// text alignment
	editor.addMenuItem('e_align',{
		text: 'Alignment',
		context : 'format',
		menu : [
			{text: 'Left', icon: 'alignleft', format: 'alignleft',onclick:function(){editor.formatter.apply('alignleft');}},
			{text: 'Center', icon: 'aligncenter', format: 'aligncenter',onclick:function(){editor.formatter.apply('aligncenter');}},
			{text: 'Right', icon: 'alignright', format: 'alignright',onclick:function(){editor.formatter.apply('alignright');}},
			{text: 'Justify', icon: 'alignjustify', format: 'alignjustify',onclick:function(){editor.formatter.apply('alignjustify');}}
		]
	});
	
	var indent = new Array(
		{name:'e_outdent',label:'Decrease indent',cmd:'Outdent',icon:'outdent'},
		{name:'e_indent',label:'Increase indent',cmd:'Indent',icon:'indent'}
	);
	for(var i = 0; i < indent.length; i++){
		var itm = indent[i];
		editor.addMenuItem(itm.name, {
			text: itm.label,
			tooltip: itm.label,
			icon: itm.icon,
			cmd: itm.cmd
		});
	}

	// font selector
	var defaultFontsFormats =
		'Andale Mono=andale mono,times;' +
		'Arial=arial,helvetica,sans-serif;' +
		'Arial Black=arial black,avant garde;' +
		'Book Antiqua=book antiqua,palatino;' +
		'Comic Sans MS=comic sans ms,sans-serif;' +
		'Courier New=courier new,courier;' +
		'Georgia=georgia,palatino;' +
		'Helvetica=helvetica;' +
		'Impact=impact,chicago;' +
		'Symbol=symbol;' +
		'Tahoma=tahoma,arial,helvetica,sans-serif;' +
		'Terminal=terminal,monaco;' +
		'Times New Roman=times new roman,times;' +
		'Trebuchet MS=trebuchet ms,geneva;' +
		'Verdana=verdana,geneva;' +
		'Webdings=webdings;' +
		'Wingdings=wingdings,zapf dingbats';
	var flist = editor.settings.font_formats || defaultFontsFormats;
	var formats = flist.split(';');
	var i = formats.length;
	while (i--) {
		formats[i] = formats[i].split('=');
	}
	var fs_items = [];
	for(var i = 0; i < formats.length; i++){
		var font = formats[i];
		fs_items.push({
			text: {raw: font[0]},
			value: font[1],
			textStyle: font[1].indexOf('dings') == -1 ? 'font-family:' + font[1] : ''
		});
	}
	editor.addMenuItem('e_fontselect',{
		text: 'Font Family',
		menu: fs_items,
		fixedWidth: true,
		onselect: function(e) {
			if (e.control.settings.value) {
				editor.execCommand('FontName', false, e.control.settings.value);
			}
		}
	});

	var ff_items = [];
	var fontsize_formats = editor.settings.fontsize_formats || '8pt 10pt 12pt 14pt 18pt 24pt 36pt';
	var f_format = fontsize_formats.split(' ');
	for(var i = 0; i < f_format.length; i++){
		ff_items.push({text: f_format[i], value: f_format[i]});
	}
	editor.addMenuItem('e_fontsizeselect',{
			text: 'Font Sizes',
			menu: ff_items,
			fixedWidth: true,
			onclick: function(e) {
				if (e.control.settings.value) {
					editor.execCommand('FontSize', false, e.control.settings.value);
				}
			}
	});

	// list
	var olMenuItems, ulMenuItems, lastStyles = {};
	function buildMenuItems(listName, styleValues) {
		var items = [];
		tinymce.each(styleValues.split(/[ ,]/), function(styleValue) {
			items.push({
				text: styleValue.replace(/\-/g, ' ').replace(/\b\w/g, function(chr) {return chr.toUpperCase();}),
				data: styleValue == 'default' ? '' : styleValue
			});
		});
		return items;
	}
	olMenuItems = buildMenuItems('OL', editor.getParam(
		"advlist_number_styles",
		"default,lower-alpha,lower-greek,lower-roman,upper-alpha,upper-roman"
	));
	ulMenuItems = buildMenuItems('UL', editor.getParam("advlist_bullet_styles", "default,circle,disc,square"));
	function applyListFormat(listName, styleValue) {
		var list, dom = editor.dom, sel = editor.selection;
		// Check for existing list element
		list = dom.getParent(sel.getNode(), 'ol,ul');
		// Switch/add list type if needed
		if (!list || list.nodeName != listName || styleValue === false) {
			editor.execCommand(listName == 'UL' ? 'InsertUnorderedList' : 'InsertOrderedList');
		}
		// Set style
		styleValue = styleValue === false ? lastStyles[listName] : styleValue;
		lastStyles[listName] = styleValue;
		list = dom.getParent(sel.getNode(), 'ol,ul');
		if (list) {
			dom.setStyle(list, 'listStyleType', styleValue);
			list.removeAttribute('data-mce-style');
		}
		editor.focus();
	}
	function updateSelection(e) {
		var listStyleType = editor.dom.getStyle(editor.dom.getParent(editor.selection.getNode(), 'ol,ul'), 'listStyleType') || '';
		e.control.items().each(function(ctrl) {
			ctrl.active(ctrl.settings.data === listStyleType);
		});
	}
	editor.addMenuItem('e_numlist', {
		text: 'Numbered list',
		icon: 'numlist',
		menu: olMenuItems,
		onshow: updateSelection,
		onselect: function(e) {
			applyListFormat('OL', e.control.settings.data);
		}
	});
	editor.addMenuItem('e_bullist', {
		text: 'Bullet list',
		icon: 'bullist',
		menu: ulMenuItems,
		onshow: updateSelection,
		onselect: function(e) {
			applyListFormat('UL', e.control.settings.data);
		}
	});

	var special = new Object();
	if (editor.settings.exsite_style_formats){
		var flist = editor.settings.exsite_style_formats.split(';');
		var fobj = new Array();
		for(var i = 0; i < flist.length; i++){
			var _list = flist[i].split('=');
			fobj.push({title: _list[0],classes: _list[1]});
		}
		var elist = new Object();
		var s_menu = new Array();
		for(var i = 0; i < fobj.length; i++){
			var fmt = fobj[i],_t;
			_t = fmt.title;
			special[_t] = {text: fmt.title,classes: fmt.classes};
			s_menu.push({text: special[_t].text, onclick: (function(_t) {return function(){do_special(_t);}})(_t)});
		}
		editor.addMenuItem('e_special',{
			text: 'Special',
			context : 'format',
			menu : s_menu
		});
	}
	function do_special(style){
		editor.formatter.register(special[style].text,{inline: 'span',classes: special[style].classes});
		editor.formatter.apply(special[style].text);
	}
});
