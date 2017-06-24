tinymce.PluginManager.add('dlgmailto', function(editor, url) {
	function dialog(){
		editor.windowManager.open({
			title: 'Insert MailTo Link',
			body: [
				{type: 'textbox', name: 'mail', label: 'E-mail address'}
			],
			onsubmit: function(e) {
				editor.execCommand("mceInsertContent", false, '<img alt="MailTo(' + e.data.mail + ')" name="MailTo" src="' + editor.settings.plugin_mailto.plugin_img + '" title="MailTo" border="3" style="border-style:outset;">');
			}
		});
	}
	editor.addButton('e_dlgmailto', {
		image: editor.settings.plugin_mailto.img,
		tooltip: 'Insert MailTo Link',
		onclick: dialog
	});
});
