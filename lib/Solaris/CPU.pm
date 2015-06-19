use strict;
use warnings;
use v5.18.1;
use feature qw(say);

package Solaris::CPU;

# VERSION

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::ClassAttribute;
with 'MooseX::Log::Log4perl';

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
# CPU ID (vCPU)
has 'id'      => ( isa => 'Num', is => 'ro', required => 1 );
# CPU Description
has 'brand'   => ( isa => 'Str', is => 'ro', required => 1 );
# CPU State
# TODO: Create an enumeration of possible states
has 'state'   => ( isa => 'Str', is => 'ro', required => 1 );
# CORE ID
has 'core_id' => ( isa => 'Num', is => 'ro', required => 1 );
# Chip (Socket) ID
has 'chip_id' => ( isa => 'Num', is => 'ro', required => 1 );
# PG ID (not sure this is that useful at the moment - mpstat uses it)
has 'pg_id'   => ( isa => 'Num', is => 'ro', required => 1 );
# One or more interrupt may be assigned to a CPU
has 'interrupts' =>
                 ( isa => 'ArrayRef|Undef',
                   is  => 'ro',
                 );

=method in_use

Returns 1 if this CPU in use in any of the following ways:

=over 4

=item *

Is handling one or more interrupts

=item *

A thread is bound to this CPU (singly or MCB)

=item *

This CPU is a member of a processor set

=back

=cut

sub in_use {
  my $self = shift;

  if (defined($self->interrupts)) {
    return 1;
  }
  # TODO: Check whether pbound to
  # TODO: Check whether part of a pset

  # If we got this far, this CPU is not in use
  return 0;
}

=method cpu_avail

The logical inverse of B<in_use> above.

=cut

sub cpu_avail {
  my $self = shift;

  return not $self->in_use;
}

=method interrupts_assigned

The count of interrupts (of importance) assigned to this CPU.  Interrupts that
are not actually being used, or have known very low utilization of the CPU are
ignored / not counted.

=cut


sub interrupts_assigned {
  my $self = shift;

  my $iaref = $self->interrupts_for;

  return scalar(@{$iaref});
}

=method oversubscribed

This method will return true if there are too many threads are bound to or too
manyinterrupts assigned to this CPU.

Where "too many" is the subjective > 1.

=cut

sub oversubscribed {
  my $self = shift;

}

__PACKAGE__->meta()->make_immutable();
 
1;
