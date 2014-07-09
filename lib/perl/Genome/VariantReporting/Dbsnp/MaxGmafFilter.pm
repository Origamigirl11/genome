package Genome::VariantReporting::Dbsnp::MaxGmafFilter;

use strict;
use warnings;
use Genome;

class Genome::VariantReporting::Dbsnp::MaxGmafFilter {
    is => 'Genome::VariantReporting::Framework::Component::Filter',
    has => [
        max_gmaf => {
            is => 'Number',
            doc => 'Maximum allele frequency',
        },
    ],
};

sub name {
    return 'max-gmaf'
}

sub requires_annotations {
    return ('dbsnp');
}

sub filter_entry {
    my $self = shift;
    my $entry = shift;
    my %return_values;

    if (!defined $entry->info("GMAF")) {
        return map {$_ => 1} @{$entry->{alternate_alleles}};
    }

    for my $alt_allele (@{$entry->{alternate_alleles}}) {
        if ($entry->info("GMAF") <= $self->max_gmaf) {
            $return_values{$alt_allele} = 1;
        }
        else {
            $return_values{$alt_allele} = 0;
        }
    }

    return %return_values;
}

1;

