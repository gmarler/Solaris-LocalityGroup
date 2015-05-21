use strict;
use warnings;
use v5.18.1;
use feature qw(say);

package Solaris::LocalityGroup;

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
# Instance Attributes
#
# Locality Group Type
has 'type'      => ( isa => enum([ qw( root leaf ) ]), is => 'ro', required => 1 );


1;
