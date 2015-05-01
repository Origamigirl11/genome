#!/usr/bin/env genome-perl

use strict;
use warnings;

use Test::More tests => 4;
use File::Compare;

use above 'Genome';

BEGIN {
        use_ok('Genome::Model::Tools::Snp::GenotypeDetail');
    };

my $dir = Genome::Config::get('test_inputs') . '/Genome-Model-Tools-Snp/GenotypeDetail';

my $test_snp_file = "$dir/test.sam.snp";
my $exp_out_file  = $test_snp_file.'.genotype_detail.ori';

my $tmp_dir =  File::Temp::tempdir('GenotypeDetail-XXXXXX',CLEANUP => 1, TMPDIR => 1);
my $out_file = $tmp_dir .'/test.sam.snp.genotype_detail';

my $snp_gd = Genome::Model::Tools::Snp::GenotypeDetail->create(
    snp_file   => $test_snp_file,
    out_file   => $out_file,
    snp_format => 'sam',
);

isa_ok($snp_gd,'Genome::Model::Tools::Snp::GenotypeDetail');
ok($snp_gd->execute,'execute command ok'. $snp_gd->command_name);
cmp_ok(compare($out_file, $exp_out_file), '==', 0, 'Sam SNP genotype-detail output matches the expected original one.');
