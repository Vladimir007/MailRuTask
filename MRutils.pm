package MRutils;
use strict;
use warnings;
use Exporter;
use Data::Dumper;
use DBI;
use utf8;
use lib qw(..);
use JSON qw();

our @ISA= qw( Exporter );

our @EXPORT_OK = qw( clear_db fill_test_data fill_rand_data recalculate_cache get_random_images add_elements disconnec_from_db);

our @EXPORT = qw();


our $dbconf_file = q{dbconf.json};
our $dbh;

# Connect to DB and create tables if they don't exist
{
	my @tables = (
		q{CREATE TABLE IF NOT EXISTS groups (
			id serial PRIMARY KEY,
			min_w real NOT NULL,
			max_w real NOT NULL,
			cnt integer NOT NULL
		)},
		q{CREATE TABLE IF NOT EXISTS images (
			id serial PRIMARY KEY,
			group_id integer REFERENCES groups (id) ON UPDATE NO ACTION ON DELETE SET NULL,
			weight real NOT NULL,
			url character varying(1000) NOT NULL,
			comment character varying(20)
		)}
	);
	my $json_text = do {
	   open(my $json_fh, q{<:encoding(UTF-8)}, $dbconf_file) or die qq{Can't open "$dbconf_file": $!};
	   local $/;
	   <$json_fh>
	};
	my $json = JSON->new;
	my $db_data = $json->decode($json_text);

	my @required = ('name', 'passwd', 'name', 'host', 'port');
	foreach (@required) {
		die if not defined $db_data->{$_};
	}
	$dbh = DBI->connect(
		qq{dbi:Pg:dbname=$db_data->{name};host=$db_data->{host};port=$db_data->{port}},
		$db_data->{user}, $db_data->{passwd}, {PrintError => 0}
	) or die qq{Can't connect to database: $DBI::errstr!};
	foreach my $table (@tables) {
		$dbh->do($table);
		$DBI::err && die $DBI::errstr;
	}
}

sub insert_query {
	my $sql = shift;
	my $sth = $dbh->prepare_cached($sql) or die q{Couldn't prepare statement: } . $dbh->errstr;
	my $rv = $sth->execute(@_) or die q{Couldn't execute statement: } . $sth->errstr;
}

sub select_query {
	my $sql = shift;
	my $sth = $dbh->prepare_cached($sql) or die q{Couldn't prepare statement: } . $dbh->errstr;
	my $rv = $sth->execute(@_) or die q{Couldn't execute statement: } . $sth->errstr;
	return $sth;
}

sub update_query {
	my $sql = shift;
	$dbh->do($sql, undef, @_) or die q{Couldn't do statement: } . $dbh->errstr;
}

sub separate_group {
	my ($group_id, $separator, $group) = @_;
	
	# Get all images of the current group with weight > $separator
	my %images_ids;
	my $sth = select_query(q{SELECT id FROM images WHERE group_id=? AND weight>?}, $group_id, $separator);
	my $num_of_images = $sth->rows;
	while(my @image = $sth->fetchrow_array()) {
		undef $images_ids{$image[0]};
	}
	
	# Update the separated group: set max_w=$separator
	# and cnt to number of images with weight <= $separator
	update_query(q{UPDATE groups SET cnt=?, max_w=? WHERE id=?}, ($group->[2] - $num_of_images), $separator, $group_id);

	# Create new group with min_w = $separator and max_w is max_w of the separated group
	insert_query(q{INSERT INTO groups (min_w, max_w, cnt) VALUES (?, ?, ?)}, $separator, $group->[1], $num_of_images);
	my $new_group_id = $dbh->last_insert_id(undef, undef, q{groups}, undef);
	if ($num_of_images > 0) {
		# Connect new group with appropriate images
		update_query(
			qq{UPDATE images SET group_id=? WHERE id IN (@{[join',', ('?') x keys %images_ids]})},
			$new_group_id, keys %images_ids
		);
	}
	return [$new_group_id, $separator, $group->[1], $num_of_images];
}

sub fill_groups {
	my ($offset, $elements, $elements_in_db_ref, $groups) = @_;
	my %elements_in_db = %$elements_in_db_ref;
	my %groups_to_update;

	# For each element index in @elements array
	foreach my $el_id ($offset..@$elements - 1) {
		# Try to find group where image with index $el_id has weight between min_w and max_w.
		my $group_id;
		foreach my $i (keys %$groups) {
			if ($groups->{$i}->[0] < $elements->[$el_id]->[1] and $elements->[$el_id]->[1] <= $groups->{$i}->[1]) {
				$group_id = $i;
				last;
			}
		}
		
		# This means that there are no groups in DB yet. We will create group that will include all images
		# But if there are no groups than there are no images accosiated with groups.
		# So the new group will contain just 1 image.
		if (not defined $group_id) {
			insert_query(q{INSERT INTO groups (min_w, max_w, cnt) VALUES (?, ?, ?)}, 0, 1, 1);
			my $new_group_id = $dbh->last_insert_id(undef, undef, q{groups}, undef);
			$groups->{$new_group_id} = [0, 1, 1];
			update_query(q{UPDATE images SET group_id=? WHERE id=?}, $new_group_id, $elements_in_db{$el_id});
			# Next fill_groups() will be continued from the second image
			return 1;
		}
		else {
			# Check if number of elements in group differs from number of groups not more than 20%
			if ($groups->{$group_id}->[2] > 1.2 * scalar keys %$groups) {
				# Too many elements in group. We will divide this group by 2.
				# Separator is weight of new image if it is strictly between (min_w, max_w).
				# Otherwise its value is median of min_w, max_w.
				my $separator = $elements->[$el_id]->[1];
				if ($separator == $groups->{$group_id}->[1]) {
					$separator = 0.5 * ($groups->{$group_id}->[0] + $groups->{$group_id}->[1]);
				}
				# Update groups in DB before separation
				foreach my $group_id (keys %groups_to_update) {
					update_query(q{UPDATE groups SET cnt=? WHERE id=?}, $groups->{$group_id}->[2], $group_id);
					update_query(
						qq{UPDATE images SET group_id=? WHERE id IN(@{[join',', ('?') x @{$groups_to_update{$group_id}}]})},
						$group_id, @{$groups_to_update{$group_id}}
					);
				}
				# Divide the group by 2.
				my $new_group = separate_group($group_id, $separator, $groups->{$group_id});
				# Update groups hash
				$groups->{$group_id}->[1] = $separator;
				$groups->{$group_id}->[2] = $groups->{$group_id}->[2] - $new_group->[3];
				$groups->{$new_group->[0]} = [$new_group->[1], $new_group->[2], $new_group->[3]];
				# We have just separated the group, but didn't add current image to new group,
				# so we continue fill_group from this image.
				return $el_id;
			}
			else {
				# Increase number of elements in group and add it to set of groups "to update"
				$groups->{$group_id}->[2]++;
				if (exists $groups_to_update{$group_id}) {
					push @{$groups_to_update{$group_id}}, $elements_in_db{$el_id};
				}
				else {
					$groups_to_update{$group_id} = [$elements_in_db{$el_id}];
				}
			}
		}
	}
	# Update groups in DB
	foreach my $group_id (keys %groups_to_update) {
		update_query(q{UPDATE groups SET cnt=? WHERE id=?}, $groups->{$group_id}->[2], $group_id);
		update_query(
			qq{UPDATE images SET group_id=? WHERE id IN(@{[join',', ('?') x @{$groups_to_update{$group_id}}]})},
			$group_id, @{$groups_to_update{$group_id}}
		);
	}
	# Just finish calling fill_groups() due to all images are in groups already.
	return scalar @$elements;
}

sub add_elements {
	my $elements = shift;
	my %elements_in_db;
	{
		$dbh->{AutoCommit} = 0;
		my $sth = $dbh->prepare(q{INSERT INTO images (url, weight, comment) VALUES (?, ?, ?)})
			or die q{Couldn't prepare statement: } . $dbh->errstr;
		foreach my $el_id (0..@$elements - 1) {
			if ($elements->[$el_id]->[1] <= 0) {
				$elements->[$el_id]->[1] = 0.01;
			}
			elsif ($elements->[$el_id]->[1] > 1) {
				$elements->[$el_id]->[1] = 1.0;
			}
			$sth->execute(@{$elements->[$el_id]}[0..2])
				or die q{Couldn't execute statement: } . $sth->errstr;
			$elements_in_db{$el_id} = $dbh->last_insert_id(undef, undef, q{images}, undef)
				or die q{Can't find last insert id};
		}
		$sth->finish;
		$dbh->{AutoCommit} = 1;
	}
	my $offset = 0;
	my %groups;
	
	# Selecting all groups from DB and fill %groups with values.
	{
		my $sth = select_query(q{SELECT id, min_w, max_w, cnt FROM groups});
		while(my @group = $sth->fetchrow_array()) {
			$groups{$group[0]} = [$group[1], $group[2], $group[3]];
		}
	}
	while (scalar @$elements > $offset) {
		$offset = fill_groups($offset, $elements, \%elements_in_db, \%groups);
	}
}

sub recalculate_cache {
	my %groups_data;
	my $error_msg;
	my $sth = select_query(q{SELECT id, min_w, max_w, cnt FROM groups});
	while(my @group = $sth->fetchrow_array()) {
		my $sth_im = select_query(q{SELECT id, group_id FROM images WHERE weight>? AND weight<=?}, $group[1], $group[2]);
		if ($group[3] != $sth_im->rows) {
			$error_msg = qq{Cache was wrong: the number of images in group $group[0] is wrong};
		}
		while(my @image = $sth_im->fetchrow_array()) {
			if ($image[1] != $group[0]) {
				$error_msg = qq{Cache was wrong: image $image[0] had wrong group: $image[1] ($group[0] expected)};
			}
			if (exists $groups_data{$group[0]}) {
				push @{$groups_data{$group[0]}}, $image[0];
			}
			else {
				$groups_data{$group[0]} = [$image[0]];
			}
		}
	}
	# Update DB if error found only
	if ($error_msg) {
		foreach my $group_id (keys %groups_data) {
			update_query(q{UPDATE groups SET cnt=? WHERE id=?}, scalar @{$groups_data{$group_id}}, $group_id);
			update_query(
				qq{UPDATE images SET group_id=? WHERE id IN(@{[join',', ('?') x @{$groups_data{$group_id}}]})},
				$group_id, @{$groups_data{$group_id}}
			);
		}
	}
	return $error_msg;
}

sub get_random_groups {
	my $num_of_images = shift;
	my $excluded_images = shift;
	my @groups_data;
	my $sth = select_query(q{SELECT id, min_w, max_w, cnt FROM groups WHERE cnt>0});
	while(my @group = $sth->fetchrow_array()) {
		push @groups_data, \@group;
	}

	# Exclude some elements from groups
	my %excl_iig;
	if (scalar keys %$excluded_images > 0) {
		my $sth = select_query(qq{SELECT group_id FROM images WHERE id IN(@{[join',', ('?') x keys %$excluded_images]})}, keys %$excluded_images);
		while (my @img = $sth->fetchrow_array()) {
			if (exists $excl_iig{$img[0]}) {
				$excl_iig{$img[0]} += 1;
			}
			else {
				$excl_iig{$img[0]} = 1;
			}
		}
	}
	for my $group (@groups_data) {
		if (exists $excl_iig{$group->[0]}) {
			$group->[3] -= $excl_iig{$group->[0]};
			$group->[3] = 0 if $group->[3] < 0;
		}
	}

	my %group_ids;
	for my $i (1..$num_of_images) {
		my $line_len = 0;
		for my $group (@groups_data) {
			$line_len += 0.5 * ($group->[1] + $group->[2]) * $group->[3];
		}
		$line_len == 0 and die q{There are no so many images in the DB as you want};
		my $rand_point = rand($line_len);
		$line_len = 0;
		for my $group (@groups_data) {
			$line_len += 0.5 * ($group->[1] + $group->[2]) * $group->[3];
			if ($rand_point <= $line_len) {
				if (exists $group_ids{$group->[0]}) {
					$group_ids{$group->[0]}++;
				}
				else {
					$group_ids{$group->[0]} = 1;
				}
				$group->[3]--;
				last;
			}
		}
	}
	return %group_ids;
}

sub rand_weight {
	my ($weights, $excluded) = @_;
	my $line_len = 0;
	for my $w_id (0..@$weights - 1) {
		if (not exists $excluded->{$w_id}) {
			$line_len += $weights->[$w_id];
		}
	}
	my $rand_point = rand($line_len);
	$line_len = 0;
	for my $w_id (0..@$weights - 1) {
		if (not exists $excluded->{$w_id}) {
			$line_len += $weights->[$w_id];
			if ($line_len >= $rand_point) {
				return $w_id;
			}
		}
	}
	# Wrong! Last weight can be excluded. But this will never happen.
	return (@$weights - 1);
}

sub get_random_images {
	my $num_of_images = shift;
	my $excluded_images = shift;

	my %groups = get_random_groups($num_of_images, $excluded_images);
	
	my %images_data;
	my $sql = 'SELECT id, weight, group_id FROM images WHERE group_id IN(' . join(',', keys %groups) . ')';
	if (scalar keys %$excluded_images > 0) {
		$sql .=  'AND id NOT IN(' . join(',', keys %$excluded_images) . ')';
	}
	my $sth = select_query($sql);
	while(my @image = $sth->fetchrow_array()) {
		if (exists $images_data{$image[2]}) {
			push @{$images_data{$image[2]}}, \@image;
		}
		else {
			$images_data{$image[2]} = [\@image];
		}
	}

	my @images_ids;
	foreach my $gr_id (keys %images_data) {
		my @weights;
		my %excluded;
		foreach my $image (@{$images_data{$gr_id}}) {
			push @weights, $image->[1];
		}
		for (1..$groups{$gr_id}) {
			my $rand_im_index = rand_weight(\@weights, \%excluded);
			undef $excluded{$rand_im_index};
			push @images_ids, $images_data{$gr_id}->[$rand_im_index]->[0];
		}
	}

	my @random_images;
	if (scalar @images_ids > 0) {
		$sth = select_query(qq{SELECT id, url, comment FROM images WHERE id IN(@{[join',', ('?') x @images_ids]})}, @images_ids);
		while(my @image = $sth->fetchrow_array()) {
			push @random_images, \@image;
		}
	}
	else {
		die q{Not enough images to show};
	}
	return @random_images;
}

sub clear_db {
	$dbh->do('DELETE FROM groups');
	$DBI::err && die $DBI::errstr;
	$dbh->do('DELETE FROM images');
	$DBI::err && die $DBI::errstr;
}

sub fill_rand_data {
	my $num_of_images = shift;
	my @test_images;
	for my $i(1..$num_of_images) {
		my $rand_weight = int(rand(1000))/1000;
		push @test_images, [q{http://sait-zaika.ru/images/images_content/raskraski/raskraski_dlya_2-3_let/2.jpg}, $rand_weight, "$i"];
	}
	add_elements(\@test_images);
}

sub fill_test_data {
	my @test_images;
	my $file = 'default.csv';
	open(my $data, '<', $file)
		or die qq{Could not open '$file' $!};
 
	while (my $line = <$data>) {
		chomp $line;
		my @fields = split q{;}, $line;
		push @test_images, \@fields;
	}
	add_elements(\@test_images);
}

sub disconnect_from_db {
	$dbh->disconnect();
}

1;
