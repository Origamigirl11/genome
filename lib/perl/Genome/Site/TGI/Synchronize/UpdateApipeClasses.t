#! /gsc/bin/perl

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{UR_COMMAND_DUMP_STATUS_MESSAGES} = 1;
}

use strict;
use warnings;

use above 'Genome';

use Data::Dumper 'Dumper';
use Test::More;

use_ok('Genome::Site::TGI::Synchronize::UpdateApipeClasses') or die;
use_ok('Genome::Site::TGI::Synchronize::Classes::Dictionary') or die;

class Iterator {
    has => [
        objects => { is_many => 1, },
        position => { is => 'Integer', default_value => -1, },
    ],
};
sub Iterator::_inc_position {
    my $self = shift;
    return $self->position( $self->position + 1 );
};
sub Iterator::next {
    my $self = shift;
    my $position = $self->_inc_position;
    return ($self->objects)[$position];
};

class Transaction {};
sub Transaction::commit { return 1; };
{
    no warnings;
    use UR::Context::Transaction;
    *UR::Context::Transaction::begin = sub{ return Transaction->create; };
    *Genome::InstrumentData::Microarray::update_genotype_file = sub{ return 1; };
}

my $uac = Genome::Site::TGI::Synchronize::UpdateApipeClasses->create();
ok($uac, 'create');
my $i = -100;
ok(init(), 'init') or die;
ok($uac->execute, 'execute');

ok(verify(), 'verify') or die;

done_testing();

###

sub init {
    diag("INIT...");
    my @lims_objects;
    for my $entity_name ( Genome::Site::TGI::Synchronize::Classes::Dictionary->entity_names ) {
        my $lims_class = Genome::Site::TGI::Synchronize::Classes::Dictionary->lims_class_for_entity_name($entity_name);
        eval "use $lims_class";
        warn $@ if $@;
        my @properties_to_copy = $lims_class->properties_to_copy;

        my @lims_objects = _define_lims_objects($lims_class);
        is(@lims_objects, 2, "create 2 lims '$entity_name' objects") or die;

        if ( $entity_name =~ /^instrument data/ ) {
            for my $lims_object ( @lims_objects ) {
                # FIXME
                my $file = $ENV{GENOME_TEST_INPUTS} . '/Genome-InstrumentData-Microarray/test_genotype_file1';
                $uac->instrument_data_with_successful_pidfas->{ $lims_object->id } = $file;
            }
        }

        my @genome_objects = (
            $lims_objects[$#lims_objects]->create_in_genome,
        );
        is(@genome_objects, 1, "create 1 genome '$entity_name' objects") or die;

        no strict;
        *{$lims_class  .'::create_iterator'} = sub{ 
            my ($class, %params) = @_;
            return Iterator->create(objects => [ %params ? $lims_objects[0] : @lims_objects ]); 
        };

        my $genome_class_for_comparison = $lims_class->genome_class_for_comparison;
        eval "use $genome_class_for_comparison";
        warn $@ if $@;
        *{$genome_class_for_comparison.'::create_iterator'} = sub{
            return Iterator->create(objects => \@genome_objects); 
        };
    }

    return 1;
}

sub _define_lims_objects {
    my ($lims_class) = @_;

    my $entity_name = $lims_class->entity_name;
    $entity_name =~ s/ /_/g;
    my $method = '_define_lims_'.$entity_name;
    if ( main->can($method) ) {
        no strict;
        return $method->($lims_class);
    }

    return (
        $lims_class->create( map { $_ => --$i } $lims_class->properties_to_copy ),
        $lims_class->create( map { $_ => --$i } $lims_class->properties_to_copy ),
    );
}

sub _define_lims_population_group {
    my ($lims_class) = @_;

    my %properties = map {
        $_ => --$i,
    } $lims_class->properties_to_copy;
    delete $properties{member_ids};

    my @lims_objects = ( $lims_class->create(%properties) );
    $properties{id} = --$i;
    push @lims_objects, $lims_class->create(%properties);

    return @lims_objects;
}

sub _define_lims_instrument_data_microarray {
    my ($lims_class) = @_;

    my $sample = Genome::Sample->__define__(id => -22, name => '__TEST_SAMPLE__');
    my %properties = ( map { $_ => --$i } $lims_class->properties_to_copy );
    $properties{sample_id} = $sample->id;
    $properties{sample_name} = $sample->name;
    $properties{genotype_file} = $ENV{GENOME_TEST_INPUTS} . '/Genome-InstrumentData-Microarray/test_genotype_file1';

    my @lims_objects = ( $lims_class->create(%properties) );
    $properties{id} = --$i;
    push @lims_objects, $lims_class->create(%properties);

    return @lims_objects;
}

sub _define_lims_instrument_data_454 {
    my ($lims_class) = @_;

    my @lims_objects = (
        $lims_class->create( map { $_ => --$i } $lims_class->properties_to_copy ),
        $lims_class->create( map { $_ => --$i } $lims_class->properties_to_copy ),
    );

    my $file = $ENV{GENOME_TEST_INPUTS} . '/Genome-InstrumentData-Microarray/test_genotype_file1';
    map { $_->sff_file($file) } @lims_objects;

    return @lims_objects;
}

sub _define_lims_analysis_project_instrument_data {
    my ($lims_class) = @_;

    my %properties = map {
        $_ => --$i,
    } $lims_class->properties_to_copy;
    my $ii_iterator = Genome::Site::TGI::Synchronize::Classes::IndexIllumina->create_iterator;
    $properties{instrument_data_id} = $ii_iterator->next->id;

    my @lims_objects = ( $lims_class->create(%properties) );
    $properties{analysis_project_id} = --$i;
    push @lims_objects, $lims_class->create(%properties);

    return @lims_objects;
}

sub verify {
    diag("VERIFY...");
    for my $entity_name ( Genome::Site::TGI::Synchronize::Classes::Dictionary->entity_names ) {
        my $lims_class = Genome::Site::TGI::Synchronize::Classes::Dictionary->lims_class_for_entity_name($entity_name);
        my $genome_class = $lims_class->genome_class_for_create($entity_name);
        my $iterator = $lims_class->create_iterator;
        my ($lims_object_cnt, $genome_object_cnt) = (qw/ 0 0 /);
        while ( my $lims_object = $iterator->next ) {
            $lims_object_cnt++;
            my (%get_params, @properties_to_copy);
            if ( $entity_name =~ /^project / ) {
                %get_params = (
                    project_id => $lims_object->project_id,
                    entity_id => $lims_object->entity_id,
                    entity_class_name => $lims_object->entity_class_name,
                    label => $lims_object->label,
                );
                @properties_to_copy = keys %get_params;
            }
            elsif ( $entity_name eq 'analysis project instrument data' ) {
                %get_params = (
                    analysis_project_id => $lims_object->analysis_project_id,
                    instrument_data_id => $lims_object->instrument_data_id,
                );
                @properties_to_copy = keys %get_params;
            }
            else {
                %get_params = (id => $lims_object->id);
                @properties_to_copy = $lims_object->properties_to_copy;
            }
            my $genome_object = $genome_class->get(%get_params);
            $genome_object_cnt++ if $genome_object;
            my $ok = 0;
            for my $property ( @properties_to_copy ) {
                my $genome_value = eval{ $genome_object->$property; };
                $genome_value = eval{
                    $genome_object->attributes(attribute_label => $property)->attribute_value; 
                } if not defined $genome_value;
                $ok++ if $genome_value eq $lims_object->$property;
            }
            is($ok, @properties_to_copy, 'properties match');
        }
        is($genome_object_cnt, $lims_object_cnt, "correct number of genome '$entity_name' objects!");
    }

    return 1;
}

