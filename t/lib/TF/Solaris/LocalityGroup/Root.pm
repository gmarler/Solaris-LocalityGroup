use v5.18.1;
use feature qw(say);

package TF::Solaris::LocalityGroup::Root;

use File::Temp               qw();
use Readonly                 qw();
use Data::Dumper             qw();
use Carp                     qw(confess);
use Path::Class::File        qw();

use Test::Class::Moose;
with 'Test::Class::Moose::Role::AutoUse';
use Test::Output;

Readonly::Scalar my $KSTAT    => '/bin/kstat';
Readonly::Scalar my $LGRPINFO => '/bin/lgrpinfo';

# MOCK qx{}, backticks calls, so we can pass in known kstat / lgrpinfo from a
# variety of different system types for testing
BEGIN {
  *CORE::GLOBAL::readpipe = \&_mock_readpipe
};

# The global contents of the current lgrpinfo / kstat output file, which will be
# used by _mock_readpipe()
#
our $lgrpinfo;
our $kstat;
# NOTE: Using an aref to guarantee order (like it matters)
my $mocked_output = [
  "T4-4" => { lgrpinfo => "lgrpinfo-T4-4.out",
                 kstat => "kstat-T4-4.out",
            },
];

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

  my $lgrp_file =
    Path::Class::File->new(__FILE__)->parent->parent->parent->parent->parent
                     ->file("data","lgrpinfo-T4-4.out")
                     ->absolute->stringify;

  my $kstat_file =
    Path::Class::File->new(__FILE__)->parent->parent->parent->parent->parent
                     ->file("data","kstat-T4-4.out")
                     ->absolute->stringify;

  #  Test datafiles should exist
  for my $file ( ( $lgrp_file, $kstat_file ) ) {
    #ok( -f $file, "$file should exist");
  }

  my $lgrp_fh  = IO::File->new($lgrp_file,"<");
  my $kstat_fh = IO::File->new($kstat_file,"<");

  $lgrpinfo = do { local $/; <$lgrp_fh>; };
  $kstat    = do { local $/; <$kstat_fh>; };


  my $stdout = qx{$LGRPINFO -cCG};

  my $lgrp_specs_aref = __PACKAGE__->_parse_lgrpinfo($stdout);

  $stdout = qx{$KSTAT -p 'cpu_info:::/^\(?:brand|chip_id|core_id|cpu_type|pg_id|device_ID|state|state_begin\)\$/'};

  my $cpu_specs_aref  = __PACKAGE__->_parse_kstat_cpu_info($stdout);

  $test->{ctor_args}  = $lgrp_specs_aref;
  $test->{kstat_args} = $cpu_specs_aref;
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

sub test_attrs {
  my $test = shift;

  my $obj = Solaris::LocalityGroup::Root->new( );

  isa_ok($obj, 'Solaris::LocalityGroup::Root', 'object is of proper class');

  can_ok($obj, qw( lgrps ) );

  # Test that returned Locality Group Leaves are valid
  my $leaves = $obj->lgrps;
  isa_ok($leaves, 'ARRAY' );

  my @leaves = @{$leaves};
  cmp_deeply(\@leaves, array_each(isa("Solaris::LocalityGroup::Leaf")),
             'LG leaves are of the proper object type');

  stdout_like( sub { $obj->print }, qr/Locality\sGroup:/,
              'printing LG leaves ok');
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
    my $href = { lgrp     => $+{lgroup},
                 cpufirst => $+{cpufirst},
                 cpulast  => $+{cpulast},
               };
    push @ctor_args, $href;
  }

  return \@ctor_args;
}

sub _parse_kstat_cpu_info {
  my $self       = shift;
  my $c          = shift;
  my @ctor_args;

  my (@lines) = split /\n/, $c;

  my (%cpu_ctor_args);

  # Parse each individual property line for this datalink
  foreach my $line (@lines) {
    my ($cpu_id,$key);

    my ($keypart, $value) = split /\s+/, $line;

    ($cpu_id = $keypart) =~ s{^cpu_info:(\d+):.+$}{$1};

    ($key = $keypart) =~ s{^cpu_info:$cpu_id:[^:]+:(\S+)$}{$1};

    $cpu_ctor_args{$cpu_id}->{$key} = $value;
  }

  @ctor_args = map { my $cpu_id = $_;
                    { id => $cpu_id,
                      map {
                        $_ => $cpu_ctor_args{$cpu_id}->{$_};
                      } keys $cpu_ctor_args{$cpu_id},
                    };
                  } keys %cpu_ctor_args;

  return \@ctor_args;
}


sub _mock_readpipe {
  my $cmd = shift;

  if ($cmd =~ m/^\$LGRPINFO/) {
    return $lgrpinfo;
  } elsif ($cmd =~ m/^\$KSTAT/) {
    return $kstat;
  } else {
    confess "NOT IMPLEMENTED";
  }
}

1;
