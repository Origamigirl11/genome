#!/gsc/bin/perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use File::Basename;
use Test::More;

use_ok("Genome::Model::Tools::Annotate::Sv::FusionTranscripts");

my $base_dir = $ENV{GENOME_TEST_INPUTS}."/Genome-Model-Tools-Annotate-Sv-FusionTranscripts";
my $version = 2;
my $data_dir = "$base_dir/v$version";

my $temp_file = Genome::Sys->create_temp_file_path;
my $fusion_temp_file = dirname($temp_file).'/fusion_transcripts.out';
my $cmd = Genome::Model::Tools::Annotate::Sv->create(
    input_file  => "$base_dir/in.svs",
    fusion_transcripts_output_file => $fusion_temp_file,
    output_file => $temp_file,
    annotation_build_id => 102549985,  #54_36p_v2, human Build36
    annotator_list      => ['FusionTranscripts'],
);

ok($cmd, "Created command");
ok($cmd->execute, "Command executed successfully");

my $expected_file = "$data_dir/expected.out";
ok(-s $temp_file, "Output file created");
my $diff = Genome::Sys->diff_file_vs_file($temp_file, $expected_file);
ok(!$diff, 'output matched expected result') or diag("diff results:\n" . $diff);


my $fusion_expected_file = "$data_dir/fusion_expected.out";
ok(-s $fusion_temp_file, 'fusion output file created');
my $fusion_diff = Genome::Sys->diff_file_vs_file($fusion_temp_file, $fusion_expected_file);
ok(!$fusion_diff, "fusion output matched expected result") or diag("fusion diff results:\n" . $fusion_diff);

done_testing;
