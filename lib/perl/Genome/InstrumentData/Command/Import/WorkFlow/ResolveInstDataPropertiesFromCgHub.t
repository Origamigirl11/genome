#!/usr/bin/env genome-perl

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{UR_COMMAND_DUMP_STATUS_MESSAGES} = 1;
};

use above "Genome";

use Genome::Utility::Test;
use File::Temp;
use Test::More;

use_ok('Genome::InstrumentData::Command::Import::WorkFlow::ResolveInstDataPropertiesFromCgHub') or die;
my $data_dir = Genome::Utility::Test->data_dir_ok('Genome::InstrumentData::Command::Import', File::Spec->catfile('cghub', 'v2')) or die;
my $metadata_file = File::Spec->join($data_dir, 'metadata.xml');
my $tempdir = File::Temp::tempdir(CLEANUP => 1);
my $source_bam = File::Spec->join($tempdir, 'test.bam'); # no need to link

use_ok('Genome::Model::Tools::CgHub::Query') or die;
sub Genome::Model::Tools::CgHub::Query::execute { 
    my $self = shift;
    return Genome::Sys->create_symlink($metadata_file, $self->xml_file);
}

my $cmd = Genome::InstrumentData::Command::Import::WorkFlow::ResolveInstDataPropertiesFromCgHub->create(
    source => $source_bam,
    instrument_data_properties => [qw/ 
        description=imported
        downsample_ratio=0.7
        import_source_name=TGI
        this=that
        uuid=387c3f70-46e9-4669-80e3-694d450f2919
    /],
);
ok($cmd, "created cmd object");
ok($cmd->execute,"executed command");
is_deeply(
    $cmd->resolved_instrument_data_properties,
    { 
        downsample_ratio => 0.7,
        description => 'imported',
        import_source_name => 'TGI',
        original_data_path => $source_bam,
        this => 'that', 
        analysis_id => '387c3f70-46e9-4669-80e3-694d450f2919',
        tcga_name => 'TCGA-77-8154-10A-01D-2244-08',
        aliquot_id => 'f7de2e89-ee90-4098-b86e-57a489b3a71a',
        target_region_set_name => 'agilent_sureselect_exome_version_2_broad_refseq_cds_only_hs37',
        participant_id => '569691a3-15b4-4b1c-b8b7-b3ad17d0996e',
        sample_id => 'f39b4cc9-9253-4cf9-8827-ebf26af1003a',
        source_md5 => '5d2c5cbfc7420405fd4e8e7491a56dc8',
        source_size => 12322789137,
    },
    'resolved_instrument_data_properties',
);

# ERRORS to test
# required args not in metadata and not given
# target region
# feature list

done_testing();
