package PVE::API2::LXC::Features;

use strict;
use warnings;

use PVE::Tools qw(extract_param);
use PVE::Exception qw(raise_param_exc);
use PVE::Storage;
use PVE::RESTHandler;
use PVE::RPCEnvironment;
use PVE::LXC;
use PVE::JSONSchema qw(get_standard_option);
use base qw(PVE::RESTHandler);

my $apparmor_rules = {
    netmount => [
	'mount fstype=nfs*,',
	'mount fstype=cifs,',
	'mount fstype=9p,',
    ],
    blockmount => [
	# Equivalent of the lxc-container-default-with-mounting profile
	'mount fstype=ext*,',
	'mount fstype=xfs,',
	'mount fstype=btrfs,',
    ],
    nesting => [
	# Equivalent of the lxc-container-default-with-nesting profile
	'#include <abstractions/lxc/start-container>',
	# NOTE: When we stop using cgmanager we need to add the following:
	# 'mount fstype=cgroup -> /sys/fs/cgroup/**,',
	'deny /dev/.lxc/proc/** rw,',
	'deny /dev/.lxc/sys/** rw,',
	'mount fstype=proc -> /var/cache/lxc/**,',
	'mount fstype=sysfs -> /var/cache/lxc/**,',
	'mount options=(rw,bind),',
    ],
};

sub map_combinations {
    my ($values, $func, $current) = @_;
    return if !@$values;
    foreach my $i (0..@$values-1) {
	&$func(@$current, $values->[$i]);
	map_combinations([@$values[$i+1..@$values-1]],
	                 $func,
	                 [@$current, $values->[$i]]);
    }
};

sub generate_apparmor_profiles {
    my ($fh) = @_;
    my $keys = [sort keys %$apparmor_rules];
    print {$fh} "# lxc profile combinations\n";
    map_combinations($keys, sub {
	my (@options) = @_;
	my $name = join('-', @options);
	print {$fh} "\nprofile lxc-pve-$name";
	print {$fh} " flags=(attach_disconnected,mediate_deleted)";
	print {$fh} " {\n";
	print {$fh} "  #include <abstractions/lxc/container-base>\n";
	foreach my $opt (@options) {
	    my $rules = $apparmor_rules->{$opt};
	    print {$fh} "  ", join("\n  ", @$rules), "\n";
	}
	print {$fh} "}\n";
    });
}

__PACKAGE__->register_method({
    name => 'features',
    path => '',
    method => 'GET',
    proxyto => 'node',
    description => "Get available feature information.",
    permissions => {
	check => ['perm', '/vms/{vmid}', [ 'VM.Audit' ]],
    },
    parameters => {
	additionalProperties => 0,
	properties => {
	    node => get_standard_option('pve-node'),
	    vmid => get_standard_option('pve-vmid', { completion => \&PVE::LXC::complete_ctid }),
	},
    },
    returns => {
	type => 'object',
	properties => {
	    features => { type => 'string', optional => 1 },
	    available => {
		type => 'array',
		items => {
		    type => 'object',
		    properties => {
			id => { type => 'string' },
			name => { type => 'string' },
			description => { type => 'string' },
			allowed => { type => 'boolean' },
		    }
		},
	    },
	},
    },
    code => sub {
	my ($param) = @_;

	my $rpcenv = PVE::RPCEnvironment::get();

	my $authuser = $rpcenv->get_user();

	my $conf = PVE::LXC::Config->load_config($param->{vmid});

	my $all_options = $PVE::LXC::Config::ct_features;
	my $available = [];
	foreach my $id (keys %$all_options) {
	    my $allowed = PVE::LXC::check_feature_perms($rpcenv, $authuser, $id, $param, 1);
	    my $feature = $all_options->{$id};
	    push @$available, { id => $id,
				name => $feature->{name},
				description => $feature->{description},
				allowed => $allowed ? 1 : 0,
				};
	}

	my $res = { available => $available };
	if (my $features = $conf->{features}) {
	    $res->{features} = $features;
	}
	return $res;
    }});

__PACKAGE__->register_method({
    name => 'update_features',
    path => '',
    method => 'PUT',
    protected => 1,
    proxyto => 'node',
    description => "Set VM features.",
    permissions => {
	check => ['perm', '/vms/{vmid}', [ 'VM.Config.Options' ]],
    },
    parameters => {
	additionalProperties => 0,
	properties => {
	    node => get_standard_option('pve-node'),
	    vmid => get_standard_option('pve-vmid', { completion => \&PVE::LXC::complete_ctid }),
	    features => {
		type => 'string',
		format => $PVE::LXC::Config::feature_desc,
	    },
	    digest => {
		type => 'string',
		description => 'Prevent changes if current configuration file has different SHA1 digest. This can be used to prevent concurrent modifications.',
		maxLength => 40,
		optional => 1,
	    }
	},
    },
    returns => { type => 'null', },
    code => sub {
	my ($param) = @_;

	my $rpcenv = PVE::RPCEnvironment::get();
	my $authuser = $rpcenv->get_user();

	my $vmid = $param->{vmid};
	my $features = extract_param($param, 'features');

	my $digest = extract_param($param, 'digest');

	my $code = sub {
	    my $conf = PVE::LXC::Config->load_config($vmid);
	    PVE::LXC::Config->check_lock($conf);

	    PVE::Tools::assert_if_modified($digest, $conf->{digest});

	    if (!length($features)) {
		delete $conf->{features};
	    } else {
		PVE::LXC::check_modify_features($rpcenv, $authuser, $vmid, undef, $conf->{features}, $features);
		$conf->{features} = $features;
	    }
	    PVE::LXC::Config->write_config($vmid, $conf);

	    my $storage_cfg = PVE::Storage::config();
	    PVE::LXC::update_lxc_config($storage_cfg, $vmid, $conf);
	};

	PVE::LXC::Config->lock_config($vmid, $code);

	return undef;
    }});

1;
