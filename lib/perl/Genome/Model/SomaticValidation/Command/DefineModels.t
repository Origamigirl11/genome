#!/usr/bin/env genome-perl

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

use above 'Genome';
use Test::More tests => 19;

use Genome::Test::Factory::InstrumentData::Solexa;

my $temp_build_data_dir = File::Temp::tempdir('t_SomaticValidation_Build-XXXXX', CLEANUP => 1, TMPDIR => 1);
my $temp_dir = File::Temp::tempdir('Model-Command-Define-SomaticValidation-XXXXX', CLEANUP => 1, TMPDIR => 1);

use_ok('Genome::Model::SomaticValidation::Command::DefineModels');

my @somvar_models = &setup_somatic_variation_models();
for (@somvar_models) {
    isa_ok($_, 'Genome::Model::SomaticVariation', 'setup fake model');
}

my @snv_files;
for my $i (1..3) {
    my $f = Genome::Sys->create_temp_file_path . '/TEST' . ($i % 2 + 1);
    Genome::Sys->create_directory($f . '/TEST' . $i);
    $f .= '/test_individual' . ($i % 2 + 1) . '.bed';
    Genome::Sys->write_file($f,
        join("\t", 1, $i, $i, 'A', 'G', 'SNP'), "\n",
        join("\t", 1, ($i+100), ($i+100), 'A', 'G', 'SNP'), "\n",
        join("\t", 1, ($i+200), ($i+200), 'A', 'G', 'SNP'), "\n",
    );
    push @snv_files, $f;
}

my $indel_file = Genome::Sys->create_temp_file_path . '/TEST1';
Genome::Sys->create_directory($indel_file);
$indel_file .= '/test_individual1.bed';
Genome::Sys->write_file($indel_file,
    join("\t", 2, 25, 29, 'CTCTT', '-', 'DEL'), "\n",
);


my $listing_file = Genome::Sys->create_temp_file_path;
Genome::Sys->write_file($listing_file,
    "snvs\n",
    join("\n", @snv_files), "\n",
    "indels\n",
    $indel_file, "\n"
);

#Set up a fake feature-list
my $data = <<EOBED
1	10003	10004	A/T
EOBED
;
my $test_bed_file = Genome::Sys->create_temp_file_path;
Genome::Sys->write_file($test_bed_file, $data);
my $test_bed_file_md5 = Genome::Sys->md5sum($test_bed_file);
my $test_targets = Genome::FeatureList->create(
    name => 'test_somatic_validation_feature_list',
    format              => 'true-BED',
    content_type        => 'validation',
    file_path           => $test_bed_file,
    file_content_hash   => $test_bed_file_md5,
    reference_id        => $somvar_models[0]->tumor_model->reference_sequence_build->id,
);
isa_ok($test_targets, 'Genome::FeatureList', 'created test feature-list');

my $model_group = Genome::ModelGroup->create(
    name => 'test_model_for_DefineModels.t',
);

my $cmd = Genome::Model::SomaticValidation::Command::DefineModels->create(
    variant_file_list => $listing_file,
    models => \@somvar_models,
    target => $test_targets,
    design => $test_targets,
    region_of_interest_set => $test_targets,
    new_model_group => $model_group,
);
isa_ok($cmd, 'Genome::Model::SomaticValidation::Command::DefineModels', 'created importer command');

$cmd->dump_status_messages(1);
ok($cmd->execute, 'executed importer command');

is(scalar(@{[$cmd->result_models]}), 2, 'defined expected number of models');
is(scalar(@{[$model_group->models]}), 2, 'both models added to group');

for my $m ($cmd->result_models) {
    ok($m->snv_variant_list, 'snv result attached');
    if($m->subject->name =~ /1/) {
        ok($m->indel_variant_list, 'indel result attached');
    } else {
        ok(!$m->indel_variant_list, 'no indel result attached');
    }
}

my $cmd2 = Genome::Model::SomaticValidation::Command::DefineModels->create(
    models => \@somvar_models,
    target => $test_targets,
    design => $test_targets,
    region_of_interest_set => $test_targets,
    generate_variant_lists => 1,
);
isa_ok($cmd2, 'Genome::Model::SomaticValidation::Command::DefineModels', 'created importer command');

$cmd->dump_status_messages(1);
ok($cmd2->execute, 'executed importer command');

is(scalar(@{[$cmd2->result_models]}), 2, 'defined expected number of models');

for my $m ($cmd2->result_models) {
    ok($m->snv_variant_list, 'snv result attached');
}




sub setup_somatic_variation_models {
    my $test_profile = Genome::ProcessingProfile::ReferenceAlignment->create(
        name => 'test_profile',
        sequencing_platform => 'solexa',
        dna_type => 'cdna',
        read_aligner_name => 'bwa',
        snv_detection_strategy => 'samtools',
    );

    my $test_somvar_pp = Genome::ProcessingProfile::SomaticVariation->create(
        name => 'test somvar pp',
        snv_detection_strategy => 'samtools r599 [--test=1]',
        tiering_version => 1,
    );

    my $annotation_build = Genome::Model::Build::ImportedAnnotation->__define__(
        model_id => '-1',
    );

    my @somvar_models;
    for(1..2) {
        my $test_individual = Genome::Individual->create(
            common_name => 'TEST' . $_,
            name => 'test_individual' . $_,
        );

        my $test_sample = Genome::Sample->create(
            name => 'test_subject' . $_,
            source_id => $test_individual->id,
        );

        my $test_control_sample = Genome::Sample->create(
            name => 'test_control_subject' . $_,
            source_id => $test_individual->id,
        );

        my $test_instrument_data = Genome::Test::Factory::InstrumentData::Solexa->setup_object();

        my $reference_sequence_build = Genome::Model::Build::ReferenceSequence->get_by_name('NCBI-human-build36');

        my $test_model = Genome::Model->create(
            name => 'test_reference_aligment_model_TUMOR' . $_,
            subject_name => 'test_subject' . $_,
            subject_type => 'sample_name',
            processing_profile_id => $test_profile->id,
            reference_sequence_build => $reference_sequence_build,
        );

        my $add_ok = $test_model->add_instrument_data($test_instrument_data);

        my $test_build = Genome::Model::Build->create(
            model_id => $test_model->id,
            data_directory => $temp_build_data_dir,
        );

        my $test_model_two = Genome::Model->create(
            name => 'test_reference_aligment_model_mock_NORMAL' . $_,
            subject_name => 'test_control_subject' . $_,
            subject_type => 'sample_name',
            processing_profile_id => $test_profile->id,
            reference_sequence_build => $reference_sequence_build,
        );

        $add_ok = $test_model_two->add_instrument_data($test_instrument_data);

        my $test_build_two = Genome::Model::Build->create(
            model_id => $test_model_two->id,
            data_directory => $temp_build_data_dir,
        );

        my $somvar_model = Genome::Model::SomaticVariation->create(
            tumor_model => $test_model,
            normal_model => $test_model_two,
            name => 'test somvar model' . $_,
            processing_profile => $test_somvar_pp,
            annotation_build => $annotation_build,
        );
        push @somvar_models, $somvar_model;

        my $somvar_build = Genome::Model::Build::SomaticVariation->__define__(
            model_id => $somvar_model->id,
            data_directory => $temp_build_data_dir,
            tumor_build => $test_build_two,
            normal_build => $test_build,
        );
        my $e = Genome::Model::Event::Build->__define__(
            build_id => $somvar_build->id,
            event_type => 'genome model build',
            event_status => 'Succeeded',
            model_id => $somvar_model->id,
            date_completed => '1999-01-01 15:19:01',
        );

        is($somvar_model->last_complete_build, $somvar_build, 'setup a somatic model with a complete build');

        my $dir = ($temp_dir . '/' . 'fake_samtools_result' . $_);
        Genome::Sys->create_directory($dir);
        my $result = Genome::Model::Tools::DetectVariants2::Result->__define__(
            detector_name => 'the_bed_detector',
            detector_version => 'r599',
            detector_params => '--fake',
            output_dir => Cwd::abs_path($dir),
            id => -2013 + $_,
        );
        $result->lookup_hash($result->calculate_lookup_hash());

        my $data = <<EOBED
1	10003	10004	A/T
2	8819	8820	A/G
EOBED
        ;
        my $bed_file = $dir . '/snvs.hq.bed';
        Genome::Sys->write_file($bed_file, $data);

        $result->add_user(user => $somvar_build, label => 'uses');

    }

    return @somvar_models;
}
