use strict;
use warnings;
use v5.18.1;
use feature qw(say);

package Solaris::LocalityGroup::Leaf;

# VERSION
#
# ABSTRACT: Solaris Locality Group Root abstraction - represents entire system

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::ClassAttribute;
with 'MooseX::Log::Log4perl';
use Data::Dumper               qw();
use Solaris::CPU::Core;
use Solaris::CPU::vCPU;

use namespace::autoclean;

use autodie                             qw(:all);
use Readonly                            qw();


Readonly::Scalar my $KSTAT    => '/bin/kstat';
Readonly::Scalar my $LGRPINFO => '/bin/lgrpinfo';

#
# Instance Attributes
#

has 'id'        => ( isa      => 'Int',
                     is       => 'ro',
                     required => 1,
                   );

# TODO: have both an array of cores, and a hashref of coures with the core ID as
# the keys
has 'cores'     => ( isa => 'HashRef[Solaris::CPU::Core]|Undef',
                     is => 'ro',
                     # init_arg => cpu_info_data,
                   );

has 'cpu_range' => ( isa      => 'ArrayRef[Int]',
                     is       => 'ro',
                     required => 1,
                   );

# TODO: Populate these from below, from the Core or CPU level
has 'cpus'      => ( isa => 'HashRef[Solaris::CPU]|Undef',
                     is  => 'ro',
                   );

override BUILDARGS => sub {
  my $self = shift;

  my %args = @_;

  #say Dumper(\%args);

  # We're passing in data to build ALL cores, which needs pre-processing to
  # whittle it down to just the data for the cores in this leaf
  #
  if (exists($args{'core_data'})) {
    my $cpu_info = $args{'core_data'};
    delete $args{'core_data'};
    my $interrupt_info;
    if (exists($args{'interrupt_data'})) {
      $interrupt_info = $args{'interrupt_data'};
      delete $args{'interrupt_data'};
    }
    my $cores_href =
      $self->_build_core_objects($args{'id'},$args{'cpu_range'}, $cpu_info,
                                 $interrupt_info);
    return { cores => $cores_href, %args };
  }

  return super;
};

# sub BUILD {
#   my $self = shift;
# 
#   my $id = $self->id;
#   say "Building Locality Group Leaf: $id";
# }
#

sub _build_core_objects {
  my $self = shift;
  my $leaf_id        = shift;
  my $cpu_range_aref = shift;
  my $cpu_info       = shift;
  my $interrupt_info = shift;

  my $cpu_first      = $cpu_range_aref->[0];
  my $cpu_last       = $cpu_range_aref->[1];

  my %core_objs;
  #
  # TODO: Assert that $cpu_range_aref is an ARRAY reference
  #       Assert that $cpu_range_aref has 2 numeric elements
  #       Assert that $cpu_info is an aref of CPU data hrefs
  #
  # Get data specific to the CPUs that reside in this leaf
  my @cpu_data = grep { ($_->{id} >= $cpu_first) &&
                        ($_->{id} <= $cpu_last) } @$cpu_info;

  my %interrupt_data = map { $_->{cpu} => $_->{interrupts_for};
                      } @$interrupt_info;
  
  # Gather CPU data by core, sorted by core id, then by CPU id
  my @core_data =
    map { $_->[0] }
    sort { $a->[1] <=> $b->[1] ||
           $a->[2] <=> $b->[2] }
    map { [ $_, $_->{core_id}, $_->{id} ] }
    @cpu_data;

  # Add information on interrupts assigned to individual CPUs, if they exist
  foreach my $core_data (@core_data) {
    if (exists($interrupt_data{$core_data->{id}})) {
      $core_data->{interrupts} = $interrupt_data{$core_data->{id}};
    }
  }
  #say Data::Dumper::Dumper(\@core_data);

  # Build:
  # { core_id => id,
  #   cpus    => [ { cpu_data }, ... ] }
  my %core_ctor;
  foreach my $datum (@core_data) {
    if (not exists($core_ctor{$datum->{core_id}})) {
      $core_ctor{$datum->{core_id}} = [];
      push @{$core_ctor{$datum->{core_id}}}, $datum;
    } else {
      push @{$core_ctor{$datum->{core_id}}}, $datum;
    }
  }

  #foreach my $key (sort keys(%core_ctor)) {
  #  say Data::Dumper::Dumper(\$core_ctor{$key});
  #}
  
  #
  # Then create hashref of Core objects, with the key being the core_id
  #
  foreach my $core_id (sort keys %core_ctor) {
    #say Data::Dumper::Dumper(\$core_ctor{$core_id});
    my $core =
      Solaris::CPU::Core->new( id       => $core_id,
                               cpu_data => $core_ctor{$core_id},
                             );
    $core_objs{$core_id} = $core;
  }

  # Return completed set of Core objects
  #say Data::Dumper::Dumper(\%core_objs);
  return \%core_objs;
}

=head2 PUBLIC Methods

=method core_count

The count of cores in this LG Leaf

=cut

sub core_count {
  my $self = shift;

  my $core_count = scalar(keys %{$self->cores});

  return $core_count;
}

=method cpu_count

The count of CPUs / vCPUs in this core

=cut

sub cpu_count {
  my $self = shift;

  my $cpu_count = 0;
  my @cores = values(%{$self->cores});

  foreach my $core (@cores) {
    $cpu_count += scalar(@{$core->cpus});
  }

  return $cpu_count;
}

=method cpus_avail_for_binding

For this Locality Group Leaf, returns the list of CPUs / vCPUs / strands
available for binding to a processor set, a thread, or an MCB group.

RETURNS: an array reference of CPUs available for binding, if any

=cut

sub cpus_avail_for_binding {
  my $self = shift;
  my $cores_href = $self->cores;
  my @avail_cpus;

  foreach my $core_id (sort { $a <=> $b } keys %$cores_href) {
    push @avail_cpus, @{$cores_href->{$core_id}->cpus_avail_for_binding};
  }

  return \@avail_cpus; 
}


=method print

Print out information on this leaf Locality Group

=cut

sub print
{
  my $self = shift;
  my $cores_href = $self->cores;

  #say Data::Dumper::Dumper($cores_href);

  say "Locality Group: " . $self->id;
  say "CPU RANGE: " . $self->cpu_range->[0] . "-" . $self->cpu_range->[1];
  my $buf = sprintf("%5s: ","CORES");
  foreach my $core_id (sort keys %$cores_href) {
    $buf .= sprintf("\n%6s %8d: [ %40s ]","",
                    $core_id,$cores_href->{$core_id}->format);
    $cores_href->{$core_id}->print_cpus_avail_for_binding;
  }
  say $buf;
}

=method print_cpu_avail_terse

This method is used to print a leaf's ID and the complete list of CPUs available
for binding on a single line - this is the most terse format, and the one most
  likely to be used by consumers looking to bind their threads all in a single
  Locality Group Leaf (which is the only case that makes sense).

=cut

sub print_cpu_avail_terse {
  my $self = shift;
  # TODO: factor out and reimplement in terms of cpus_avail_for_binding() method
  my @avail_cpus;

  my $buf = "LGRP " . $self->id . ": ";

  @avail_cpus = @{$self->cpus_avail_for_binding()};

  $buf .= join(" ", @avail_cpus);
  say $buf;
}

=head1 PRIVATE Methods

=cut

# sub _build_id {
#   my $self     = shift;
#   my $ctor_args = shift;
# 
#   my $id = $ctor_args->{lgrp};
# 
#   say "Building Locality Group Leaf: $id";
# 
#   return $id;
# }

1;
