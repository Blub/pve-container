package PVE::LXCSetup::Ubuntu;

use strict;
use warnings;
use Data::Dumper;
use PVE::Tools;
use PVE::LXC;
use File::Path;

use PVE::LXCSetup::Debian;

use base qw(PVE::LXCSetup::Debian);

my $known_versions = {
    '15.04' => 1, # vivid
    '14.04' => 1, # trusty LTS
    '12.04' => 1, # precise LTS
};

sub new {
    my ($class, $conf, $rootdir) = @_;

    my $lsb_fn = "$rootdir/etc/lsb-release";
    my $lsbinfo = PVE::Tools::file_get_contents($lsb_fn);

    die "got unknown DISTRIB_ID\n" if $lsbinfo !~ m/^DISTRIB_ID=Ubuntu$/mi;
    
    my $version;
    if ($lsbinfo =~ m/^DISTRIB_RELEASE=(\d+\.\d+)$/mi) {
	$version = $1;
    }
    
    die "unable to read version info\n" if !defined($version);
  
    die "unsupported ubunt version '$version'\n" if !$known_versions->{$version};

    my $self = { conf => $conf, rootdir => $rootdir, version => $version };

    $conf->{ostype} = "ubuntu";

    return bless $self, $class;
}

sub template_fixup {
    my ($self, $conf) = @_;

    my $rootdir = $self->{rootdir};
    my $version = $self->{version};
    
    if ($version eq '15.04') {
	# edit /etc/securetty (enable login on console)
	my $filename = "$rootdir/etc/securetty";
	my $data = PVE::Tools::file_get_contents($filename);
	if ($data !~ m!^pts/0\s*$!m) {
	    $data .= "pts/0\n"; 
	}
	PVE::Tools::file_set_contents($filename, $data);
    }

    if ($version eq '12.04') {
	# suppress log level output for udev
	my $filename = "$rootdir/etc/udev/udev.conf";
	my $data = PVE::Tools::file_get_contents($filename);
	$data =~ s/=\"err\"/=0/m;
	PVE::Tools::file_set_contents($filename, $data);
    }
}

sub setup_init {
    my ($self, $conf) = @_;

    my $rootdir = $self->{rootdir};
    my $version = $self->{version};

    if ($version eq '12.04' || $version eq '14.04') {
	my $ttycount = defined($conf->{tty}) ? $conf->{tty} : 4;
	for (my $i = 1; $i < 7; $i++) {
	    my $filename = "$rootdir/etc/init/tty$i.conf";
	    if ($i <= $ttycount) {
		my $tty_conf = <<__EOD__;
# tty$i - getty
#
# This service maintains a getty on tty$i from the point the system is
# started until it is shut down again.

start on stopped rc RUNLEVEL=[2345] and (
            not-container or
            container CONTAINER=lxc or
            container CONTAINER=lxc-libvirt)

stop on runlevel [!2345]

respawn
exec /sbin/getty -8 38400 tty$i
__EOD__
                PVE::Tools::file_set_contents($filename, $tty_conf);
	    } else {
		for (my $i = $ttycount + 1; $i < 7; $i++) {
		    unlink $filename;
		}
	    }
	}
    }
}

1;
