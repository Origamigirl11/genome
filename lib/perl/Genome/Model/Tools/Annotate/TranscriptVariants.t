#!/usr/bin/env genome-perl

use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 9;
use File::Compare;
use above "Genome";

my $test_dir = Genome::Config::get('test_inputs') . '/Genome-Model-Tools-Annotate-TranscriptVariants';
ok(-d $test_dir, "test data dir exists");

my $input = "$test_dir/input";
ok(-e $input, 'input exists');

my $bed_input = __FILE__ . '.bed';
ok(-e $bed_input, 'bed input exists');

my $ref_transcript = "$test_dir/known_output.transcript";
ok(-e $ref_transcript, 'ref transcript exists');

my $iub_input = "$test_dir/iub_input";
ok(-e $iub_input, 'iub input exists');

my $output_base = File::Temp::tempdir(
                'TranscripVariantOutput-XXXXXX',
                TMPDIR => 1,
                CLEANUP => 1);
my $transcript = "$output_base/transcript";

my $command = Genome::Model::Tools::Annotate::TranscriptVariants->create(
    variant_file => $input,
    output_file => $transcript,
    reference_transcripts => "NCBI-human.ensembl/70_37_v5",
);
is($command->execute(),1, "executed transcript variants w/ return value of 1");

ok(-e $transcript, 'transcript output exists');

unlink($transcript);

my $command_bed_file = Genome::Model::Tools::Annotate::TranscriptVariants->create(
    reference_transcripts => "NCBI-human.ensembl/70_37_v5",
    variant_bed_file => $bed_input,
    output_file => $transcript,
);
is($command_bed_file->execute(),1, "executed transcript variants with bed file w/ return value of 1");

my $iub_command = Genome::Model::Tools::Annotate::TranscriptVariants->create(
    reference_transcripts=> "NCBI-human.ensembl/70_37_v5",
    variant_file => $iub_input, 
    output_file => $transcript,
    use_version => 4,
    accept_reference_IUB_codes => 1,
);
is($iub_command->execute(), 1, "executed transcript variants version 4 with variant containing IUB reference");
