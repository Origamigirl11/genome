package Genome::Model::Tools::BwaSw;

use strict;
use warnings;

use Genome;
use Data::Dumper;
use File::Temp;

class Genome::Model::Tools::BwaSw {
    is => ['Command'],
    has_optional => [
                     version => {
                                 is    => 'string',
                                 doc   => 'version of bwa-sw application to use',
                             },
                     _tmp_dir => {
                                  is => 'string',
                                  doc => 'a temporary directory for storing files',
                              },
                 ]
};

sub help_brief {
    "tools to work with Ssaha output"
}

sub help_detail {                           # This is what the user will see with --help <---
    return <<EOS

EOS
}

sub create {
    my $class = shift;

    my $self = $class->SUPER::create(@_);

    unless (Genome::Sys->arch_os =~ /64/) {
        $self->error_message('All Ssaha tools must be run from 64-bit architecture');
        return;
    }
    my $tempdir = File::Temp::tempdir(CLEANUP => 1);
    $self->_tmp_dir($tempdir);

    return $self;
}



1;

