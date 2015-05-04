#!/usr/bin/env genome-perl

use strict;
use warnings;

use Test::More tests => 1;

require Genome::Env;

subtest 'set_default_values' => sub {
    plan tests => 4;

    subtest 'set env without default' => sub {
        plan tests => 2;
        no warnings 'once', 'redefine';
        my $var = 'GENOME_WITHOUT_DEFAULT';
        local $ENV{$var} = '42';
        local *Genome::Env::allowed_modules = sub { 'Genome::Env::' . $var };
        is($ENV{$var}, 42, 'env var is set before calling set_default_values');
        Genome::Env::set_default_values();
        is($ENV{$var}, 42, 'env var is still set after calling set_default_values');
    };

    subtest 'set env with default' => sub {
        plan tests => 2;
        no warnings 'once', 'redefine';
        my $var = 'GENOME_WITH_DEFAULT';
        local $ENV{$var} = 42;
        local *Genome::Env::allowed_modules = sub { 'Genome::Env::' . $var };
        no strict 'refs';
        local *{"Genome::Env::${var}::default_value"} = sub { 2 * $ENV{$var} };
        is($ENV{$var}, 42, 'env var is set before calling set_default_values');
        Genome::Env::set_default_values();
        is($ENV{$var}, 42, 'env var is still set after calling set_default_values');
    };

    subtest 'unset env without default' => sub {
        plan tests => 2;
        no warnings 'once', 'redefine';
        my $var = 'GENOME_WITHOUT_DEFAULT';
        local $ENV{$var};
        local *Genome::Env::allowed_modules = sub { 'Genome::Env::' . $var };
        ok(!defined($ENV{$var}), 'env var is not set before calling set_default_values');
        Genome::Env::set_default_values();
        ok(!defined($ENV{$var}), 'env var is not set after calling set_default_values');
    };

    subtest 'unset env with default' => sub {
        plan tests => 2;
        no warnings 'once', 'redefine';
        my $var = 'GENOME_WITH_DEFAULT';
        local $ENV{$var};
        local *Genome::Env::allowed_modules = sub { 'Genome::Env::' . $var };
        no strict 'refs';
        local *{"Genome::Env::${var}::default_value"} = sub { 42 };
        ok(!defined($ENV{$var}), 'env var is not set before calling set_default_values');
        Genome::Env::set_default_values();
        is($ENV{$var}, 42, 'env var is set after calling set_default_values');
    };
};
