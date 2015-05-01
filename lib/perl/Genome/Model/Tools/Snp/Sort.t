#!/usr/bin/env genome-perl

use strict;
use warnings;

use Test::More tests => 4;
use File::Compare;

use above 'Genome';

BEGIN {
        use_ok('Genome::Model::Tools::Snp::Sort');
    };

my $test_snp_file = Genome::Config::get('test_inputs') . '/Genome-Model-Tools-Snp/Sort/test.snp';
my $expected_out_file = Genome::Config::get('test_inputs') . '/Genome-Model-Tools-Snp/Sort/test.out';

my $tmp_dir =  File::Temp::tempdir('gt-snp-sort-XXXXXX',CLEANUP => 1, TMPDIR => 1);
my $output_file = $tmp_dir .'/test.out';
my $snp_sorter = Genome::Model::Tools::Snp::Sort->create(
                                                         snp_file => $test_snp_file,
                                                         output_file => $output_file,
                                                     );
isa_ok($snp_sorter,'Genome::Model::Tools::Snp::Sort');
ok($snp_sorter->execute,'execute command '. $snp_sorter->command_name);
ok(!compare($expected_out_file,$output_file),'sorted output file matches expected output');
