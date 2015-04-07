#!/usr/bin/env genome-perl

BEGIN {
    $ENV{UR_COMMAND_DUMP_DEBUG_MESSAGES} = 1;
}

use strict;
use warnings;

use above 'Genome';

require File::Spec;
require Genome::Utility::Test;
use Test::Exception;
use Test::More;

my $class = 'Genome::Model::Tools::CgHub::Metadata';
use_ok($class) or die;

my $data_dir = Genome::Utility::Test->data_dir_ok('Genome::Model::Tools::CgHub');
my $xml_file = File::Spec->join($data_dir, 'metadata.xml');
my $b36_xml_file = File::Spec->join($data_dir, 'metadata.b36.xml');

# Failures 
throws_ok(sub{ $class->create_from_xml; }, qr/create_from_xml but 2 were expected/, 'create failed w/o XML');
throws_ok(sub{ $class->create_from_xml('blah'); }, qr//, 'create failed w/ invalid xml');
throws_ok(sub{ $class->create_from_file('blah'); }, qr/File \(blah\) does not exist/, 'create_from_file failed w/ non existing file');

# Success [b37]
my $uuid = '387c3f70-46e9-4669-80e3-694d450f2919';
my $metadata1 = $class->create_from_file($xml_file);
ok($metadata1, 'create') or die;
ok($metadata1->metadata, 'metadata');
is($metadata1->uuid, $uuid, 'uuid');
ok(
    _test_metadata(
        metadata => $metadata1,
        files => [
            { 
                file_name => 'C508.TCGA-77-8154-10A-01D-2244-08.1.bam',
                file_size => 12322789137,
                checksum => {
                    content => '5d2c5cbfc7420405fd4e8e7491a56dc8',
                    type => 'MD5',
                },
            },
            {
                file_name => 'C508.TCGA-77-8154-10A-01D-2244-08.1.bam.bai',
                file_size => 5731680,
                checksum => {
                    content => '10b2dd0951d76c4813e91e33074d1680',
                    type => 'MD5',
                },
            },
        ],
        instdata_attrs => {
            aliquot_id => 'f7de2e89-ee90-4098-b86e-57a489b3a71a',
            analysis_id => $uuid,
            center_name => 'BI',
            import_source_name => 'BI',
            library_strategy => 'WXS',
            tcga_name => 'TCGA-77-8154-10A-01D-2244-08',
            sample_id => 'f39b4cc9-9253-4cf9-8827-ebf26af1003a',
            uuid => $uuid,
        },
    ),
    'test metadata'
);

# Success - load [b36]
my $uuid2 = 'a1d11d67-4d5f-4db9-a61d-a0279c3c3d4f';
my $metadata2 = $class->create_from_file($b36_xml_file);
ok($metadata2, 'create w/ b36 xml file') or die;
ok($metadata2->metadata, 'metadata');
is($metadata2->uuid, $uuid2, 'uuid');
ok(
    _test_metadata(
        metadata => $metadata2,
        files => [
            {
                file_name => 'TCGA-A6-2674-01A-02W-0831-10_SOLiD.bam',
				file_size => 18604187778,
				checksum => {
                    type => "MD5",
                    content => '0f307401916947ab16e37b225da8c919',
                },
            },
            {
                file_name => 'TCGA-A6-2674-01A-02W-0831-10_SOLiD.bam.bai',
                file_size => 7121464,
                checksum => {
                    type => "MD5",
                    content => '89a44bbea9fcd62e5c5e1a3dc3610014',
                },
            },
        ],
        instdata_attrs => {
            aliquot_id => 'f957194b-6da9-4690-a87d-0051e239bf3f',
            analysis_id => $uuid2,
            center_name => 'BCM',
            import_source_name => 'BCM',
            library_strategy => 'WXS',
            tcga_name => 'TCGA-A6-2674-01A-02W-0831-10',
            sample_id => '8aca008c-f55a-420a-82c7-acd2cca77d85',
            uuid => $uuid2,
        },
    ),
    'test metadata'
);

# Fails to get checksum type/content
throws_ok(sub{ $metadata2->checksum_content_for_file_name(); }, qr/No file name given to get attribute value!/, 'checksum_content_for_file_name fails w/o file name');
throws_ok(sub{ $metadata2->checksum_type_for_file_name(); }, qr/No file name given to get attribute value!/, 'checksum_type_for_file_name fails w/o file name');

done_testing();

###

sub _test_metadata {
    my %params = @_;

    my $metadata = $params{metadata};
    my %instdata_attrs = %{$params{instdata_attrs}};

    # attrs values
    throws_ok(sub{ $metadata->get_attribute_value(); }, qr/No name to get attribute value!/, 'get_attribute_value fails w/o attribute name');
    for my $name ( sort keys %instdata_attrs ) {
        is($metadata->get_attribute_value($name), $instdata_attrs{$name}, "get_attribute_value for $name");
    }

    # files
    my @files = @{$params{files}};
    my @file_names = $metadata->file_names;
    is_deeply(\@file_names, [map { $_->{file_name} } @files], 'file_names');
    is_deeply([$metadata->bam_file_names], [$files[0]->{file_name}], 'bam_file_names');

    # file attrs
    for my $file_name ( @file_names ) {
        my ($file) = grep { $_->{file_name} eq $file_name } @files;
        ok($file, "found file hash for $file_name");
        is(
            $metadata->checksum_type_for_file_name($file_name),
            $file->{checksum}->{type},
            "checksum_content_for_file_name for $file_name",
        );
        is(
            $metadata->checksum_content_for_file_name($file_name),
            $file->{checksum}->{content},
            "checksum_type_for_file_name for $file_name",
        );
        is(
            $metadata->file_size_for_file_name($file_name),
            $file->{file_size},
            "checksum_type_for_file_name for $file_name",
        );
    }

    return 1;
}

