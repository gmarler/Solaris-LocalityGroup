use strict;
use warnings;
use v5.18.1;
use feature qw(say);

package Solaris::LocalityGroup;

# VERSION
#
# ABSTRACT: Solaris Locality Group (NUMA node) abstraction

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::ClassAttribute;
with 'MooseX::Log::Log4perl';

use namespace::autoclean;

use autodie                             qw(:all);
use Readonly                            qw();


Readonly::Scalar my $KSTAT    => '/bin/kstat';
Readonly::Scalar my $LGRPINFO => '/bin/lgrpinfo';

#
# Instance Attributes
#


1;
