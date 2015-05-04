#!/usr/bin/env genome-perl

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
}

use strict;
use warnings;

use above 'Genome';

use Genome::InstrumentData::InstrumentDataTestObjGenerator;
use Test::More;

my $bam_path = Genome::Config::get('test_inputs') . '/Genome-InstrumentData-AlignmentResult-Bwa/input.bam';

use_ok('Genome::InstrumentData::AlignmentResult');
# Test Intermediate AR Class
class Genome::InstrumentData::IntermediateAlignmentResult::Tester {
    is => ['Genome::InstrumentData::IntermediateAlignmentResult'],
};
sub Genome::InstrumentData::IntermediateAlignmentResult::Tester::_run_aligner {
    my $self = shift;
    # Copy bam
    my $copy_ok = Genome::Sys->copy_file($bam_path, $self->temp_staging_directory.'/all_sequences.bam');
    ok($copy_ok, 'copied bam');
    return 1;
}
# overload these in base IAR to return ours
our $IAR = Genome::InstrumentData::IntermediateAlignmentResult::Tester->__define__;
sub Genome::InstrumentData::IntermediateAlignmentResult::create { return $IAR; }
sub Genome::InstrumentData::IntermediateAlignmentResult::get_or_create { return $IAR; }
sub Genome::InstrumentData::IntermediateAlignmentResult::get_with_lock { return $IAR; }

# Test AR Class
class Genome::InstrumentData::AlignmentResult::Tester {
    is => 'Genome::InstrumentData::AlignmentResult::WithIntermediateResults',
};
sub Genome::InstrumentData::AlignmentResult::Tester::_run_aligner { 
    my $self = shift;

    # Test get_or_create_intermediate_result_for_params
    ok(!eval{$self->get_or_create_intermediate_result_for_params();}, 'failed to get or create iar w/o params');
    ok(!eval{$self->get_or_create_intermediate_result_for_params({});}, 'failed to get or create iar w/o params');
    ok(!eval{$self->get_or_create_intermediate_result_for_params('params');}, 'failed to get or create iar w/ invalid params');
    my $iar = $self->get_or_create_intermediate_result_for_params({
            aligner_name => 'tester',
        });
    $IAR = $iar;
    is($iar, $IAR, 'get or create iar');

    # Copy bam
    my $copy_ok = Genome::Sys->copy_file($bam_path, $self->temp_staging_directory.'/all_sequences.bam');
    ok($copy_ok, 'copied bam');

    return 1;
};
sub Genome::InstrumentData::AlignmentResult::Tester::aligner_params_for_sam_header { 'align me bro!' };
sub Genome::InstrumentData::AlignmentResult::Tester::estimated_kb_usage { 0 };
sub Genome::InstrumentData::AlignmentResult::Tester::fillmd_for_sam { 0 };
sub Genome::InstrumentData::AlignmentResult::Tester::requires_fastqs_to_align { 0 };

my $inst_data = Genome::InstrumentData::InstrumentDataTestObjGenerator::create_solexa_instrument_data($bam_path);
ok($inst_data, 'create inst data');
my $reference_model = Genome::Model::ImportedReferenceSequence->get(name => 'TEST-human');
ok($reference_model, "got reference model");
my $reference_build = $reference_model->build_by_version('1');
ok($reference_build, "got reference build");

my $alignment_result = Genome::InstrumentData::AlignmentResult::Tester->create(
    id => -1337,
    instrument_data => $inst_data,
    reference_build => $reference_build,
    aligner_name => 'tester',
    aligner_version => '1',
    aligner_params => '',
);
ok($alignment_result, 'defined alignment result');
isa_ok($alignment_result, 'Genome::InstrumentData::AlignmentResult::Tester');

# Check that the iar is deleted
my @users = Genome::SoftwareResult::User->get(user => $alignment_result, label => 'intermediate result');
ok(!@users, 'alignment result is not using any intermediate results');
isa_ok($IAR, 'UR::DeletedRef', 'intermediate result deleted');

done_testing();
