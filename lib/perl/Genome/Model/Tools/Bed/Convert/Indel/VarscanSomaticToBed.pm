package Genome::Model::Tools::Bed::Convert::Indel::VarscanSomaticToBed;
# DO NOT EDIT THIS FILE UNINTENTIONALLY IT IS A COPY OF VarscanToBed

use strict;
use warnings;

use Genome;

class Genome::Model::Tools::Bed::Convert::Indel::VarscanSomaticToBed {
    is => ['Genome::Model::Tools::Bed::Convert::Indel'],
};

sub help_brief {
    "Tools to convert varscan-somatic indel format to BED.",
}

sub help_synopsis {
    my $self = shift;
    return <<"EOS"
  gmt bed convert indel varscan-somatic-to-bed --source indels_all_sequences --output indels_all_sequences.bed
EOS
}

sub help_detail {                           
    return <<EOS
    This is a small tool to take indel calls in var-scan format and convert them to a common BED format (using the first four columns).
EOS
}

sub process_source {
    my $self = shift;
    my $input_fh = $self->_input_fh;
    
    while(my $line = <$input_fh>) {
        my ($chromosome, $position, $_reference, undef, $depth1, $depth2, undef, undef, undef, $quality, undef, $consensus, @extra) = split("\t", $line);
        my @converted_indels = $self->convert_indel($line);
        
        # we take depth to mean total depth. varscan reports this in 2 fields, depth of reads
        # supporting the reference, and depth of reads supporting the called variant, so
        # we output the sum.
        my $depth = $depth1 + $depth2;
        for my $converted_indel (@converted_indels){
            my ($reference, $variant, $start, $stop) = @$converted_indel;
            $self->write_bed_line($chromosome, $start, $stop, $reference, $variant, $quality, $depth);
        }
    }

    return 1;
}

sub convert_indel {
    my $class = shift;
    my $line = shift;
    my ($chromosome, $position, $_reference, $var, $depth1, $depth2, undef, $n_gt, undef, $quality, undef, $consensus, @extra) = split("\t", $line);

    no warnings qw(numeric);
    return unless $position eq int($position); #Skip header line(s)
    use warnings qw(numeric);

    my @converted_indels;
    my ($indel_call_1, $indel_call_2);

    if ($var =~ /\//) {
        #1	247991	C	-A/-AA	16	2	11.11%	*/-A	30	6	16.67%	*/-AA	Unknown	1.0	0.45991974036934513	24	14	3	3
        #1	10353	A	+C/+AC	18	2	10%	    */+C	42	4	8.7%	*/+AC	Unknown	1.0	0.7460705278327899	20	28	2	2
        ($indel_call_1, $indel_call_2) = split /\//, $var;
    }
    else {
        ($indel_call_1, $indel_call_2) = split /\//, $consensus;
    }

    if (defined $indel_call_2) {
        if ($indel_call_1 eq $indel_call_2) {
            undef $indel_call_2;
        }
    }

    for my $indel ($indel_call_1, $indel_call_2) {
        next unless defined $indel;
        next if $indel eq '*'; #Indicates only one indel call...and this isn't it!

        #position => 1-based position of the start of the indel
        #BED uses 0-based position of and after the event

        my ($reference, $variant, $start, $stop);

        #samtools pileup reports the position before the first deleted base or the inserted base ... so the start position is already correct for bed format
        $start = $position;
        if (substr($indel, 0, 1) eq '+') {
            $reference = '*';
            $variant   = substr($indel, 1);
            $stop      = $start; #Two positions are included-- but an insertion has no "length" so stop and start are the same
        } 
        elsif (substr($indel, 0, 1) eq '-') {
            $reference = substr($indel, 1);
            $variant   = '*';
            $stop      = $start + length($reference);
        }
        elsif ($indel =~ /^[ACTG]$/) {
            #13	85935825	A	+CT	53	38	41.76%	*/+CT	60	4	6.25%	A	LOH	1.0	2.7536750660204944E-7	34	30	2	2
            #13	86203103	T	-TA	55	10	15.38%	*/-TA	46	0	0%	    T	LOH	1.0	0.0034732332318821516	31	15	0	0
            my ($n_var) = $n_gt =~ /([+-]\S+)$/;
            if ($var eq $n_var) {
                if (substr($var, 0, 1) eq '+') {
                    $reference = '*';
                    $variant   = substr($var, 1);
                    $stop      = $start;
                }
                else {
                    $reference = substr($var, 1);
                    $variant   = '*';
                    $stop      = $start + length($reference);
                }
            }
            else {
                $class->warning_message("Unexpected indel format encountered ($indel) on line:\n$line");
                next;
            }
        }
        else {
            $class->warning_message("Unexpected indel format encountered ($indel) on line:\n$line");
            next;
        }
        push @converted_indels, [$reference, $variant, $start, $stop];
    }
    
    return @converted_indels;
}

1;
