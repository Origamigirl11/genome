#!/usr/bin/env genome-perl

use strict;
use warnings;
use above "Genome";
use Test::More;

Genome::Report::Email->silent();

$ENV{UR_DBI_NO_COMMIT} = 1;
$ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;

my $vcf_data = <<EOS
##fileformat=VCFv4.1
#CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO	FORMAT
1	10144	.	T	C,G	.	.	.
EOS
;

my $pkg = "Genome::Model::ImportedVariationList::Command::ImportVariants";
use_ok("Genome::Model::ImportedVariationList::Command::ImportDbsnpBuild");

my $reference_sequence_build = Genome::Model::Build::ReferenceSequence->get_by_name('g1k-human-build37');

my $cmd = $pkg->create(
    input_path => "/________nope_/_nono_/_nope.no",
    reference_sequence_build => $reference_sequence_build,
    source_name => "test",
    description => "this will not work!",
    variant_type => "snv",
    format => "vcf",
    version => "2012_06_01",
);

ok(!$cmd->execute, "Importing a nonexisting file is an error");

my $tmpdir = File::Temp::tempdir("/tmp/ImportVariantsTest.XXXXXXX", CLEANUP => 1);
my $vcf_input_path = "$tmpdir/in.vcf";
my $fh = Genome::Sys->open_file_for_writing($vcf_input_path);
$fh->print($vcf_data);
$fh->close;

$cmd = $pkg->create(
    input_path => $vcf_input_path,
    reference_sequence_build => $reference_sequence_build,
    source_name => "test",
    description => "this had better work!",
    variant_type => "snv",
    format => "vcf",
    version => "2012_06_01",
);
ok($cmd->execute, "Imported vcf variants");
isa_ok($cmd->build, "Genome::Model::Build::ImportedVariationList");
ok($cmd->build->snv_result, "The build has a snv result attached");
ok(-s $cmd->build->snvs_vcf, "The snvs_vcf accessor works");
is($cmd->build->source_name, "test", "Source name is set properly");
my $diff = Genome::Sys->diff_file_vs_file($vcf_input_path, $cmd->build->snvs_vcf);
ok(!$diff, 'snv output matched expected result')
    or diag("diff results:\n" . $diff);

$cmd = $pkg->create(
    input_path => $vcf_input_path,
    reference_sequence_build => $reference_sequence_build,
    source_name => "test",
    description => "this had better work!",
    variant_type => "indel",
    format => "vcf",
    version => "2012_06_02",
);
ok($cmd->execute, "Imported vcf variants");
isa_ok($cmd->build, "Genome::Model::Build::ImportedVariationList");
ok($cmd->build->indel_result, "The build has an indel result attached");
is($cmd->build->source_name, "test", "Source name is set properly");

done_testing();
