#!/usr/bin/env genome-perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;
use Genome::Utility::Test qw(compare_ok);
use Genome::Test::Factory::Model::ReferenceSequence;
use Genome::Test::Factory::Build;
use Genome::Test::Factory::InstrumentData::Solexa;
use Genome::Test::Factory::InstrumentData::AlignmentResult;
use Sub::Override;

my $pkg = 'Genome::Qc::Tool::Picard::CalculateHsMetrics';
use_ok($pkg);

my $data_dir = __FILE__.".d";

my $output_file = File::Spec->join($data_dir, 'output_file.txt');
my $temp_file = Genome::Sys->create_temp_file_path;

my $reference_sequence_model = Genome::Test::Factory::Model::ReferenceSequence->setup_object();
my $reference_sequence = Genome::Test::Factory::Build->setup_object(
    model_id => $reference_sequence_model->id
);
my $override_seqdict = Sub::Override->new(
    'Genome::Model::Build::ReferenceSequence::get_sequence_dictionary',
    sub {return File::Spec->join($data_dir, 'seqdict.sam');},
);

my $feature_list = Genome::FeatureList->__define__(
    name => 'test',
    reference => $reference_sequence,
    format => 'multi-tracked',
    file_content_hash => '7c380705ec8a78a0e2fa2e0e147c5b80',
);
my $override_file_path = Sub::Override->new(
    'Genome::FeatureList::file_path',
    sub {return File::Spec->join($data_dir, 'feature_list.bed');}
);

my $instrument_data = Genome::Test::Factory::InstrumentData::Solexa->setup_object(
    target_region_set_name => 'test',
);
my $alignment_result = Genome::Test::Factory::InstrumentData::AlignmentResult->setup_object(
    reference_build => $reference_sequence,
    instrument_data => $instrument_data,
);

my $tool = $pkg->create(
    gmt_params => {
        bait_intervals => $temp_file,
        input_file => $temp_file,
        output_file => $output_file,
        target_intervals => $temp_file,
        temp_directory => $temp_file,
        use_version => 1.123,
    },
    alignment_result => $alignment_result,
);
ok($tool->isa($pkg), 'Tool created successfully');

my @expected_cmd_line =(
    'java',
    '-Xmx4096m',
    '-XX:MaxPermSize=64m',
    '-cp',
    '/usr/share/java/ant.jar:/gscmnt/sata132/techd/solexa/jwalker/lib/picard-tools-1.123/CalculateHsMetrics.jar',
    'picard.analysis.directed.CalculateHsMetrics',
    sprintf('BAIT_INTERVALS=%s', $temp_file),
    sprintf('INPUT=%s', $temp_file),
    'MAX_RECORDS_IN_RAM=500000',
    sprintf('OUTPUT=%s', $output_file),
    sprintf('TARGET_INTERVALS=%s', $temp_file),
    sprintf('TMP_DIR=%s', $temp_file),
    'VALIDATION_STRINGENCY=SILENT',
);
is_deeply([$tool->cmd_line], [@expected_cmd_line], 'Command line list as expected');

my %expected_metrics = (
    'pct_bases_greater_than_2x_coverage' => 0,
    'pct_bases_greater_than_10x_coverage' => 0,
    'pct_bases_greater_than_20x_coverage' => 0,
    'pct_bases_greater_than_30x_coverage' => 0,
    'pct_bases_greater_than_40x_coverage' => 0,
    'pct_bases_greater_than_50x_coverage' => 0,
    'pct_bases_greater_than_100x_coverage' => 0,
);
is_deeply({$tool->get_metrics}, {%expected_metrics}, 'Parsed metrics as expected');

compare_ok($tool->bait_intervals, File::Spec->join($data_dir, 'bait.intervals'), 'bait_intervals file as expected');
compare_ok($tool->target_intervals, File::Spec->join($data_dir, 'target.intervals'), 'target_intercals file as expected');

$override_file_path->restore;
$override_seqdict->restore;

done_testing;
