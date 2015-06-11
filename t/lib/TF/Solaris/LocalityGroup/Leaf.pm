use v5.18.1;
use feature qw(say);

package TF::Solaris::LocalityGroup::Leaf;

use File::Temp               qw();
use Readonly                 qw();
use Data::Dumper             qw();

use Test::Class::Moose;
with 'Test::Class::Moose::Role::AutoUse';
use Test::Output;

Readonly::Scalar my $KSTAT  => '/bin/kstat';
Readonly::Scalar my $LGRPINFO => '/bin/lgrpinfo';


sub test_startup {
  my ($test) = shift;
  $test->next::method;

  my $logfile_fh   = File::Temp->new();
  my $logfile_name = $logfile_fh->filename;

  diag "Test logging to $logfile_name";

  # Log::Log4perl Configuration in a string ...
  my $conf = qq(
    #log4perl.rootLogger          = DEBUG, Logfile, Screen
    #log4perl.rootLogger          = DEBUG, Screen
    log4perl.rootLogger          = DEBUG, Logfile

    log4perl.appender.Logfile          = Log::Log4perl::Appender::File
    log4perl.appender.Logfile.filename = $logfile_name
    log4perl.appender.Logfile.layout   = Log::Log4perl::Layout::PatternLayout
    log4perl.appender.Logfile.layout.ConversionPattern = [%r] %F %L %m%n

    log4perl.appender.Screen         = Log::Log4perl::Appender::Screen
    log4perl.appender.Screen.stderr  = 0
    log4perl.appender.Screen.layout = Log::Log4perl::Layout::SimpleLayout
  );

  # ... passed as a reference to init()
  Log::Log4perl::init( \$conf );

  #$test->{sockpath} = "/tmp/test_glogserver_sockpath.sock-$$";
  #diag "Test socket path will be $test->{sockpath}";
  #
  my $stdout = qx{$LGRPINFO -cCG};

  my $lgrp_specs_aref = __PACKAGE__->_parse_lgrpinfo($stdout);

  $test->{ctor_args} = $lgrp_specs_aref;
}

sub test_setup {
  my $test = shift;
  my $test_method = $test->test_report->current_method;

  # if ( 'test_server_logfile' eq $test_method->name ) {
  #   $test->test_skip("TODO");
  # } elsif ( 'test_server_connect_disconnect' eq $test_method->name ) {
  #   $test->test_skip("TODO");
  # } elsif ( 'test_server_connect_bad_protocol' eq $test_method->name ) {
  #   $test->test_skip("TODO");
  # } elsif ( 'test_server_rotate_logs' eq $test_method->name ) {
  #   $test->test_skip("TODO");
  # }
}

sub test_empty_constructor {
  my $test = shift;

  dies_ok( sub { Solaris::LocalityGroup::Leaf->new() } );
}

sub test_good_constructor {
  my $test = shift;

  my $ctor_args = $test->{ctor_args};

  my $lgrp_ctor_args = $ctor_args->[0];

  my $leaf = Solaris::LocalityGroup::Leaf->new(
               id        => $lgrp_ctor_args->{'lgrp'},
               cpu_range => [ $lgrp_ctor_args->{cpufirst},
                              $lgrp_ctor_args->{cpulast}, ],
             );

  isa_ok($leaf, 'Solaris::LocalityGroup::Leaf', 'object is of proper class');

  can_ok($leaf, qw( id ) );
}

sub test_print {
  my $test = shift;

  my $ctor_args = $test->{ctor_args};

  my $lgrp_ctor_args = $ctor_args->[0];

  my $leaf = Solaris::LocalityGroup::Leaf->new(
               id        => $lgrp_ctor_args->{'lgrp'},
               cpu_range => [ $lgrp_ctor_args->{cpufirst},
                              $lgrp_ctor_args->{cpulast}, ],
             );

  can_ok($leaf, qw( print ) );

  stdout_like( sub { $leaf->print }, qr/^Locality\sGroup:/,
              'locality group header');
  stdout_like( sub { $leaf->print }, qr/^CPU\sRANGE:\s\d+[-]\d+/m,
              'CPU range line');
}

# Stolen from Solaris::LocalityGroup::Root
sub _parse_lgrpinfo {
  my $self       = shift;
  my $c          = shift;
  my @ctor_args;

  my $re =
    qr{^lgroup \s+ (?<lgroup>\d+) \s+ \(leaf\):\n
       ^ \s+ CPUs: \s+ (?<cpufirst>\d+)-(?<cpulast>\d+)   \n
      }smx;

  while ($c =~ m/$re/gsmx) {
    # say "LGroup: " . $+{lgroup};
    # say "First CPU: " . $+{cpufirst};
    # say "Last  CPU: " . $+{cpulast};
    my $href = { lgrp     => $+{lgroup},
                 cpufirst => $+{cpufirst},
                 cpulast  => $+{cpulast},
               };
    push @ctor_args, $href;
  }

  return \@ctor_args;
}


1;
