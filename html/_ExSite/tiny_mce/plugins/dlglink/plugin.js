tinymce.PluginManager.add('dlglink', function(editor, url) {
	function dialog(){
		editor.windowManager.open({
				title: 'Insert Link',
				text : 'Insert Link',
				inline: 1,
				flex: 1,
				width: editor.settings.plugin_link.width,
				height: editor.settings.plugin_link.height,
				resizable: true,
				maximizable: true,
				url : editor.settings.plugin_link.url
			});
	}
	// Add a button that opens a window
	editor.addButton('e_dlglink', {
		tooltip: 'Insert Link',
		text: '',
		icon: 'link',
		stateSelector: 'a[href]',
		onclick: dialog
	});
	// Add a button that opens a window
	editor.addButton('e_dlglink_unlink', {
		tooltip: 'Remove Link',
		text: '',
		icon: 'unlink',
		stateSelector: 'a[href]',
		onclick: function(){
			editor.execCommand("unlink");
		}
	});
	// Adds a menu item to the tools menu
	editor.addMenuItem('e_dlglink', {
		text: 'Insert Link',
		icon: 'link',
		context: 'insert',
		onclick: dialog
	});
	// Adds a menu item to the tools menu
	editor.addMenuItem('e_dlglink_unlink', {
		text: 'Remove Link',
		icon: 'unlink',
		context: 'insert',
		onclick: function(){
			editor.execCommand("unlink");
		}
	});
});
