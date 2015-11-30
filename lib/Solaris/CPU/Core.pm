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
use Term::ANSIColor;

use Solaris::CPU;

use namespace::autoclean;

use autodie                             qw(:all);
use Readonly                            qw();

Readonly::Scalar my $KSTAT  => '/bin/kstat';

# Definition, for each CPU 'brand', for how many instructions can simultaneously
# be 'retired' from the core pipeline per clock cycle
my $exec_per_core = {
  # NOTE: OPL values may NOT be correct
  'SPARC64-VII+'   => 2,  
  'SPARC64-VII'    => 2,
  'UltraSPARC-T2'  => 1,
  'UltraSPARC-T2+' => 1,
  'SPARC-T3'       => 1,
  'SPARC-T4'       => 2,
  'SPARC-T5'       => 2,
};

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
                    qw( id brand state core_id chip_id pg_id interrupts in_pset
                        bindings );
    #say Data::Dumper::Dumper(\%ctor_args);
    push @cpu_objs, Solaris::CPU->new( \%ctor_args );
  }

  # say Data::Dumper::Dumper(\@cpu_objs);
  #foreach my $cpu_obj (@cpu_objs) {
  #  say "CPU " . $cpu_obj->id . " is in a PSET" if ($cpu_obj->in_pset);
  #  say "CPU " . $cpu_obj->id . " has threads BOUND to it" if ($cpu_obj->bindings);
  #}

  # Return completed set of CPU objects
  return \@cpu_objs;
  # return undef;
}


=method $core->print

Print out the CPUs that make up this core instance.

=cut

sub print {
  my ($self) = shift;

  # TODO: Refactor in terms of format() below
  my $cpus_aref = $self->cpus;
  my $buf;

  foreach my $cpu (@$cpus_aref) {
    $buf .= sprintf("%4d ",$cpu->id);
  }
  say $buf;
}

=method $core->format

Format the output of the CPUs that make up this core instance.

Returns the formatted output for emitting / printing later

=cut


sub format {
  my ($self) = shift;
  my $cpus_aref = $self->cpus;
  my $buf;

  foreach my $cpu (@$cpus_aref) {
    $buf .= sprintf("%4d ",$cpu->id);
  }
  return $buf;
}

=method cpus_avail_for_binding

For an individual core, determines how many threads/strands/vCPUs are available
(if any) for use in creating processor sets, pbinding (single CPU), or Multiple
CPU Binding (MCB) purposes.

This is based on the type or "brand" of the core, which determines how many
execution units are simultaneously available to 'retire' code instructions per
clock cycle.  For lowest latency, one should never dedicate or bind more vCPUs
into service than this count per core.

If you don't care about latency, then you can ignore this advice altogether at
your peril.

RETURNS: aref containing CPU IDs available for binding, if any.

=cut

sub cpus_avail_for_binding {
  my ($self) = shift;

  my $core_id   = $self->id;
  my $cpus_aref = $self->cpus;

  # TODO: Assert the 'brand' of all the CPUs in the core are identical - freak
  #       out if not

  # The 'brand' of the CPUs/vCPUs in the core allow us to look up the number of
  # execution units in the core. Just look at the first vCPU for now.
  my $brand = $cpus_aref->[0]->brand;

  unless (exists($exec_per_core->{$brand})) {
    die "Can't determine available execution units in vCPU type [$brand]";
  }

  my $max_avail  = $exec_per_core->{$brand};
  my $in_use     = 0;
  my $curr_avail = $max_avail;

  # See how many vCPUs are in use in the core
  # TODO: if $in_use exceeds $max_avail, flag the core as "oversubscribed"
  #       (factor this out, as it'll likely be used elsewhere too)
  foreach my $cpu_obj (@$cpus_aref) {
    if ($cpu_obj->in_use) {
      $in_use++;
    }
  }

  my $avail_aref = [];
  # say "Core $core_id has $in_use CPUs in use";
  if ($in_use >= $max_avail) {
    # TODO: Make this a warning
    # say "CORE $core_id is " . colored(['red bold'], 'OVERSUBSCRIBED');
    # nothing to do - will already return empty list
  } elsif ($in_use == 0) {
    # No need to check whether CPUs are in use, as none of them are in this case
    for (my $i = 0; $i < scalar(@$cpus_aref); $i++) {
      my $cpu_obj = $cpus_aref->[$i];
      push @$avail_aref, $cpu_obj->id;
      last if (--$curr_avail == 0);
    }
  } elsif ($in_use > 0) {
    # Need to check for CPUs that are in use, and skip over them
    for (my $i = 0; $i < scalar(@$cpus_aref); $i++) {
      my $cpu_obj = $cpus_aref->[$i];
      if ($cpu_obj->cpu_avail) {
        push @$avail_aref, $cpu_obj->id;
      }
      last if (--$curr_avail == 0);
    }
  }

  return $avail_aref;
}

=method print_cpus_avail_for_binding

=cut

sub print_cpus_avail_for_binding {
  my $self = shift;

  my $cpus_aref = $self->cpus_avail_for_binding;

  say "CPUs Available in CORE " . $self->id .
      " [ " . join(" ", @$cpus_aref) . " ]";
}

1;




