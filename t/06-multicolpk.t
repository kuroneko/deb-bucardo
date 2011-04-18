#!perl

## Test of multi-col PK replication

use 5.008003;
use strict;
use warnings;
use Data::Dumper;
use lib 't','.';
use DBD::Pg;
use Test::More 'no_plan';

use BucardoTesting;
my $bct = BucardoTesting->new() or BAIL_OUT "Creation of BucardoTesting object failed\n";
$location = 'fullcopy';

use vars qw/$SQL $sth $t $i $result $count %sql %val %pkey/;

pass("*** Beginning 'fullcopy' tests");

## Prepare a clean Bucardo database on A
my $dbhA = $bct->blank_database('A');
my $dbhX = $bct->setup_bucardo(A => $dbhA);

## Server A is the master, the rest are slaves
my $dbhB = $bct->blank_database('B');
my $dbhC = $bct->blank_database('C');

$dbhA->do(qq{ALTER TABLE bucardo_test1 DROP CONSTRAINT bucardo_test1_pkey});
$dbhA->do(qq{ALTER TABLE bucardo_test1 ADD CONSTRAINT bucardo_test1_pkey2 PRIMARY KEY (data1,inty)});
$dbhA->commit();

$dbhB->do(qq{ALTER TABLE bucardo_test1 DROP CONSTRAINT bucardo_test1_pkey});
$dbhB->do(qq{ALTER TABLE bucardo_test1 ADD CONSTRAINT bucardo_test1_pkey2 PRIMARY KEY (data1,inty)});
$dbhB->commit();

## Tell Bucardo about these databases
$bct->add_test_databases('A B C');

## Create a herd for 'A' and add all test tables to it
$bct->add_test_tables_to_herd('A', 'testherd1');

## Create a new sync to fullcopy from A to B
$t=q{Add sync works};
$i = $bct->ctl("add sync multicoltest source=testherd1 type=pushdelta targetdb=B");
like($i, qr{Added sync}, $t);

$SQL = "SELECT * FROM sync";
my $info = $dbhX->selectall_arrayref($SQL);
$bct->restart_bucardo($dbhX);

$dbhX->do('LISTEN bucardo_syncdone_multicoltest');
$dbhX->commit();

for my $table (sort keys %tabletype) {

    my $type = $tabletype{$table};
    my $val = $val{$type}{1};
    if (!defined $val) {
        BAIL_OUT "Could not determine value for $table $type\n";
    }

    $pkey{$table} = $table =~ /test5/ ? q{"id space"} : 'id';

    $SQL = $table =~ /0/
        ? "INSERT INTO $table($pkey{$table}) VALUES (?)"
            : "INSERT INTO $table($pkey{$table},data1,inty) VALUES (?,'one',1)";
    $sql{insert}{$table} = $dbhA->prepare($SQL);
    if ($type eq 'BYTEA') {
        $sql{insert}{$table}->bind_param(1, undef, {pg_type => PG_BYTEA});
    }
    $val{$table} = $val;

    $sql{insert}{$table}->execute($val{$table});

    last; ## Just the first table for now
}

$dbhA->commit();

sub test_empty_drop {
    my ($table, $dbh) = @_;
    my $DROPSQL = 'SELECT * FROM droptest';
    my $line = (caller)[2];
    $t=qq{ Triggers and rules did NOT fire on remote table $table};
    $result = [];
    bc_deeply($result, $dbhB, $DROPSQL, $t, $line);
}

for my $table (sort keys %tabletype) {
    $t=qq{ Second table $table still empty before commit };

    $SQL = $table =~ /0/
        ? "SELECT $pkey{$table} FROM $table"
            : "SELECT $pkey{$table},data1 FROM $table";
    $result = [];
    bc_deeply($result, $dbhB, $SQL, $t);

    $t=q{ After insert, trigger and rule both populate droptest table };
    my $qtable = $dbhX->quote($table);
    my $LOCALDROPSQL = $table =~ /0/
        ? "SELECT type,0 FROM droptest WHERE name = $qtable ORDER BY 1,2"
            : "SELECT type,inty FROM droptest WHERE name = $qtable ORDER BY 1,2";
    my $tval = $table =~ /0/ ? 0 : 1;
    $result = [['rule',$tval],['trigger',$tval]];
    bc_deeply($result, $dbhA, $LOCALDROPSQL, $t);

    test_empty_drop($table,$dbhB);
    last;
}

for my $table (sort keys %tabletype) {
    $t=qq{ Second table $table still empty before kick };
    $sql{select}{$table} = "SELECT inty FROM $table ORDER BY $pkey{$table}";
    $table =~ /0/ and $sql{select}{$table} =~ s/inty/$pkey{$table}/;
    $result = [];
    bc_deeply($result, $dbhB, $sql{select}{$table}, $t);
    last;
}

$bct->ctl("kick multicoltest 0");
wait_for_notice($dbhX, 'bucardo_syncdone_multicoltest', 5);

for my $table (sort keys %tabletype) {
    $t=qq{ Second table $table got the row};
    $result = [[1]];
    bc_deeply($result, $dbhB, $sql{select}{$table}, $t);

    test_empty_drop($table,$dbhB);
    last;
}

END {
    $bct->stop_bucardo($dbhX);
    $dbhX->disconnect();
    $dbhA->disconnect();
    $dbhB->disconnect();
    $dbhC->disconnect();
}

