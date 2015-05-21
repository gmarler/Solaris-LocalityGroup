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


Readonly::Scalar my $KSTAT    => '/bin/kstat';
Readonly::Scalar my $LGRPINFO => '/bin/lgrpinfo';

#
# Instance Attributes
#
# Locality Group Type
has 'type'      => ( isa => enum([ qw( root leaf ) ]), is => 'ro', required => 1 );

# has 'lgrps'     => ( isa => 

sub new_from_lgrpinfo {
  my $self = shift;

  my $stdout = qx{$LGRPINFO -cCG};

  my $specs_aref = __PACKAGE__->_parse_lgrpinfo($stdout);
  my @objs       = map { __PACKAGE__->new(%$_) } @$specs_aref;

  # Add to Class Object Cache attribute, for ease of lookups later
  #foreach my $obj (@objs) {
  #  __PACKAGE__->Cache()->{$obj->id} = $obj;
  #}
  
  # TODO: wantarray() handling
  return \@objs;
}

sub _parse_lgrpinfo {
  my $self       = shift;
  my $c          = shift;
  my @con_args;

  my (@lines) = split /\n/, $c;

  return \@con_args;
}



1;
