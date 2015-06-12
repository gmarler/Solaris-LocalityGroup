use strict;
use warnings;
use v5.18.1;
use feature qw(say);

package Solaris::CPU::Core;

# VERSION
#
use Moose;
use Moose::Util::TypeConstraints;
use MooseX::ClassAttribute;
with 'MooseX::Log::Log4perl';

use Solaris::CPU;

use namespace::autoclean;

use autodie                             qw(:all);
use Readonly                            qw();

Readonly::Scalar my $KSTAT  => '/bin/kstat';

#
# Class Attribute
#
class_has 'Cache' =>
    ( is      => 'rw',
      isa     => 'HashRef',
      default => sub { {} },
    );

#
# Instance Attributes
#
# CORE ID (vCPU)
has 'id'      => ( isa => 'Num', is => 'ro', required => 1 );

# CPU / vCPU List
# TODO: weaken?
has 'cpus'   => ( # isa      => 'ArrayRef[Solaris::CPU::vCPU]',
                  isa      => 'ArrayRef[Solaris::CPU]|Undef',
                  is       => 'ro',
                  required => 1 );


override BUILDARGS => sub {
  my $self = shift;

  my %args = @_;

  # We're passing in data to build ALL CPU objects for this core,
  # which needs pre-processing
  #
  if (exists($args{'cpu_data'})) {
    my $cpu_data = $args{'cpu_data'};
    delete $args{'cpu_data'};
    my $cpu_aref =
      $self->_build_cpu_objects($cpu_data);
    return { cpus => $cpu_aref, %args };
  }

  return super;
};

sub _build_cpu_objects {
  my ($self,$cpu_data) = @_;

  my @cpu_objs;
  #
  # TODO: Assert that $cpu_data is an aref of CPU data hrefs
  #
  foreach my $ctor_data_href (@$cpu_data) {
    # Whittle this down to what we actually use now
    #say Data::Dumper::Dumper(\$ctor_data_href);
    my %ctor_args = map { $_ => $ctor_data_href->{$_}; }
                    qw( id brand state core_id chip_id pg_id );
    #say Data::Dumper::Dumper(\%ctor_args);
    push @cpu_objs, Solaris::CPU->new( \%ctor_args );
  }

  # Return completed set of CPU objects
  return \@cpu_objs;
  # return undef;
}



sub print {
  my ($self) = shift;
  my $cpus_aref = $self->cpus;
  my $buf;

  foreach my $cpu (@$cpus_aref) {
    $buf .= sprintf("%4d ",$cpu->id);
  }
  say $buf;
}

sub format {
  my ($self) = shift;
  my $cpus_aref = $self->cpus;
  my $buf;

  foreach my $cpu (@$cpus_aref) {
    $buf .= sprintf("%4d ",$cpu->id);
  }
  return $buf;
}

1;




