package Genome::Site;

use strict;
use warnings;

BEGIN {
    require Genome::Config;
};

use Carp qw(croak);
use File::Spec qw();
use Sys::Hostname qw(hostname);
use UR::Util qw();
use Module::Runtime qw(require_module);

our $VERSION = $Genome::VERSION;

sub import {
    if (my $config = Genome::Config::get('config')) {
        require_module($config);
    }
    else {
        load_host_config();
    }
}

sub load_host_config {
    my @hwords = site_dirs();
    while (@hwords) {
        my $pkg = site_pkg(@hwords);
        if (UR::Util::use_package_optimistically($pkg)) {
            last;
        } else {
            pop @hwords;
            next;
        }
    }
}

sub site_pkg {
    my @site_dirs = @_;
    return join('::', 'Genome', 'Site', @site_dirs);
}

sub site_dirs {
    # look for a config module matching all or part of the hostname
    my $hostname = hostname();
    my @hwords = map { s/-/_/g; $_ } reverse split(/\./, $hostname);
}

BEGIN {
    import();
}

1;

=pod

=head1 NAME

Genome::Site - hostname oriented site-based configuration

=head1 DESCRIPTION

Use the fully-qualified hostname to look up site-based configuration.

=head1 AUTHORS

This software is developed by the analysis and engineering teams at
The Genome Center at Washington Univiersity in St. Louis, with funding from
the National Human Genome Research Institute.

=head1 LICENSE

This software is copyright Washington University in St. Louis.  It is released under
the Lesser GNU Public License (LGPL) version 3.  See the associated LICENSE file in
this distribution.

=head1 BUGS

For defects with any software in the genome namespace,
contact genome-dev@genome.wustl.edu.

=cut

