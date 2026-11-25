#!perl -w
use strict;
use warnings;

use Test::More;
use Time::HiRes qw(time);

use DBI;
unshift @INC, 't';
require 'nchar_test_lib.pl';

$| = 1;

my $dbh = db_handle();
if ( !$dbh ) {
    plan skip_all => "Unable to connect to Oracle\n";
}

my ($client_major) = DBD::Oracle::ORA_OCI() =~ /^(\d+)/;
if ( $client_major < 18 ) {
    plan skip_all => "ora_call_timeout needs Oracle client 18c or later\n";
}

my $sleep = $dbh->prepare('BEGIN DBMS_SESSION.SLEEP(?); END;');
if ( !$sleep ) {
    plan skip_all => "DBMS_SESSION.SLEEP is not available: $DBI::errstr\n";
}

plan tests => 11;

$dbh->{ora_call_timeout} = 1000;
is( $dbh->{ora_call_timeout}, 1000, 'ora_call_timeout reads back the value set' );

my $t0 = time;
my $ok = $sleep->execute(3);
my $elapsed = time - $t0;
ok( !$ok, 'a call longer than ora_call_timeout fails' );
is( $DBI::err, 3156, 'it fails with ORA-03156' );
cmp_ok( $elapsed, '<', 2.5, 'it fails at about the limit' );

my ($one) = $dbh->selectrow_array('SELECT 1 FROM dual');
is( $one, 1, 'the connection is usable after the timeout' );

$dbh->{ora_call_timeout} = 0;
ok( $sleep->execute(1), 'ora_call_timeout 0 means no limit' );

{
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    $dbh->{ora_call_timeout} = 1000;
    $dbh->{ora_call_timeout} = undef;
    is( scalar @warnings, 0, 'setting ora_call_timeout to undef does not warn' );
    ok( $sleep->execute(2), 'ora_call_timeout undef means no limit' );
}

foreach my $bad ( -10, 4294967296 ) {
    my $set = eval { $dbh->{ora_call_timeout} = $bad; 1 };
    like(
        $set ? '' : $@,
        qr/ora_call_timeout must be 0 or a positive number of milliseconds/,
        "setting ora_call_timeout to $bad croaks"
    );
}

$dbh->disconnect;

my $stored = eval { $dbh->{ora_call_timeout} = 1000; 1 };
ok( $stored, 'setting ora_call_timeout on a disconnected handle neither dies nor crashes' );
