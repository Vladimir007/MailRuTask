use Try::Tiny;
use Mojolicious::Lite;
use MRutils qw(clear_db fill_test_data fill_rand_data recalculate_cache get_random_images add_elements);
use JSON qw();
use Data::Dumper;

push @{app->static->paths} => app->home->rel_dir('public');

get '/' => sub {
	my $c = shift;
	my $row = $c->param('N') || 1;
	my $col = $c->param('M') || 1;
	my $num_of_rand_img = $row * $col;
	my $error_message;
	my @images_table;
	try {
		my @rand_images = get_random_images($num_of_rand_img);
		foreach my $i (0..$col-1) {
			my @row_images;
			foreach my $j (0..$row-1) {
				push @row_images, pop @rand_images;
			}
			push @images_table, \@row_images;
		}
	} catch {
		$error_message = $_;
	};
	$c->render(template => 'base', title => 'Mail Ru task', images => \@images_table, error_message => $error_message);
};

post '/next-img/' => sub {
	my $c = shift;
	my $json = JSON->new;
	my %data;
	my %excluded = map { $_ => undef } @{$json->decode($c->req->params->to_hash->{excluded})};
	try {
		my @images = get_random_images(1, \%excluded);
		my $img = $images[0];
		%data = (
			id => $img->[0],
			url => $img->[1],
			comment => $img->[2]
		);
	} catch {
		%data = (error => $_);
	};
	$c->render(json => \%data);
};

get '/refresh' => sub {
	my $c = shift;
	$c->render(template => 'refresh', title => 'Database refreshing');
};

post '/refresh/default/' => sub {
	my $c = shift;
	my %data;
	try {
		if ($c->param('clear_db') eq 'true') {
			clear_db();
		}
		fill_test_data();
	}
	catch {
		$data{error} = "$_";
	};
	$c->render(json => \%data);
};

post '/refresh/random/' => sub {
	my $c = shift;
	my %data;
	try {
		if ($c->param('clear_db') eq 'true') {
			clear_db();
		}
		fill_rand_data($c->param('number'));
	}
	catch {
		$data{error} = "$_";
	};
	$c->render(json => \%data);
};

post '/refresh/csv/' => sub {
	my $c = shift;
	my %data;
	my @images;
	try {
		foreach my $line (split("\n", $c->req->upload('file')->slurp)) {
			my @fields = split ";" , $line;
			push @images, \@fields;
		}
		if ($c->param('clear_db') eq 'true') {
			clear_db();
		}
		add_elements(\@images);
	}
	catch {
		$data{error} = "$_";
	};
	$c->render(json => \%data);
};

post '/check-cache/' => sub {
	my $c = shift;
	my %data;
	try {
		my $err_msg = recalculate_cache();
		$data{error} = $err_msg if $err_msg;
	}
	catch {
		$data{error} = "$_";
	};
	$c->render(json => \%data);
};

app->start;


__DATA__
@@not_found.html.ep

<!DOCTYPE html>
<html>
	<head>
		<meta charset="UTF-8">
		<meta http-equiv="X-UA-COMPATIBLE" content="IE=edge">
		<meta name="viewport" content="width=device-width, initial-scale=1">
		<meta name="description" content="Mail ru task">
		<meta name="author" content="Vladimir Gratinskii">
        <link rel="icon" href="/images/icon.ico">
		<title>Not found</title>
	</head>
	<body>
		<h1 style="color: red;">Page was not found</h1>
	</body>
</html>

@@not_found.development.html.ep

<!DOCTYPE html>
<html>
	<head>
		<meta charset="UTF-8">
		<meta http-equiv="X-UA-COMPATIBLE" content="IE=edge">
		<meta name="viewport" content="width=device-width, initial-scale=1">
		<meta name="description" content="Mail ru task">
		<meta name="author" content="Vladimir Gratinskii">
        <link rel="icon" href="/images/icon.ico">
		<title>Not found</title>
	</head>
	<body>
		<h1 style="color: red;">Page was not found</h1>
	</body>
</html>

@@exception.html.ep

<!DOCTYPE html>
<html>
	<head>
		<meta charset="UTF-8">
		<meta http-equiv="X-UA-COMPATIBLE" content="IE=edge">
		<meta name="viewport" content="width=device-width, initial-scale=1">
		<meta name="description" content="Mail ru task">
		<meta name="author" content="Vladimir Gratinskii">
        <link rel="icon" href="/images/icon.ico">
		<title>Not found</title>
	</head>
	<body>
		<h1 style="color: red;">Page was not found</h1>
	</body>
</html>

@@exception.development.html.ep

<!DOCTYPE html>
<html>
	<head>
		<meta charset="UTF-8">
		<meta http-equiv="X-UA-COMPATIBLE" content="IE=edge">
		<meta name="viewport" content="width=device-width, initial-scale=1">
		<meta name="description" content="Mail ru task">
		<meta name="author" content="Vladimir Gratinskii">
        <link rel="icon" href="/images/icon.ico">
		<title>Not found</title>
	</head>
	<body>
		<h1 style="color: red;">Page was not found</h1>
	</body>
</html>
