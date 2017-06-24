tinymce.PluginManager.add('dlgimg', function(editor, url) {
	function dialog(){
		function onSubmit(e){
			// Insert content when the window form is submitted
			editor.insertContent(e.data.title);
		}
		
		editor.windowManager.open({
				title: 'Insert Image',
				inline: 1,
				flex: 1,
				width: editor.settings.plugin_image.width,
				height: editor.settings.plugin_image.height,
				resizable: true,
				maximizable: true,
				url : editor.settings.plugin_image.url,
				onsubmit: onSubmit
			});
	}
	
	// Add a button that opens a window
	editor.addButton('e_dlgimg', {
		text: '',
		tooltip: 'Insert Image',
		icon: 'image',
		onclick: dialog
	});

	// Adds a menu item to the tools menu
	editor.addMenuItem('e_dlgimg', {
		text: 'Insert Image',
		icon: 'image',
		context: 'tools',
		onclick: dialog
	});
});
