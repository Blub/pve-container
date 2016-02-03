#!/usr/bin/perl

use strict;
use warnings;

use lib qw(../..);

use PVE::LXC::Setup::Base;

# these are in order of PVE::LXC::Setup::Base::update_etc_hosts() parameters
my @CONF_PARAMS = qw(hostip oldname newname searchdomains);

sub test_file {
    my ($exp_fn, $real_fn, $msg, $cfg) = @_;

    return if system("diff -u '$exp_fn' '$real_fn'") == 0;

    die "files do not match: $msg\n" .
	join("\n", map { "   $_: " . ($cfg->{$_}//'') } @CONF_PARAMS) . "\n";
}

sub parse_test($) {
    my ($file) = @_;

    my $tests = [];
    my $testdesc = {};

    open my $fh, '<', $file or die "failed to open $file: $!\n";

    my $line;
    my $data = '';
    while ($line = <$fh>) {
	last if $line =~ /^test:/;
	$data .= $line;
    }
    $testdesc->{input} = $data;

    die "missing tests\n" if !defined($line);
    while (defined($line) && $line =~ /^test:/) {
	chomp $line;
	$line =~ s/^test:\s*//;
	my $test = { id => $line };

	# Read test configuration
	while ($line = <$fh>) {
	    chomp $line;
	    last if $line =~ /^expect:/;
	    next if $line =~ /^\s*$/ || $line =~ /^\s*#/;
	    if ($line =~ /^\s*(\w+)\s*=\s*(.*)$/) {
		die "duplicate entry: $1\n" if defined($test->{$1});
		$test->{$1} = $2;
		die "unknown config key: $1\n" if !grep { $_ eq $1 } @CONF_PARAMS;
	    } else {
		die "bad test input: $line";
	    }
	}
	die "missing expected output\n" if !defined($line);

	$test->{newname} //= 'localhost';
	$test->{oldname} //= 'localhost';

	# Read expected output
	$data = '';
	while ($line = <$fh>) {
	    last if $line =~ /^test:/ || $line =~ /^end\s*$/;
	    $data .= $line;
	}
	$test->{expected} = $data;
	push @$tests, $test;

	if (defined($line) && $line =~ /^end\s*$/) {
	    # skip to next 'test:'
	    while ($line = <$fh>) {
		last if $line =~ /^test:/;
	    }
	}
    }
    die "garbage after test description: $line\n" if defined($line);

    close $fh;

    $testdesc->{tests} = $tests;
    return $testdesc;
}

sub run_test {
    my ($testfile) = @_;

    my $testdesc = parse_test($testfile);

    my $input = $testdesc->{input};

    my $id = 0;
    foreach my $test (@{$testdesc->{tests}}) {
	my @cfgargs = map { $test->{$_} } @CONF_PARAMS;

	my $got = PVE::LXC::Setup::Base::update_etc_hosts($input, @cfgargs);

	open my $expfd, '>', 'tmphosts.exp'
	    or die "failed to open tmphosts.exp: $!\n";
	print {$expfd} $test->{expected};
	close $expfd;

	open my $gotfd, '>', 'tmphosts.got'
	    or die "failed to open tmphosts.got: $!\n";
	print {$gotfd} $got;
	close $gotfd;

	my $subtestname = $test->{id} || $id;
	test_file('tmphosts.exp', 'tmphosts.got', "first pass, subtest $subtestname", $test);

	# second run:
	$got = PVE::LXC::Setup::Base::update_etc_hosts($got, @cfgargs);
	open $gotfd, '>', 'tmphosts.got'
	    or die "failed to open tmphosts.got: $!\n";
	print {$gotfd} $got;
	close $gotfd;

	test_file('tmphosts.exp', 'tmphosts.got', "second pass, subtest $subtestname", $test);

	print "TEST $testfile [$subtestname] => OK\n";
	++$id;
    }
}

if (scalar(@ARGV)) {

    foreach my $testdir (@ARGV) {
	run_test($testdir);  
    }

} else {

    foreach my $testdir (<test.*>) {#
	next if ! -f $testdir; 
	run_test($testdir);
    }
}
