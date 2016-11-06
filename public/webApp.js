$(document).on('change', '.btn-file :file', function () {
    var input = $(this),
        numFiles = input.get(0).files ? input.get(0).files.length : 1,
        label = input.val().replace(/\\/g, '/').replace(/.*\//, '');
    input.trigger('fileselect', [numFiles, label]);
});

$(document).ready(function () {
	$('.images-cell').flip({trigger: 'manual'});
	
	$('.images-cell').on('flip:change', function(){
		$(this).flip('toggle');
	});

	$('.images-cell').click(function () {
		var excluded = [], img_cell = $(this),
			flip = img_cell.data("flip-model"),
			backside = img_cell.find('.' + (flip.isFlipped ? 'front' : 'back')),
			currside = img_cell.find('.' + (flip.isFlipped ? 'back' : 'front'));
		$('.image-id').each(function () {
			if ($(this).text().length > 0) {
				excluded.push(parseInt($(this).text(), 10));
			}
		});
		$.post(
			'/next-img/',
			{
				'excluded': JSON.stringify(excluded)
			},
			function (data) {
				if (data.error) {
					$.notify(data.error, {autoHide: true, autoHideDelay: 3000, style: 'bootstrap', className: 'error'});
				}
				else {
					currside.find('.image-id').empty();
					backside.find('.image-id').text(data['id']);
					backside.find('img').attr('src', data['url']);
					backside.find('.image-comment').text(data['comment']);
					if (flip.isFlipped) {
						img_cell.flip({reverse: true});
					}
					else {
						img_cell.flip({reverse: false});
					}
				}
			},
			"json"
		);
	});
	$('#refresh_type').change(function () {
		var ref_type = $(this).val();
		if (ref_type == 1) {
			$('#rand_number_div').hide();
			$('#upload_file_div').hide();
		}
		else if (ref_type == 2) {
			$('#rand_number_div').show();
			$('#upload_file_div').hide();
		}
		else if (ref_type == 3) {
			$('#rand_number_div').hide();
			$('#upload_file_div').show();
		}
	});
	
	$('.btn-file').each(function () {
        $(this).find("input[type='file']").on('fileselect', function () {
            if($(this)[0].files.length > 0) {
                $(this).parent().parent().find('span.btn-file-name').text($(this)[0].files[0].name);
            }
        });
    });
	
	$('#start_refreshing').click(function () {
		var ref_type = $('#refresh_type').val();
		if (ref_type == 1) {
			$(this).prop('disabled', true);
			$.post(
				'/refresh/default/',
				{'clear_db': $('#clear_db').is(':checked')},
				function (data) {
					if (data.error) {
						$.notify(data.error, {autoHide: true, autoHideDelay: 3000, style: 'bootstrap', className: 'error'});
					}
					else {
						window.location.replace('/');
					}
				},
				"json"
			);
		}
		else if (ref_type == 2) {
			var num_of_new = parseInt($('#rand_number').val());
			if (num_of_new < 10 || num_of_new > 1000000) {
				$.notify('Please select the number between 10 and 1,000,000', {autoHide: true, autoHideDelay: 3000, style: 'bootstrap', className: 'error'});
				return false;
			}
			else {
				$(this).prop('disabled', true);
				$.post(
					'/refresh/random/',
					{'number': num_of_new, 'clear_db': $('#clear_db').is(':checked')},
					function (data) {
						if (data.error) {
							$.notify(data.error, {autoHide: true, autoHideDelay: 3000, style: 'bootstrap', className: 'error'});
						}
						else {
							window.location.replace('/');
						}
					},
					"json"
				);
			}
		}
		else if (ref_type == 3) {
			var files = $('#csv_file_input')[0].files;
			if (files.length <= 0) {
				$.notify('Please choose csv file', {autoHide: true, autoHideDelay: 3000, style: 'bootstrap', className: 'error'});
				return false;
			}
			else {
				var data = new FormData();
				$(this).prop('disabled', true);
				data.append('file', files[0]);
				data.append('clear_db', $('#clear_db').is(':checked'));
				$.ajax({
					url: '/refresh/csv/',
					type: 'POST',
					data: data,
					dataType: 'json',
					contentType: false,
					processData: false,
					mimeType: 'multipart/form-data',
					xhr: function() {
						return $.ajaxSettings.xhr();
					},
					success: function (data) {
						if (data.error) {
							$.notify(data.error, {autoHide: true, autoHideDelay: 3000, style: 'bootstrap', className: 'error'});
						}
						else {
							window.location.replace('/');
						}
					}
				});
			}
		}
	});
	$('#text_for_clear_db').click(function() {
		var clear_checkbox = $('#clear_db');
		clear_checkbox.prop("checked", !clear_checkbox.prop("checked"));
	});
	
	$('#update_cache').click(function(){
		$.post(
			'/check-cache/',
			{},
			function (data) {
				if (data.error) {
					$.notify(data.error, {autoHide: true, autoHideDelay: 3000, style: 'bootstrap', className: 'error'});
				}
				else {
					$.notify("Everything is OK.", {autoHide: true, autoHideDelay: 3000, style: 'bootstrap', className: 'success'});
				}
			},
			"json"
		);
	});
});
