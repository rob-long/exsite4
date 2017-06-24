tinymce.PluginManager.add('dlgdyn', function(editor, url) {
	function dialog(){
		function onSubmit(e){
			// Insert content when the window form is submitted
			editor.insertContent(e.data.title);
		}
		editor.windowManager.open({
				title: 'Insert Application',
				text : 'Insert Application',
				inline: 1,
				flex: 1,
				width: editor.settings.plugin_dyncontent.width,
				height: editor.settings.plugin_dyncontent.height,
				resizable: true,
				maximizable: true,
				url : editor.settings.plugin_dyncontent.url,
				onsubmit: onSubmit
			});
	}
	
	// Add a button that opens a window
	editor.addButton('e_dlgdyn', {
		text: '',
		tooltip: 'Insert Application',
		image: editor.settings.plugin_dyncontent.img,
		icon: 'dlgdyn',
		onclick: dialog
	});

	// Adds a menu item to the tools menu
	editor.addMenuItem('e_dlgdyn', {
		text: 'Insert Application',
		image: editor.settings.plugin_dyncontent.img,
		icon: 'dlgdyn',
		context: 'tools',
		onclick: dialog
	});
});
