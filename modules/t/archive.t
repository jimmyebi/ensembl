## Bioperl Test Harness Script for Modules
##
# CVS Version
# $Id$


# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.t'

#-----------------------------------------------------------------------
## perl test harness expects the following output syntax only!
## 1..3
## ok 1  [not ok 1 (if test fails)]
## 2..3
## ok 2  [not ok 2 (if test fails)]
## 3..3
## ok 3  [not ok 3 (if test fails)]
##
## etc. etc. etc. (continue on for each tested function in the .t file)
#-----------------------------------------------------------------------


## We start with some black magic to print on failure.
BEGIN { $| = 1; print "1..10\n"; 
	use vars qw($loaded); }

END {print "not ok 1\n" unless $loaded;}

use lib 't';
use EnsTestDB;
use Bio::EnsEMBL::DBArchive::Obj;

$loaded = 1;
print "ok 1\n";    # 1st test passes.
    
my $ens_test = EnsTestDB->new();
    
# Load some data into the db
$ens_test->do_sql_file("../sql/archive.sql");
$ens_test->do_sql_file("t/archive.dump");


$host = $ens_test->host;
$dbname = $ens_test->dbname;
$user = $ens_test->user;

$archive = Bio::EnsEMBL::DBArchive::Obj->new( -host => $host, -dbname => $dbname, -user => $user );


print "ok 2\n";

$seq = Bio::Seq->new( -id => 'silly',-seq => 'ATTCGTTGGGTGGCCCGTGGGTG');
$archive->write_seq($seq->id,1,'exon',$seq->seq,'ENSG000000012',1,'AC0345344',1);

print "ok 3\n";

($seq2) = $archive->get_seq_by_gene_version('ENSG000000012',1,'exon');


if( !defined $seq2 || $seq2->id ne "silly.1" || $seq2->seq ne $seq->seq ) {
  print "not ok 4\n";
  print STDERR "Got ",$seq2->id," with ",$seq2->seq,"\n"
} else {
  print "ok 4\n";
}

$new_id = $archive->get_new_id_from_old_id('gene','ENSG0000018');

if( $new_id ne 'ENSG0000019' ) {
    print "not ok 5\n";
    print STDERR "Got $new_id for new id\n";
} else {
  print "ok 5\n";
}


@newids = $archive->get_new_stable_ids('exon',2);

if( $newids[0] ne 'ENSE00000000001' || $newids[1] ne 'ENSE00000000002' ) {
    print "not ok 6\n";
} else {
    print "ok 6\n";
}

@newids = $archive->get_new_stable_ids('exon',2);

if( $newids[0] ne 'ENSE00000000003' || $newids[1] ne 'ENSE00000000004' ) {
    print "not ok 7\n";
} else {
    print "ok 7\n";
}

@newids = $archive->get_new_stable_ids('gene',2);

if( $newids[0] ne 'ENSG00000000001' || $newids[1] ne 'ENSG00000000002' ) {
    print "not ok 8\n";
} else {
    print "ok 8\n";
}

@newids = $archive->get_new_stable_ids('transcript',2);

if( $newids[0] ne 'ENST00000000001' || $newids[1] ne 'ENST00000000002' ) {
    print "not ok 9\n";
} else {
    print "ok 9\n";
}

@newids = $archive->get_new_stable_ids('translation',2);

if( $newids[0] ne 'ENSP00000000001' || $newids[1] ne 'ENSP00000000002' ) {
    print "not ok 10\n";
} else {
    print "ok 10\n";
}



