#!/usr/bin/env genome-perl

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{UR_COMMAND_DUMP_STATUS_MESSAGES} = 1;
};

use strict;
use warnings;

use above 'Genome';

use Test::More;

use_ok('Genome::Site::TGI::Synchronize::Classes::MiscUpdate::IndexIllumina') or die;

my $cnt = 0;

my $solexa = Genome::InstrumentData::Solexa->create(
    id => -100,
    library_id => -101,
    flow_cell_id => 'XXXXXX',
    lane => 2,
    index_sequence => 'GATCGA',
    subset_name => '2-GATCGA',
);

_test_pass(
    subject_property_name => 'analysis_software_version',
    new_value => 'CASAVA'
);

_test_pass(
    subject_property_name => 'filt_clusters',
    new_value => 'CASAVA'
);

_test_pass(
    subject_property_name => 'flow_cell_id',
    new_value => 'YYYYYY'
);


_test_pass(
    subject_property_name => 'index_sequence',
    new_value => 'TGGGGGT',
);
is($solexa->subset_name, '2-TGGGGGT', 'Also updated subset_name on solexa');

_test_pass( # updates subset_name
    subject_property_name => 'lane',
    new_value => 3,
);
is($solexa->subset_name, '3-TGGGGGT', 'Also updated subset_name on solexa');

_test_skip(
   subject_property_name => 'library_id',
    new_value => -202,
);

_test_pass(
    subject_property_name => 'median_insert_size',
    new_value => 100,
);
_test_pass(
    subject_property_name => 'sd_above_insert_size',
    new_value => 50,
);

_test_pass(
    subject_property_name => 'sd_below_insert_size',
    new_value => 50,
);

=comment
MEDIAN_INSERT_SIZE             NUMBER   (7)                     {null} {null}   {null} ok
SD_ABOVE_INSERT_SIZE           NUMBER   (7)                     {null} {null}   {null} ok
SD_BELOW_INSERT_SIZE           NUMBER   (7)                     {null} {null}   {null} ok
TARGET_REGION_SET_NAME         VARCHAR2 (512)                   {null} {null}   {null} ok
=cut

done_testing();

###

sub _test {
    my %params = @_;

    my $new_value = delete $params{new_value};
    my $subject_property_name = delete $params{subject_property_name};
    my $genome_property_name = Genome::Site::TGI::Synchronize::Classes::IndexIllumina->lims_property_name_to_genome_property_name(
        $subject_property_name
    );
    my $misc_update = Genome::Site::TGI::Synchronize::Classes::MiscUpdate->create(
        subject_class_name => 'test.index_illumina',
        subject_id => $solexa->id,
        subject_property_name => uc($subject_property_name),
        editor_id => 'lims',
        edit_date => '2000-01-01 00:00:'.sprintf('%02d', $cnt++),
        old_value => $solexa->$genome_property_name,
        new_value => $new_value,
        description => 'UPDATE',
        is_reconciled => 0,
    );
    ok($misc_update, 'Define misc update');
    isa_ok($misc_update, 'Genome::Site::TGI::Synchronize::Classes::MiscUpdate::IndexIllumina');
    is($misc_update->lims_table_name, 'index_illumina', 'Correct lims table name');
    my $genome_class_name = $misc_update->genome_class_name;
    is($genome_class_name, 'Genome::InstrumentData::Solexa', 'Correct genome class name');
    my $genome_entity = $misc_update->genome_entity;
    ok($genome_entity, 'Got genome entity');
    is($genome_entity->class, $genome_class_name, 'Correct genome entity class name');
    is($genome_entity->id, $solexa->id, 'Correct genome entity id');

    return $misc_update;
}

sub _test_pass {
    my %params = @_;

    my $misc_update = _test(%params);
    ok($misc_update->perform_update, 'Perform update succeeds for PASS');
    is($misc_update->result, 'PASS', 'Correct result after update');
    is(
        $misc_update->status, 
        join(
            "\t", "PASS", "UPDATE", 'test.index_illumina', $solexa->id, lc($misc_update->subject_property_name),
            "'".($misc_update->old_value // 'NA')."'", "'".($misc_update->old_value // 'NULL')."'", "'".$misc_update->new_value."'",
        ),
        'Correct status after update',
    );
    ok($misc_update->is_reconciled, 'Is reconciled');
    ok(!$misc_update->error_message, 'No error after update');
    my $genome_property_name = Genome::Site::TGI::Synchronize::Classes::IndexIllumina->lims_property_name_to_genome_property_name(
        lc($misc_update->subject_property_name)
    );
    is($solexa->$genome_property_name, $misc_update->new_value, "Set ".lc($misc_update->subject_property_name)." on solexa");

    return 1;
}

sub _test_skip {
    my %params = @_;

    my $misc_update = _test(%params);
    ok(!$misc_update->perform_update, 'Perform update fails for SKIP');
    is($misc_update->result, 'SKIP', 'Correct result after update');
    is(
        $misc_update->status, 
        join(
            "\t", "SKIP", "UPDATE", 'test.index_illumina', $solexa->id, lc($misc_update->subject_property_name),
            "'".($misc_update->old_value // 'NA')."'", "'".($misc_update->old_value // 'NULL')."'", "'".$misc_update->new_value."'",
        ),
        'Correct status after update',
    );
    ok(!$misc_update->is_reconciled, 'Is NOT reconciled');
    ok(!$misc_update->error_message, 'No error after skip');
    my $genome_property_name = Genome::Site::TGI::Synchronize::Classes::IndexIllumina->lims_property_name_to_genome_property_name(
        lc($misc_update->subject_property_name)
    );
    is($solexa->$genome_property_name, $misc_update->old_value, "Did NOT set ".lc($misc_update->subject_property_name)." on solexa");

    return 1;
}

