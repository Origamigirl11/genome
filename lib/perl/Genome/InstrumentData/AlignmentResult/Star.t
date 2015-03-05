#!/usr/bin/env genome-perl

use strict;
use warnings;

use Test::More;
use Genome::Utility::Test qw(compare_ok);

BEGIN {
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{UR_DBI_NO_COMMIT} = 1;
};

use above 'Genome';
use Genome::Test::Factory::SoftwareResult::User;
use_ok('Genome::InstrumentData::AlignmentResult::Star');

my $VERSION = 2;

my $aligner_name  = "star";
my $ar_base_class = 'Genome::InstrumentData::AlignmentResult';
my $subclass_name = $ar_base_class->_resolve_subclass_name_for_aligner_name($aligner_name);

my $aligner_tools_class_name    = 'Genome::Model::Tools::' . $subclass_name;
my $alignment_result_class_name = $ar_base_class. '::' . $subclass_name;

my $samtools_version = 'r982';
my $picard_version   = '1.85';
my $aligner_version  = '2.3.1z1';

my $FAKE_INSTRUMENT_DATA_ID = -123456;

my $reference_model = Genome::Model::ImportedReferenceSequence->get(name => 'TEST-human');
ok($reference_model, "got reference model");

my $reference_build = $reference_model->build_by_version('1');
ok($reference_build, "got reference build");

my $result_users = Genome::Test::Factory::SoftwareResult::User->setup_user_hash(
    reference_sequence_build => $reference_build,
);

my $temp_reference_index = Genome::Model::Build::ReferenceSequence::AlignerIndex->create(
    reference_build => $reference_build, 
    aligner_version => $aligner_version, 
    aligner_name    => $aligner_name, 
    aligner_params  => '',
);

my @instrument_data = generate_fake_instrument_data();

my @params = (
     aligner_name     =>$aligner_name,
     aligner_version  =>$aligner_version,
     samtools_version =>$samtools_version,
     picard_version   =>$picard_version,
     reference_build  => $reference_build,
     instrument_data_id => [map($_->id, @instrument_data)],
     test_name        => 'star_unit_test',
);

my $alignment_result = Genome::InstrumentData::AlignmentResult::Star->create(
    @params,
    _user_data_for_nested_results => $result_users,
);

isa_ok($alignment_result, $ar_base_class.'::Star', 'produced alignment result');

my $test_bam = File::Spec->join($alignment_result->output_dir, 'all_sequences.bam');
my $test_sam = File::Spec->join($alignment_result->output_dir, 'all_sequences.sam');

system "samtools view -h $test_bam > $test_sam";

my $expected_dir = Genome::Utility::Test->data_dir_ok('Genome::InstrumentData::AlignmentResult::Star', $VERSION);

for my $file (map{'all_sequences.'.$_}qw(bam.flagstat sam)) {
    my $path = File::Spec->join($alignment_result->output_dir, $file);
    my $expected_path = File::Spec->join($expected_dir, $file);
    compare_ok($path, $expected_path, $file . ' matches expected result');
}

my $index_file = 'all_sequences.bam.bai';
my $path = File::Spec->join($alignment_result->output_dir, $index_file);
my $expected_path = File::Spec->join($expected_dir, $index_file);
my $diff = Genome::Sys->diff_file_vs_file($path, $expected_path);
ok(!$diff, $index_file . ' matches expected result') or diag("diff:\n". $diff);

my $existing_alignment_result = Genome::InstrumentData::AlignmentResult::Star->get_or_create(
    @params,
    users => $result_users
);
is($existing_alignment_result, $alignment_result, 'got back the previously created result');

unlink 'Log.out' if -e 'Log.out';

done_testing();


sub generate_fake_instrument_data {
    my $fastq_directory = File::Spec->join($ENV{GENOME_TEST_INPUTS}, 'Genome-InstrumentData-Align-Maq', 'test_sample_name');

    my @instrument_data;
    my $i = 0;

    my $instrument_data = Genome::InstrumentData::Solexa->create(
        id => $FAKE_INSTRUMENT_DATA_ID + $i,
        sequencing_platform => 'solexa',
        flow_cell_id => '12345',
        lane => 4 + $i,
        median_insert_size => '22',
        sd_insert_size => '100',
        clusters => '600',
        read_length => '50',
        run_name => 'test_run_name',
        subset_name => 4 + $i,
        run_type => 'Paired End Read 2',
        gerald_directory => $fastq_directory,
        bam_path => File::Spec->join($ENV{GENOME_TEST_INPUTS}, 'Genome-InstrumentData-AlignmentResult-Bwa', 'input.bam'),
        library_id => '2792100280',
    );

    isa_ok($instrument_data, 'Genome::InstrumentData::Solexa');
    push @instrument_data, $instrument_data;
    
    return @instrument_data;
}
