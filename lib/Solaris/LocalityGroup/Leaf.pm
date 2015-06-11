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
use Data::Dumper;
use Solaris::CPU::Core;

use namespace::autoclean;

use autodie                             qw(:all);
use Readonly                            qw();


Readonly::Scalar my $KSTAT    => '/bin/kstat';
Readonly::Scalar my $LGRPINFO => '/bin/lgrpinfo';

#
# Instance Attributes
#

has 'cores'     => ( isa => 'HashRef[Solaris::CPU::Core]|Undef',
                     is => 'ro',
                     # init_arg => cpu_info_data,
                   );

has 'cpus'      => ( isa => 'HashRef[Solaris::CPU::vCPU]|Undef',
                     is  => 'ro',
                   );

1;
