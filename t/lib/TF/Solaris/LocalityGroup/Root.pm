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

my $mock_files = {
  "T4-4" => { lgrpinfo => "lgrpinfo-T4-4.out",
                 kstat => "kstat-T4-4.out",
            },
  "T5-4" => { lgrpinfo => "lgrpinfo-T5-4.out",
                 kstat => "kstat-T5-4.out",
            },
};

my $mock_output = {
  "T4-4" => { },
  "T5-4" => { },
};

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

  foreach my $mach_type (keys %$mock_files) {
    my $lgrp_file =
      Path::Class::File->new(__FILE__)->parent->parent->parent->parent->parent
                       ->file("data",$mock_files->{$mach_type}->{lgrpinfo})
                       ->absolute->stringify;

    my $kstat_file =
      Path::Class::File->new(__FILE__)->parent->parent->parent->parent->parent
                       ->file("data",$mock_files->{$mach_type}->{kstat})
                       ->absolute->stringify;

    my $lgrp_fh  = IO::File->new($lgrp_file,"<");
    my $kstat_fh = IO::File->new($kstat_file,"<");

    my $lgrpinfo_c = do { local $/; <$lgrp_fh>; };
    my $kstat_c    = do { local $/; <$kstat_fh>; };

    $mock_output->{$mach_type}->{lgrpinfo} = $lgrpinfo_c;
    $mock_output->{$mach_type}->{kstat}    = $kstat_c;
  }

  # TODO: Get rid of this, once we do it properly below...
  $lgrpinfo = $mock_output->{"T4-4"}->{lgrpinfo};
  $kstat    = $mock_output->{"T4-4"}->{kstat};


  # my $stdout = qx{$LGRPINFO -cCG};
  # 
  # my $lgrp_specs_aref = __PACKAGE__->_parse_lgrpinfo($stdout);

  # $stdout = qx{$KSTAT -p 'cpu_info:::/^\(?:brand|chip_id|core_id|cpu_type|pg_id|device_ID|state|state_begin\)\$/'};

  # my $cpu_specs_aref  = __PACKAGE__->_parse_kstat_cpu_info($stdout);

  # $test->{ctor_args}  = $lgrp_specs_aref;
  # $test->{kstat_args} = $cpu_specs_aref;
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

# Test kstat / lgrpinfo without mocking them, live for this machine type
sub test_attrs_live {
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

# Use all saved mocked output of lgrpinfo and kstat to determine if constructor
# works as expected
sub test_constructor_mocked {
  my $test = shift;

  my @mocked_objs;

  foreach my $machtype (keys %$mock_output) {
    $lgrpinfo = $mock_output->{$machtype}->{lgrpinfo};
    $kstat    = $mock_output->{$machtype}->{kstat};
    my $obj   = Solaris::LocalityGroup::Root->new( );
    push @mocked_objs, $obj;
    # TODO: machine specific tests are needed here
  }

  # Are Root objects correct?
  my $ctests = all( isa("Solaris::LocalityGroup::Root"), );
  cmp_deeply(\@mocked_objs, array_each($ctests),
             'Mocked LG leaves are of the proper object type');

  # Are Root objects composed of Leaves?
  my (@mocked_leaf_list);
  foreach my $root (@mocked_objs) {
    my $leaves = $root->lgrps;
    push @mocked_leaf_list, $leaves;
  }
  cmp_deeply(\@mocked_leaf_list, array_each(isa("ARRAY")),
             'Mocked LG Roots are have an array of leaves');
  # ... and are the leaves of the right object type?
  cmp_deeply(\@mocked_leaf_list,
             array_each(array_each(isa("Solaris::LocalityGroup::Leaf"))),
             'Each Mocked LG Root has Leaves that are of the correct object type');
}

# TODO: test_print_cpu_avail_terse_mock, at Root level

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
