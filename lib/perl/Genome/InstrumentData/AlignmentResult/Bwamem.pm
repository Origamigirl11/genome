package Genome::InstrumentData::AlignmentResult::Bwamem;

use strict;
use warnings;
use Carp qw/confess/;
use Data::Dumper;
use File::Basename;
use File::Copy qw/move/;
use Genome;
use Getopt::Long;

class Genome::InstrumentData::AlignmentResult::Bwamem {
    is => 'Genome::InstrumentData::AlignmentResult',
    has_constant => [
        aligner_name => { value => 'bwamem', is_param=>1 },
    ],
    has_transient_optional => [
        _bwa_sam_cmd => { is => 'Text' }
    ]
};

sub required_arch_os { 'x86_64' }

sub required_rusage {
    my $class = shift;
    my %p = @_;
    my $instrument_data = delete $p{instrument_data};
    my $aligner_params  = delete $p{aligner_params};

    my $tmp_mb = $class->tmp_megabytes_estimated($instrument_data);
    my $mem_mb = 1024 * 16; 
    my $cpus = 4;

    if ($aligner_params and $aligner_params =~ /-t\s*([0-9]+)/) {
        $cpus = $1;
    }

    my $mem_kb = $mem_mb*1024;
    my $tmp_gb = $tmp_mb/1024;

    my $user = getpwuid($<);
    my $queue = 'alignment';
    $queue = 'alignment-pd' if (Genome::Config->should_use_alignment_pd);

    my $host_groups;
    $host_groups = qx(bqueues -l $queue | grep ^HOSTS:);
    $host_groups =~ s/\/\s+/\ /;
    $host_groups =~ s/^HOSTS:\s+//;

    my $select  = "select[ncpus >= $cpus && mem >= $mem_mb && gtmp >= $tmp_gb] span[hosts=1]";
    my $rusage  = "rusage[mem=$mem_mb, gtmp=$tmp_gb]";
    my $options = "-M $mem_kb -n $cpus -q $queue";

    my $required_usage = "-R '$select $rusage' $options";

    #check to see if our resource requests are feasible (This uses "maxmem" to check theoretical availability)
    #factor of four is based on current six jobs per host policy this should be revisited later
    my $select_check = "select[ncpus >= $cpus && maxmem >= " . ($mem_mb * 4) . " && maxgtmp >= $tmp_gb] span[hosts=1]";
    my $select_cmd = "bhosts -R '$select_check' $host_groups | grep ^blade";

    my @selected_blades = qx($select_cmd);

    if (@selected_blades) {
        return $required_usage;
    } else {
        die $class->error_message("Failed to find hosts that meet resource requirements ($required_usage). [Looked with `$select_cmd`]");
    }
}

# TODO copied verbatim from normal bwa, but this may be totally off for bwa mem
sub tmp_megabytes_estimated {
    my $class = shift || die;
    my $instrument_data = shift;

    my $default_megabytes = 90000;


    if (not defined $instrument_data) {
        return $default_megabytes;
    } elsif ($instrument_data->bam_path) {
        my $bam_path = $instrument_data->bam_path;

        my $scale_factor = 3.25; # assumption: up to 3x during sort/fixmate/sort and also during fastq extraction (2x) + bam = 3

        my $bam_bytes = -s $bam_path;
        unless ($bam_bytes) {
            die $class->error_message("Instrument Data " . $instrument_data->id  . " has BAM ($bam_path) but has no size!");
        }

        if ($instrument_data->can('get_segments')) {
            my $bam_segments = scalar $instrument_data->get_segments;
            if ($bam_segments > 1) {
                $scale_factor = $scale_factor / $bam_segments;
            }
        }

        return int(($bam_bytes * $scale_factor) / 1024**2);
    } elsif ($instrument_data->can("calculate_alignment_estimated_kb_usage")) {
        my $kb_usage = $instrument_data->calculate_alignment_estimated_kb_usage;
        return int(($kb_usage * 3) / 1024) + 100; # assumption: 2x for the quality conversion, one gets rm'di after; aligner generates 0.5 (1.5 total now); rm orig; sort and merge maybe 2-2.5
    } else {
        return $default_megabytes;
    }

    return;
}

# override this from AlignmentResult.pm to filter reads with secondary alignment flag (0x100)
sub _check_read_count {
    my ($self) = @_;
    my $fq_rd_ct = $self->_fastq_read_count;
    my $sam_path = Genome::Model::Tools::Sam->path_for_samtools_version($self->samtools_version);

    my $cmd = "$sam_path view -F 256 -c " . $self->temp_staging_directory . "/all_sequences.bam";
    my $bam_read_count = `$cmd`;
    my $check = "Read count from bam: $bam_read_count and fastq: $fq_rd_ct";

    unless ($fq_rd_ct == $bam_read_count) {
        $self->error_message("$check does not match.");
        return;
    }
    $self->status_message("$check matches.");
    return 1;
}

sub _run_aligner {
    my $self = shift;
    my @input_paths = @_;

    # process inputs
    if (@input_paths != 1 and @input_paths != 2) {
        $self->error_message(
            "Expected 1 or 2 input path names. Got: " . Dumper(\@input_paths));
    }
    my $reference_fasta_path = $self->get_reference_sequence_index->full_consensus_path('fa');

    # get temp dir
    my $tmp_dir       = $self->temp_scratch_directory;
    my $log_path      = $tmp_dir . '/aligner.log';
    my $all_sequences = $tmp_dir . '/all_sequences.sam';

    # Verify the aligner and get params.
    my $aligner_version = $self->aligner_version;
    unless (Genome::Model::Tools::Bwa->supports_mem($aligner_version)) {
        die $self->error_message(
            "The pipeline does not support using " .
            "bwa mem with bwa-$aligner_version."
        );
    }
    my $cmd_path = Genome::Model::Tools::Bwa->path_for_bwa_version($aligner_version);
    my $params = $self->decomposed_aligner_params;

    # Verify inputs and outputs.
    for (@input_paths, $reference_fasta_path) {
        die $self->error_message("Missing input '$_'.") unless -e $_;
        die $self->error_message("Input '$_' is empty.") unless -s $_;
    }

    # Run mem
    $self->status_message("Running bwa mem.");

    my $full_command = sprintf '%s mem %s %s %s 2>> %s',
        $cmd_path, $params, $reference_fasta_path,
        (join ' ', @input_paths), $log_path;
    $self->_stream_bwamem($full_command, $all_sequences);

    # Verify the bwa mem logfile.
    unless ($self->_verify_bwa_mem_did_happen($log_path)) {
        die $self->error_message(
            "Error running bwa mem. Unable to verify a successful " .
            "run of bwa mem in the aligner log.");
    }

    # Sort all_sequences.sam.
    $self->status_message("Resorting fixed sam file by coordinate.");
    $self->_sort_sam($all_sequences);

    return 1;
}

# Run bwa mem and stream through AddReadGroupTag
sub _stream_bwamem {
    my ($self, $full_command, $all_sequences) = @_;

    # Open pipe
    $self->status_message("RUN: $full_command");
    $self->status_message("Opening filehandle to stream output.");

    my $bwamem_fh = IO::File->new("$full_command |");

    unless ($bwamem_fh) {
        die $self->error_message(
            "Error running bwa mem. Unable to open filehandle " .
            "to stream bwa mem output.");
    }

    # Add RG tags
    $self->status_message("Starting AddReadGroupTag.");
    my $all_sequences_fh = IO::File->new(">> $all_sequences");

    unless ($all_sequences_fh) {
        die $self->error_message(
            "Error running bwa mem. Unable to open all_sequences.sam " .
            "filehandle for AddReadGroupTag.");
    }

    my $add_rg_cmd = Genome::Model::Tools::Sam::AddReadGroupTag->create(
       input_filehandle  => $bwamem_fh,
       output_filehandle => $all_sequences_fh,
       read_group_tag    => $self->read_and_platform_group_tag_id,
       pass_sam_headers  => 0,
    );

    unless ($add_rg_cmd->execute) {
        die $self->error_message(
            "Error running bwa mem. AddReadGroupTag failed to execute.");
    }

    $all_sequences_fh->close();
    $bwamem_fh->close();
    my $rv = $?;

    # $rv >> 8 reports the actual exit code; it should be 0.
    # $rv & 128 reports whether there was a core dump.
    if ($rv >> 8) {
        die $self->error_message(
            "Error running bwa mem. Expected exit code of '0' " .
            "but got " ($rv >> 8) " instead (\$? set to $rv).");
    }
    if ($rv & 128) {
        die $self->error_message(
            "Error running bwa mem. Detected a coredump from " .
            "bwa mem (\$? set to $rv).");
    }
}

# Sort a sam file.
sub _sort_sam {
    my ($self, $given_sam) = @_;

    my $unsorted_sam = "$given_sam.unsorted";

    unless (move($given_sam, $unsorted_sam)) {
        die $self->error_message(
            "Unable to move $given_sam to $unsorted_sam. " .
            "Cannot proceed with sorting.");
    }

    my $picard_sort_cmd = Genome::Model::Tools::Picard::SortSam->create(
        sort_order             => 'coordinate',
        input_file             => $unsorted_sam,
        output_file            => $given_sam,
        max_records_in_ram     => 2000000,
        maximum_memory         => 8,
        maximum_permgen_memory => 256,
        temp_directory         => $self->temp_scratch_directory,
        use_version            => $self->picard_version,
    );

    unless ($picard_sort_cmd and $picard_sort_cmd->execute) {
        die $self->error_message(
            "Failed to create or execute Picard sort command.");
    }

    unless (unlink($unsorted_sam)) {
        $self->status_message("Could not unlink $unsorted_sam.");
    }

    return $given_sam;
}

sub _verify_bwa_mem_did_happen {
    my ($self, $log_file) = @_;

    unless ($log_file and -e $log_file) {
        $self->error_message("Log file $log_file is does not exist.");
        return;
    }

    unless ($log_file and -s $log_file) {
        $self->error_message("Log file $log_file is empty.");
        return;
    }

    my $line_count = 100;
    my @last_lines = `tail -$line_count $log_file`;

    if (not (
        ($last_lines[-3] =~ /^\[main\] Version:/) and
        ($last_lines[-2] =~ /^\[main\] CMD:/) and
        ($last_lines[-1] =~ /^\[main\] Real time:/) )
    ) {
        $self->error_message("Last lines of $log_file were unexpected. Dumping last $line_count lines.");
        $self->status_message($_) for @last_lines;
        return;
    }
    return 1;
}

sub decomposed_aligner_params {
    my $self = shift;
    my $param_string = $self->aligner_params || '';

    my $param_hash = $self->get_aligner_params_hash($param_string);

    my $cpu_count = $self->_available_cpu_count;
    my $processed_param_string = $self->join_aligner_params_hash($param_hash);

    $self->status_message("[decomposed_aligner_params] cpu count is $cpu_count");
    $self->status_message("[decomposed_aligner_params] bwa mem params are: $processed_param_string");

    # Make sure the thread count argument matches the number of CPUs available.
    if ($param_hash->{t} ne $cpu_count) {
        $param_hash->{t} = $cpu_count;
        my $modified_param_string = $self->join_aligner_params_hash($param_hash);
        $self->status_message("[decomposed_aligner_params] autocalculated CPU requirement, bwa mem params modified: $modified_param_string");
    }

    if (not exists $param_hash->{M}) {
        $param_hash->{M} = '';
        my $modified_param_string = $self->join_aligner_params_hash($param_hash);
        $self->status_message("[decomposed_aligner_params] forcing -M, bwa mem params modified: $modified_param_string");
    }

    my $final_param_string = $self->join_aligner_params_hash($param_hash);

    return $final_param_string;
}

sub aligner_params_for_sam_header {
    my $self = shift;

    my $param_string = $self->aligner_params || '';
    my $param_hash = $self->get_aligner_params_hash($param_string);

    delete $param_hash->{t}; # we don't want cpu count to be part of the sam header

    my $modified_param_string = $self->join_aligner_params_hash($param_hash);

    return "bwa mem $modified_param_string";
}

# helper for decomposed_aligner_params and aligner_params_for_sam_header
sub get_aligner_params_hash {
    my $self = shift;
    my $param_string = shift;

    Getopt::Long::Configure("bundling");

    my %param_hash;
    my $rv = Getopt::Long::GetOptionsFromString($param_string,
        't=i' => \$param_hash{t},
        'k=i' => \$param_hash{k},
        'w=i' => \$param_hash{w},
        'd=i' => \$param_hash{d},
        'r=f' => \$param_hash{r},
        'c=i' => \$param_hash{c},
        'P'   => \$param_hash{P},
        'A=i' => \$param_hash{A},
        'B=i' => \$param_hash{B},
        'O=i' => \$param_hash{O},
        'E=i' => \$param_hash{E},
        'L=i' => \$param_hash{L},
        'U=i' => \$param_hash{U},
        'p'   => \$param_hash{p},
        'R=s' => \$param_hash{R},
        'T=i' => \$param_hash{T},
        'a'   => \$param_hash{a},
        'C'   => \$param_hash{C},
        'H'   => \$param_hash{H},
        'M'   => \$param_hash{M},
        'v=i' => \$param_hash{v},
    );

    die $self->error_message("Failed to parse parameter string: $param_string") unless $rv;

    my @switches = qw(a C H M p P);

    for my $key (keys %param_hash) {
        if (not defined $param_hash{$key}) {
            delete $param_hash{$key};
            next;
        }
        if (grep { $key eq $_ } @switches) {
            if ($param_hash{$key} == 1) {
                $param_hash{$key} = '';
            } else {
                delete $param_hash{$key};
            }
        }
    }

    return \%param_hash;
}

# helper for decomposed_aligner_params and aligner_params_for_sam_header
sub join_aligner_params_hash {
    my $self = shift;
    my $param_hash = shift;

    my @param_list;

    for my $key (sort { $a cmp $b } keys %$param_hash) {
        my $val = $param_hash->{$key};
        push @param_list, "-$key";
        push @param_list, $val if $val;
    }

    return join ' ', @param_list;
}

sub fillmd_for_sam {
    return 1;
}

sub requires_read_group_addition {
    return 0;
}

sub supports_streaming_to_bam {
    return 0;
}

sub multiple_reference_mode {
    return 0;
}

sub accepts_bam_input {
    return 0;
}

# Bwa mem should just find a corresponding Bwa index and symlink it. This is the
# best we can do within the existing framework if we don't want to recreate an
# identical index already created by the 'regular' bwa module.
sub prepare_reference_sequence_index {
    my $class = shift;
    my $refindex = shift;

    my $staging_dir = $refindex->temp_staging_directory;

    $class->status_message("Bwa mem version 0.7.2 is looking for a bwa version 0.7.2 index.");

    Genome::Sys->create_symlink($refindex->reference_build->get_sequence_dictionary("sam"), $staging_dir ."/all_sequences.dict" );

    my $bwa_index = Genome::Model::Build::ReferenceSequence::AlignerIndex->get_or_create(
        reference_build_id => $refindex->reference_build_id,
        aligner_name       => 'bwa',
        #aligner_params     => $refindex->aligner_params, # none of the aligner params should affect the index step so I think this okay
        aligner_version    => $refindex->aligner_version,
        test_name          => $ENV{GENOME_ALIGNER_INDEX_TEST_NAME},
    );

    for my $filepath (glob($bwa_index->output_dir . "/*")){
        my $filename = File::Basename::fileparse($filepath);
        next if $filename eq 'all_sequences.fa';
        next if $filename eq 'all_sequences.dict';
        Genome::Sys->create_symlink($filepath, $staging_dir . "/$filename");
    }

    $bwa_index->add_user(
        label => 'uses',
        user  => $refindex
    );

    return 1;
}

1;

