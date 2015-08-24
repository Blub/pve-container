package PVE::LXC::Setup;

use strict;
use warnings;
use PVE::Tools;

use PVE::LXC::Setup::Debian;
use PVE::LXC::Setup::Ubuntu;
use PVE::LXC::Setup::Redhat;
use PVE::LXC::Setup::ArchLinux;

my $plugins = {
    debian    => 'PVE::LXC::Setup::Debian',
    ubuntu    => 'PVE::LXC::Setup::Ubuntu',
    redhat    => 'PVE::LXC::Setup::Redhat',
    archlinux => 'PVE::LXC::Setup::ArchLinux',
};

my $autodetect_type = sub {
    my ($rootdir) = @_;

    my $lsb_fn = "$rootdir/etc/lsb-release";
    if (-f $lsb_fn) {
	my $data =  PVE::Tools::file_get_contents($lsb_fn);
	if ($data =~ m/^DISTRIB_ID=Ubuntu$/im) {
	    return 'ubuntu';
	}
    } elsif (-f "$rootdir/etc/debian_version") {
	return "debian";
    } elsif (-f  "$rootdir/etc/redhat-release") {
	return "redhat";
    } elsif (-f  "$rootdir/etc/arch-release") {
	return "archlinux";
    }
    die "unable to detect OS disribution\n";
};

sub new {
    my ($class, $conf, $rootdir, $type) = @_;

    die "no root directory\n" if !$rootdir || $rootdir eq '/';

    my $self = bless { conf => $conf, $rootdir => $rootdir};

    if (!defined($type)) {
	# try to autodetect type
	$type = &$autodetect_type($rootdir);
    }
    
    my $plugin_class = $plugins->{$type} ||
	"no such OS type '$type'\n";

    $self->{plugin} = $plugin_class->new($conf, $rootdir);
    
    return $self;
}

sub template_fixup {
    my ($self) = @_;

    $self->{plugin}->template_fixup($self->{conf});
}
 
sub setup_network {
    my ($self) = @_;

    $self->{plugin}->setup_network($self->{conf});
}

sub set_hostname {
    my ($self) = @_;

    $self->{plugin}->set_hostname($self->{conf});
}

sub set_dns {
    my ($self) = @_;

    $self->{plugin}->set_dns($self->{conf});
}

sub setup_init {
    my ($self) = @_;

    $self->{plugin}->setup_init($self->{conf});
}

sub set_user_password {
    my ($self, $user, $pw) = @_;
    
    $self->{plugin}->set_user_password($self->{conf}, $user, $pw);
}

sub rewrite_ssh_host_keys {
    my ($self) = @_;

    $self->{plugin}->rewrite_ssh_host_keys($self->{conf});
}    

sub pre_start_hook {
    my ($self) = @_;

    $self->{plugin}->pre_start_hook($self->{conf});
}

sub post_create_hook {
    my ($self, $root_password) = @_;

    $self->{plugin}->post_create_hook($self->{conf}, $root_password);
}

1;