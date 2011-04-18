#!perl

## Cleanup any mess we made

use 5.008003;
use strict;
use warnings;
use Test::More tests => 2;

opendir my $dh, '.' or die qq{Could not opendir?: $!\n};
for my $dir (readdir $dh) {
	next if $dir !~ /^bucardo_test_database_[A-Z]/ or ! -d $dir;
	my $pidfile = "$dir/postmaster.pid";
	next if ! -e $pidfile;
	open my $fh, '<', $pidfile or die qq{Could not open "$pidfile": $!\n};
	<$fh> =~ /^(\d+)/ or die qq{File "$pidfile" did not start with a number!\n};
	my $pid = $1;
	close $fh or die qq{Could not close "$pidfile": $!\n};
	kill 15 => $pid;
	sleep 1;
	if (kill 0 => $pid) {
		kill 9 => $pid;
	}
}

pass 'Test databases are shut down';

my $dir = "/tmp/bucardo_testing_$ENV{USER}";
if (-d $dir) {
	opendir my $dh, $dir or die qq{Could not open directory "$dir": $!\n};
	for my $file (grep { /^\w/ } readdir($dh)) {
		unlink "$dir/$file";
	}
	closedir $dh or die qq{Could not open directory "$dir": $!\n};
	rmdir $dir;
}

pass "Removed directory $dir";


