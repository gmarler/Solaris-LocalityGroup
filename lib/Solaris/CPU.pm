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
# Whether this CPU is in use or not
# TODO: make this an ArrayRef of different "use types" (interrupt, squeue
#       thread, pbound, MCB bound), so we also get a count of the use for
#       determining oversubscription
has 'in_use'  => ( isa => 'Bool',
                   traits => ['Bool'],
                   is => 'rw',
                   default => 0,
                   handles => {
                     cpu_avail => 'not',
                   },
                 );


__PACKAGE__->meta()->make_immutable();
 
1;
