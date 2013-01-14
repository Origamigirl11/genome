#!/usr/bin/env genome-perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;
use above "Genome";
use Test::More;

use_ok('Genome::ModelGroup') or die;
use_ok('Genome::Model::ReferenceAlignment') or die;
use_ok('Genome::ProcessingProfile::ReferenceAlignment') or die;

my $taxon = Genome::Taxon->create(
    name => 'test taxon', 
    species_name => 'human', 
    domain => 'eukaryota'
);
ok($taxon, 'created test taxon') or die;

my $indiv_1 = Genome::Individual->create(
    name => 'Timmy',
    taxon_id => $taxon->id,
);
ok($indiv_1, 'created test indiv 1') or die;

my $indiv_2 = Genome::Individual->create(
    name => 'Bob',
    taxon_id => $taxon->id,
);
ok($indiv_2, 'created test indiv 2') or die;

my $sample_1 = Genome::Sample->create(
    name => 'test sample',
    source_id => $indiv_1->id,
);
ok($sample_1, 'created test sample 1') or die;

my $sample_2 = Genome::Sample->create(
    name => 'test sample 2',
    source_id => $indiv_2->id,
);
ok($sample_2, 'created test sample 2') or die;

my $pp = make_test_processing_profile();
ok($pp, 'made test processing profile') or die;

my $ref_seq_build = make_test_ref_seq_build($taxon);
ok($ref_seq_build, 'made test ref seq build') or die;

my $model_1 = make_test_model($pp, $sample_1, $ref_seq_build);
ok($model_1, 'created test model 1 using subject ' . $sample_1->__display_name__) or die;

my $model_2 = make_test_model($pp, $sample_2, $ref_seq_build);
ok($model_2, 'created test model 2 using subject ' . $sample_2->__display_name__) or die;

my $model_group = Genome::ModelGroup->create(
    name => 'test model group',
);
ok($model_group, 'created model group') or die;

$model_group->assign_models($model_1, $model_2);
my @models = $model_group->models;
ok(@models == 2, 'added both test model to model group');

my $group_subject = $model_group->infer_group_subject;
isa_ok($group_subject, 'Genome::PopulationGroup', 'model group subject is a population group, as expected');

my $indiv_hash = Genome::PopulationGroup->generate_hash_for_individuals($indiv_1, $indiv_2);
ok($indiv_hash eq $group_subject->member_hash, "population group has both samples' individuals in it");

$model_1->subject($taxon);

$group_subject = $model_group->infer_group_subject;
isa_ok($group_subject, 'Genome::Taxon', "model group subject is now a taxon after changing one model's subject to be a taxon");
ok($group_subject->id eq $taxon->id, "group subject is the test taxon");

my $taxon_2 = Genome::Taxon->create(
    name => 'some other test taxon',
    species_name => 'human',
    domain => 'eukaryota',
);

$model_1->subject($taxon_2);

$group_subject = $model_group->infer_group_subject;
isa_ok($group_subject, 'Genome::Taxon', "model group subject is now a taxon after changing one model's subject to be a taxon");
ok($group_subject->name eq 'unknown', 'group subject is the unknown taxon, as expected');

done_testing();

sub make_test_model {
    my ($pp, $subject, $ref_seq_build) = @_;
    my $model = Genome::Model::ReferenceAlignment->create(
        processing_profile_id => $pp->id,
        subject_id => $subject->id,
        subject_class_name => $subject->class,
        reference_sequence_build_id => $ref_seq_build->id,
    );
    return $model;
}

sub make_test_processing_profile {
    my $pp = Genome::ProcessingProfile::ReferenceAlignment->create(
        name => 'test pp',
        sequencing_platform => 'solexa',
        dna_type => 'genomic dna',
        read_aligner_name => 'bwa',
    );
    return $pp;
}

sub make_test_ref_seq_build {
    my $taxon = shift;
    my $pp = Genome::ProcessingProfile::ImportedReferenceSequence->create(name => 'test ref seq pp');
    return unless $pp;

    my $model = Genome::Model::ImportedReferenceSequence->create(
        processing_profile_id => $pp->id,
        subject_id => $taxon->id,
        subject_class_name => $taxon->class,
        name => 'test ref seq build',
    );

    my $build = Genome::Model::Build::ImportedReferenceSequence->create(
        model_id => $model->id,
    );

    return $build;
}
