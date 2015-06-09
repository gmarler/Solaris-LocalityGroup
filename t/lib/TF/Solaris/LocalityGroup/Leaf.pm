package TF::Solaris::LocalityGroup::Leaf;

use File::Temp               qw();
use Readonly                 qw();
use Data::Dumper             qw();

use Test::Class::Moose;
with 'Test::Class::Moose::Role::AutoUse';

# VERSION
#
# ABSTRACT: Solaris Locality Group Leaf abstraction - Contains cores

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

has 'cores'     => ( isa => 'ArrayRef[Solaris::CPU::Core]|Undef',
                     is => 'ro',
                     builder => '_build_cpu_cores',
                   );

sub _build_cpu_cores {
  my $self = shift;

  return undef;
}


1;
