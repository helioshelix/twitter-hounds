#!/usr/bin/perl -w
use strict;
use warnings;

use Cwd ();
use File::Basename ();
use YAML::Tiny ();

use List::Util ('shuffle');
use Math::Random::Secure ('irand');

use Net::Twitter;
use Net::Twitter::Error;
use Scalar::Util ('blessed', 'reftype');

use Getopt::Long ('GetOptionsFromString', ':config', 'no_auto_abbrev');

use POSIX 'ceil';

use Image::Info ('image_info');
use String::Random ('random_regex');

use LWP::UserAgent;

use Text::ASCIITable ();

use Win32::Console::ANSI;
use Term::ANSIColor (':constants');
$Term::ANSIColor::AUTORESET = 1;

use Data::Dumper;
$Data::Dumper::Sortkeys=1;
$Data::Dumper::Terse=1;
$Data::Dumper::Quotekeys=0;
$|=1;


sub cd(;$);
sub get_cwd;
sub read_conf(@);

sub fetch($$$);

sub longest(@);
sub random($$);

sub get_img_data($);

sub lookup_user_info($@);
sub read_lines($);

unless(@ARGV){
	&show_help(0);
	exit;
}

cd;
my $main_dir = get_cwd;
my $div = '-' x 150;
my $throttled = 0;

my %options = (
	account_info => 0,
	bot_files => [],
	clear_tweets => 0,
	creds => 0,
	dirs => undef,
	dump_conf => 0,
	examples => 0,
	follow_people => [],
	follow_followers => 0,
	help => 0,
	hide_progress => 0,
	logins => 0,
	lookup_users => undef,
	names => 0,
	pause => 0,
	proxy => undef,
	suspended => 0,
	suspended_files => [],
	throttle => -1,
	update_background_image => undef,
	update_banner_image => undef,
	update_profile_colors => 0,
	verify => 0,
	whitelist => [],
);

my $args = join(' ', @ARGV);
my ($arg_ret, $arg_rem) = GetOptionsFromString($args, (
	"aci|account-info" => \$options{account_info},
	"c|creds" 	=> \$options{creds},
	"ct|clear-tweets" => \$options{clear_tweets},
	"d|dirs=s" 	=> \@{$options{dirs}},
	"e|examples" 	=> \$options{examples},
	"dp|dump" 	=> \$options{dump_conf},
	"f|file=s" 	=> \@{$options{bot_files}},
	"ff|follow-followers" => \$options{follow_followers},
	"fp|follow-people=s"	=> \@{$options{follow_people}},
	"h|help" 	=> \$options{help},
	"hp|hide-progress" 	=> \$options{hide_progress},
	"l|logins" 	=> \$options{logins},
	"lu|lookup-users=s" => \$options{lookup_users},
	"n|names"   => \$options{names},
	"p|pause" 	=> \$options{pause},
	"px|proxy=s" => \$options{proxy},
	"ss|suspended" => \$options{suspended},
	"sf|suspended-file=s" => \@{$options{suspended_files}},
	"th|throttle=i" => \$options{throttle},
	"ubgi|update-background-image=s" => \$options{update_background_image},
	"ubni|update-banner-image=s" => \$options{update_banner_image},
	"upc|update-profile-colors" => \$options{update_profile_colors},
	"vy|verify" => \$options{verify},
	"wl|whitelist=s" => \@{$options{whitelist}},
));
#or die("Error in command line arguments\n");

#print Dumper($arg_ret);exit;
unless($arg_ret){
	exit;
}

if($options{help} || $options{examples}){
	&show_help($options{examples});
}

unless(@{$options{bot_files}} || @{$options{dirs}} || @{$options{suspended_files}}){
	print "No YAML files specified...\n";
	exit;
}

if(@{$options{dirs}})
{
	my @tmp = split(/,/, join(',', @{$options{dirs}}));
	@tmp = grep{!-d $_} <@tmp>;
	push(@{$options{bot_files}}, @tmp);
}

@{$options{bot_files}} = split(/,/, join(',', @{$options{bot_files}}));
#print Dumper(\@{$options{bot_files}}); exit;

my $bots = {};
unless(@{$options{suspended_files}}){
	$bots = read_conf(@{$options{bot_files}});
	unless(defined $bots){
		print "bots undefined...\n";
		exit;
	}elsif(!%$bots){
		print "no bots found...\n";
		exit;
	}
}

if(@{$options{whitelist}})
{
	@{$options{whitelist}} = split(/,/, join(',', @{$options{whitelist}}));
	print "\n$div\n\nLoading whitelist...\n";
	eval
	{
		for my $fname(@{$options{whitelist}}){
			open(WHITELIST, '<', $fname) or die "can't open file: $!";
			while(my $line = <WHITELIST>)
			{
				chomp($line);
				$line =~ s/\s+//g;
				next unless length $line;
				if(exists $bots->{$line}){
					delete $bots->{$line};
					print "\tRemoved: $line\n";
				}
			}
			close(WHITELIST) or die "can't close file: $!";
		}
	};
	if(my $err = $@){
		print "Error: error loading whitelist: $err\n";
		exit;
	}
	print "\n";
}

print "\n$div\n\nLoaded ", scalar keys %$bots, " bots...\n";
my @bot_names = sort{lc($a) cmp lc($b)} keys %$bots;
print "\t", join("\n\t", @bot_names), "\n\n$div\n\n";

if($options{names}){
	exit;
}

if($options{dump_conf}){
	print Dumper($bots);
	exit;
}elsif($options{creds}){
	for my $name(sort{lc($a) cmp lc($b)} @bot_names){
		print "\n$name\n";
		my $l = longest(keys %{$bots->{$name}->{nt_credentials}});
		foreach my $k(sort{lc($a) cmp lc($b)} keys %{$bots->{$name}->{nt_credentials}}){
			print "\t$k" . ' ' x ($l - length($k)) . " => '" . $bots->{$name}->{nt_credentials}->{$k} . "',\n";
		}
	}
	exit;
}elsif($options{logins}){
	my $l = longest(@bot_names);
	for my $name(sort{lc($a) cmp lc($b)} @bot_names){
		print $name . ' ' x ($l - length($name)) . ' : ' . $bots->{$name}->{info}->{password} . "\n";
	}
	exit;
}

if($options{pause})
{	
	print "Continue [y|n]: ";
	my $in = <STDIN>;
	chomp($in);
	if($in =~ /^(n|no)$/i){
		print "Aborting...\n";
		exit;
	}
	while($in !~ /^(y|yes)$/i)
	{
		print "Continue [y|n]: ";
		$in = <STDIN>;
		chomp($in);
		if($in =~ /^(n|no)$/i){
			print "Aborting...\n";
			exit;
		}
	}
	print "\n$div\n\n";
}


if(defined $options{proxy}){
	unless($options{proxy} =~ /^(.+)\:\d+$/){
		print "Invalid proxy: $options{proxy}\nValid format: <address:port>\n";
		exit;
	}else{
		$options{proxy} = 'socks://' . $options{proxy};
		print BOLD GREEN "Using proxy: $options{proxy}\n";
		print "\n$div\n";
	}
}
	
@bot_names = shuffle @bot_names;
unless($options{suspended} || @{$options{suspended_files}}){
	for my $name(@bot_names){
		if($options{hide_progress}){
			$bots->{$name}->{nt_settings}->{useragent_args}->{show_progress} = 0;
		}
		@{$bots->{$name}->{nt_settings}->{traits}} = 
			grep{$_ ne 'InflateObjects'} 
			@{$bots->{$name}->{nt_settings}->{traits}};
		
		$bots->{$name}->{nt} = Net::Twitter->new($bots->{$name}->{nt_settings});
		
		if(defined $options{proxy}){
			#$nt->ua()->requests_redirectable(['GET','HEAD','POST']);
			#$nt->ua()->proxy(['http','https'] => 'socks://127.0.0.1:10000');
			$bots->{$name}->{nt}->ua()->proxy(['http','https'] => $options{proxy});
		}
	}
}

if($options{verify})
{
	for my $name(@bot_names)
	{
		print "\n$name\n";
		my $res = fetch($bots->{$name}->{nt}, 'verify_credentials', {});
		if(defined $res){
			my $bname = $res->{screen_name};
			print "Credentials OK - $bname\n";
		}else{
			print "Bad credentials!\n";
		}
		
		print "\n$div\n";
	}
	exit;
}
elsif($options{update_profile_colors})
{
	for my $name(@bot_names)
	{
		print "\n$name\n";
		fetch($bots->{$name}->{nt}, 'update_profile_colors', {
			profile_background_color		=> '000000',
			profile_link_color              => '0084B4',
			profile_sidebar_border_color    => '000000',
			profile_sidebar_fill_color      => 'DDEEF6',
			profile_text_color              => '333333',
		});
		print "\n$div\n";
	}
	exit;
}
elsif(defined $options{update_background_image})
{
	my $background_img = get_img_data($options{update_background_image});
	if($background_img->{error}){
		die "Error: " . $background_img->{error} . "\n";
	}
	
	for my $name(@bot_names)
	{
		print "\n$name\n";
		fetch($bots->{$name}->{nt}, 'update_profile_background_image', {
			image 	=>  [
				undef, 
				$background_img->{rand_filename}, 
				Content_Type => $background_img->{mime_type}, 
				Content => $background_img->{raw_image_data}
			],
			use 	=> 1,
			tile 	=> 1,
		});
		print "\n$div\n";
	}
	exit;
}
elsif(defined $options{update_banner_image})
{
	#HTTP Response Codes
	#Code(s)		Meaning
	#200, 201, 202	Profile banner image succesfully uploaded
	#400			Either an image was not provided or the image data could not be processed
	#422			The image could not be resized or is too large.

	my $banner = get_img_data($options{update_banner_image});
	if($banner->{error}){
		die "Error: " . $banner->{error} . "\n";
	}
	
	for my $name(@bot_names)
	{
		print "\n$name\n";
		fetch($bots->{$name}->{nt}, 'update_profile_banner', {
			width 		=> $banner->{width},
			height 		=> $banner->{height},
			offset_left => 0,
			offset_top 	=> 0,
			banner 	=>  [
				undef, 
				$banner->{rand_filename}, 
				Content_Type => $banner->{mime_type}, 
				Content => $banner->{raw_image_data}
			],
		});
		print "\n$div\n";
	}
	exit;
}
elsif(@{$options{follow_people}})
{
	
	@{$options{follow_people}} = split(/,/, join(',', @{$options{follow_people}}));
	print "\n$div\n\nLoading follow list...\n";
	my $to_follow = [];
	eval
	{
		for my $fname(@{$options{follow_people}}){
			open(WHITELIST, '<', $fname) or die "can't open file: $!";
			while(my $line = <WHITELIST>)
			{
				chomp($line);
				$line =~ s/\s+//g;
				next unless length $line;
				push(@$to_follow, $line);
			}
			close(WHITELIST) or die "can't close file: $!";
		}
	};
	if(my $err = $@){
		print "Error: error loading follow list: $err\n";
		exit;
	}
	print "\nGoing to follow:\n\t", join("\n\t", @$to_follow), "\n\n$div\n\n";

	for my $name(@bot_names){
		print "\n$name\n";
		@$to_follow = shuffle @$to_follow;
		for my $id(@$to_follow){
			print "\t$id\n";
			fetch($bots->{$name}->{nt}, 'create_friend', {id=>$id});
		}
	}	
	
}
elsif($options{follow_followers})
{
	for my $name(@bot_names)
	{
		print "\n$name\n";
		
		my @follow = ();
		eval
		{
			for (my $cursor = -1, my $r; $cursor; $cursor = $r->{next_cursor}){
				$r = fetch($bots->{$name}->{nt}, 'followers_ids', {screen_name => $name, cursor => $cursor});
				unless(defined $r){
					print "Result is undefined...\n";
					last;
				}elsif(!defined $r->{ids}){
					print "Ids are undefined...\n";
					last;
				}elsif(!@{$r->{ids}}){
					print "Ids are not an array...\n";
					last;
				}else{
					push(@follow, @{$r->{ids}});
				}
			} 
		};
		if(my $err = $@){
			print "Error getting follower ids: $err\n";
		}
		
		unless(@follow){
			print "No followers found...\n\n$div\n";
			next;
		}
		
		my %friends = ();
		eval
		{
			for (my $cursor = -1, my $r; $cursor; $cursor = $r->{next_cursor}){
				$r = fetch($bots->{$name}->{nt}, 'friends_ids', {screen_name => $name, cursor => $cursor});
				unless(defined $r){
					print "Result is undefined...\n";
					last;
				}elsif(!defined $r->{ids}){
					print "Ids are undefined...\n";
					last;
				}elsif(!@{$r->{ids}}){
					print "Ids are not an array...\n";
					last;
				}else{
					for my $id(@{$r->{ids}}){
						$friends{$id}++;
					}
				}
			} 
		};
		if(my $err = $@){
			print "Error getting follower ids: $err\n";
		}
	
		my @real_follow = grep{!exists $friends{$_}} @follow;
		
		unless(@real_follow){
			print "No new people to follow...\n\n$div\n";
			next;
		}
		
		for my $id(@real_follow){
			print "\t$id\n";
			fetch($bots->{$name}->{nt}, 'create_friend', {id=>$id});
		}
	}	
}
elsif($options{suspended} || @{$options{suspended_files}})
{

	my @snames = ();
	if($options{suspended}){
		@snames = @bot_names;
	}
	else
	{
		@{$options{suspended_files}} = split(/,/, join(',', @{$options{suspended_files}}));
		print "\n$div\n\nLoading suspended file...\n";
		eval
		{
			for my $fname(@{$options{suspended_files}}){
				open(SUSPENDED_FILE, '<', $fname) or die "can't open file: $!";
				while(my $line = <SUSPENDED_FILE>)
				{
					chomp($line);
					$line =~ s/\s+//g;
					next unless length $line;
					push(@snames, $line);
					print "$line\n";
				}
				close(SUSPENDED_FILE) or die "can't close file: $!";
			}
		};
		if(my $err = $@){
			print "Error: error loading suspended file: $err\n";
			exit;
		}
		print "\nLoaded ", scalar(@snames), " names...\n\n";
	}
	
	my $ua = LWP::UserAgent->new(
		agent		 => 'Mozilla/5.0 (X11; Linux i686; rv:16.0) Gecko/20100101 Firefox/16.0',
		cookie_jar	 => {},
		max_redirect => 7,
		timeout		 => 10,
	);
	
	if(defined $options{proxy}){
		$ua->proxy(['http', 'https'] => $options{proxy});
	}
	
	print "Suspended check...\n\n";
	
	my $l = longest(@snames);
	for my $name(sort{lc($a) cmp lc($b)} @snames)
	{
		my $ln = $name . ' ' x ($l - length($name)) . ' - ';
		eval
		{
			my $response = $ua->get('https://twitter.com/' . $name);
			#$ln .= $response->code . ' - ';
			unless($response->is_success){
				if($response->code == 404){
					print BOLD CYAN  $ln . "USER DOES NOT EXIST\n";
				}else{
					print BOLD YELLOW $ln . "FAILED\n";
				}
			}else{
				my $title = $response->title();
				unless(defined $title){
					print BOLD YELLOW $ln . "NO TITLE\n";
				}else{
					if($title =~ /Account\s+Suspended/i){
						#Twitter / Account Suspended
						print BOLD RED $ln . "SUSPENDED\n";
					}else{
						print BOLD GREEN $ln . "OK\n";
					}
				}
			}
			$ua->cookie_jar({});
		};
		if(my $err = $@){
			print BOLD YELLOW $ln . "ERROR - $err\n";
		}
	}
	
}
elsif($options{account_info})
{
	my $bname = $bot_names[0];
	lookup_user_info($bname, \@bot_names);
	exit;
}
elsif(defined $options{lookup_users})
{
	my @user_names = read_lines($options{lookup_users});
	unless(@user_names){
		print "No user names found to lookup...\n";
	}else{
		my $bname = $bot_names[0];
		lookup_user_info($bname, \@user_names);
	}
	exit;
}
elsif($options{clear_tweets})
{
	print "\nYou are about to clear all tweets from each bot's timeline.\n";
	print "Continue [y|n]: ";
	my $in = <STDIN>;
	chomp($in);
	if($in =~ /^(n|no)$/i){
		print "Aborting...\n";
		exit;
	}
	while($in !~ /^(y|yes)$/i)
	{
		print "Continue [y|n]: ";
		$in = <STDIN>;
		chomp($in);
		if($in =~ /^(n|no)$/i){
			print "Aborting...\n";
			exit;
		}
	}
	print "\n$div\n\n";
	
	for my $name(@bot_names)
	{
		print "\n$name\n";
		eval
		{
			my $max_pages = 0;
			my $tweets_per_fetch = 150;
			my $tweets = fetch($bots->{$name}->{nt}, 'user_timeline', {screen_name => $name, count=>1});
			unless(defined $tweets){
				die "Could not fetch initial tweet...\n";
			}
			
			my $total_tweets = $tweets->[0]->{user}->{statuses_count};
			unless(defined $total_tweets){
				die "no tweets found...\n";
			}
			if($total_tweets <= $tweets_per_fetch){
				$max_pages = 1;
			}else{
				$max_pages = ceil($total_tweets / $tweets_per_fetch);
			}
			
			
			my $current_page = 0;
			my $ut_opts = 
			{
				screen_name => $name, 
				count 		=> $tweets_per_fetch, 
				include_rts => 1, 
				page 		=> $current_page
			};
			
			my @ids = ();
			while($current_page <= $max_pages)
			{
				$tweets = fetch($bots->{$name}->{nt}, 'user_timeline', $ut_opts);
				unless(defined $tweets){
					last;
				}elsif(!@$tweets){
					last;
				}
				for my $status(@$tweets)
				{
					#print "\t" . $status->{id} . "\n";
					push(@ids, $status->{id});
				}
				$current_page++;
				$ut_opts->{page} = $current_page;
			}
			
			unless(@ids){
				die "no ids found...";
			}
			
			print "\nDeleting ", scalar(@ids), " tweets...\n\n";
			
			for my $id(@ids){
				print "\t$id\n";
				fetch($bots->{$name}->{nt}, 'destroy_status', {id => $id});
				
			}
			##Cursor method
			#for (my $cursor = -1, my $r; $cursor; $cursor = $r->{next_cursor}){
			#	$r = fetch($bots->{$name}->{nt}, 'friends_ids', {screen_name => $name, cursor => $cursor});
			#	unless(defined $r){
			#		print "Result is undefined...\n";
			#		last;
			#	}elsif(!defined $r->{ids}){
			#		print "Ids are undefined...\n";
			#		last;
			#	}elsif(!@{$r->{ids}}){
			#		print "Ids are not an array...\n";
			#		last;
			#	}else{
			#		for my $id(@{$r->{ids}}){
			#			$friends{$id}++;
			#		}
			#	}
			#} 
			
		};
		if(my $err = $@){
			print "Error: error getting tweets: $err\n";
		}
		
		print "\n$div\n";
	}
	
	exit;
}


sub fetch($$$)
{
	if($options{throttle} != -1){
		if($throttled){
			print "\t--Throttle: waiting until ", scalar localtime(time + $options{throttle}), "--\n";
			sleep($options{throttle});
		}
		$throttled = 1;
	}
	my ($net_twitter_client, $method, $method_options) = @_;
	my $twitter_response = eval{$net_twitter_client->$method($method_options)};
	if (my $err = $@){
		if(blessed $@ && $err->isa('Net::Twitter::Error'))
		{
			warn 
				"Method............: ", $method,       "\n",
				"HTTP Response Code: ", $err->code,    "\n",
				"HTTP Message......: ", $err->message, "\n",
				"Twitter Error.....: ", $err->error,   "\n";
		
		}else{
			die "$@\n";
		}
	}
	return $twitter_response;
}

sub longest(@)
{
	return (sort{$b <=> $a} map{length $_} @_)[0];
}

sub random($$)
{ 
	#$_[0] = floor
	#$_[1] = ceiling
	return $_[0] + irand($_[1] - $_[0] + 1); 
}

sub read_conf(@)
{
	my $ret = {};
	
	for my $fname(@_){
		eval
		{
			unless(defined $fname){
				die "config not defined";
			}elsif(!-e $fname){
				die "$fname does not exist";
			}
		
			my $tmp_s = YAML::Tiny::LoadFile($fname);
			if($YAML::Tiny::errstr){
				die "unable to read conf from $fname: $YAML::Tiny::errstr";
			}
			
			map{$ret->{$_} = $tmp_s->{$_}} keys %$tmp_s;
		};
		if(my $err = $@){
			print "Error: $err\n";
		}else{
			print "Info: read bots from $fname\n";
		}
	}
	return $ret;
}

sub cd(;$)
{
	my $dir = $_[0];
	unless(defined $dir){
		(undef, $dir) = File::Basename::fileparse(Cwd::abs_path($0));
	}
	$dir =~ s/\\+/\//g;
	chdir($dir) or die "Can't change CWD directory to $dir: $!\n";
	#print "Changed CWD to: \"$dir\"\n";
}

sub get_cwd
{
	my (undef, $dir) = File::Basename::fileparse(Cwd::abs_path($0));
	if(defined $dir){
		$dir =~ s/\\/\//g;
		if($dir !~ /\/$/){
			$dir .= "/";
		}
	}
	return $dir;
}

sub get_img_data($)
{
	my $ret = {
		raw_image_data => undef,
		width => 0,
		height => 0,
		mime_type => undef,
		rand_filename => undef,
		error => 0,
	};
	
	eval
	{
		$ret->{raw_image_data} = do{
			open (my $fh, '<:raw:perlio', $_[0]) or die $!;
			local $/;
			<$fh>;		
		};
		
		unless(defined $ret->{raw_image_data}){
			die "Image data is undefined";
		}
	};
	if(my $err = $@){
		print "Can't open image file: $err\n";
		$ret->{error} = 1;
		return $ret;
	}
	
	eval
	{
		my $img_info = image_info($_[0]);
		if(my $error = $img_info->{error}){
			die $error;
		}
		
		unless(defined $img_info->{file_media_type}){
			die "unable to determine mime type";
		}
		
		$ret->{mime_type} = $img_info->{file_media_type};
		$ret->{width} = $img_info->{width};
		$ret->{height} = $img_info->{height};
	};
	if(my $err = $@){
		print "Can't parse image info: $err\n";
		$ret->{error} = 1;
		return $ret;
	}
	
	my $rand_rgx = new String::Random;
	$ret->{rand_filename} = $rand_rgx->randregex('[A-Za-z0-9]{8,24}');

	return $ret;
}

sub read_lines($)
{
	my $fname = $_[0];
	my @ret = ();
	eval
	{
		unless(-e $fname){
			die "file does not exist: $fname";
		}
		open(F, '<', $fname) or die "unable to open file: $!";
		while(my $line = <F>)
		{
			chomp($line);
			$line =~ s/^\s+|\s+$//g;
			next unless length $line;
			push(@ret, $line);
		}
		close(F) or die "unable to close file: $!";
	};
	if(my $err = $@){
		print "Error: error reading file lines: $err\n";
	}
	return @ret;
}

sub lookup_user_info($@)
{
	my $bname = $_[0];
	my @users = @{$_[1]};
	
	print "\n$div\nUsing $bname to perform lookup_users\n$div\n\n";
	
	my $user_list = {
		screen_name => [], 
		user_id => []
	};
	@{$user_list->{screen_name}} = grep{$_ !~ /^\d+$/} @users; 
	@{$user_list->{user_id}} = grep{$_ =~ /^\d+$/} @users;
	
	my @columns = qw(
		screen_name
		name
		id
		statuses_count
		friends_count
		followers_count
		favourites_count
		created_at
		time_zone
	);
	
	my $results = [];
	foreach my $k(keys %$user_list)
	{
		unless(@{$user_list->{$k}}){
			next;
		}
		
		while(my @chunk = splice(@{$user_list->{$k}},0,99))
		{
			my $r = fetch($bots->{$bname}->{nt}, 'lookup_users', {$k => \@chunk});
			#print Dumper($r);
			unless(defined $r){
				print "Results undefined...\n";
				last;
			}elsif(!@$r){
				print "Results are not an array...\n";
				last;
			}
			
			for my $user(@$r){
				my $ui = {};
				for my $column(@columns){
					my $v = (defined $user->{$column}) ? $user->{$column} : '';
					$v =~ s/([^\x{20}-\x{7E}])/sprintf'\\x{%02X}',ord($1)/gse;
					$v =~ s/^\s+|\s+$//g;
					$ui->{$column} = $v;
				}
				push(@$results, $ui);
			}
		}
	}
	
	#print Dumper($results);
	
	my $table = Text::ASCIITable->new({
			#drawRowLine     => 0,
			#hide_Lastline => 1, 
			reportErrors => 0,
			#hide_HeadRow => 1,
			#hide_HeadLine => 1,	
			#hide_FirstLine=>1,
			#hide_LastLine => 1,
			headingText => 'User information',
			#alignHeadRow    => 'left',
	});
	$table->setCols(@columns);
	
	for my $usr(sort{lc($a->{screen_name}) cmp lc($b->{screen_name})} @$results){
		my @row = ();
		for my $column(@columns){
			push(@row, $usr->{$column});
		}
		$table->addRow(@row);
	}
	
	print "\n$table\n";
	
}

sub show_help
{
 
print <<EOL;

Options:

aci,  account-info                          - Shows misc information and stats for each bot account
c,    creds                                 - Shows API keys
d,    dirs                     <dir>        - Directory to look for yaml files
dp,   dump                                  - Dumps bot structure
ct,   clear-tweets                          - Clear tweets from every bot's timeline
e,    examples                              - Shows example usage
f,    files                    <file>       - Specifies bot YAML files to use
ff,   follow-followers                      - Follow followers that the bots are not following
fp,   follow-people            <file>       - Specifies a file containing screen names and user ids to follow
h,    help                                  - Shows this help menu
hp,   hide-progress                         - Hides progress bar
l,    logins                                - Shows bot logins and passwords
lu,   lookup-users             <file>       - Looks up user information for users in specified file
n,    names                                 - Only show names
p,    pause                                 - Pause before continuing
px,   proxy                    <addr:port>  - Specifies a proxy to use
ss,   suspended                             - Check to see which bots are suspended
sf,   suspended-file           <file>       - Check to see which accounts are suspended from file
th,   throttle                 <number>     - Specifies number of seconds to wait in between each action
ubgi, update-background-image  <file>       - 
ubni, update-banner-image      <file>       - 
upc,  update-profile-colors                 - 
vy,   verify                                - Verifies bot API keys
wl,   whitelist                <file>       - Specifies a file containing bot names not to use
EOL

unless($_[0]){
	exit;
}

my ($s, undef) = File::Basename::fileparse($0);

print <<EOL;

Examples:

$s -v

EOL

exit;

}
