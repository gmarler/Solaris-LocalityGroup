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
has 'cpus'   => ( isa => 'ArrayRef[Solaris::CPU::vCPU]', is => 'ro',
                  required => 1 );



1;




