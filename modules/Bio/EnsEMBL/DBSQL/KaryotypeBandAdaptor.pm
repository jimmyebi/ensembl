#
# Ensembl module for Bio::EnsEMBL::DBSQL::KaryotypeBandAdaptor
#
#
# Copyright James Stalker
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::EnsEMBL::DBSQL::KaryotypeBandAdaptor

=head1 SYNOPSIS

$kary_adaptor = $db_adaptor->get_KaryotypeBandAdaptor();
foreach $band ( @{$kary_adaptor->fetch_all_by_Slice($slice)} ) {
  #do something with band
}

$band = $kary_adaptor->fetch_by_dbID($id);

my @bands = @{$kary_adaptor->fetch_all_by_chr_name('X')};

my $band = $kary_adaptor->fetch_by_chr_band('4','q23');


=head1 DESCRIPTION

Database adaptor to provide access to KaryotypeBand objects

=head1 AUTHOR

James Stalker

This modules is part of the Ensembl project http://www.ensembl.org

=head1 CONTACT

Email jws@sanger.ac.uk

=head1 APPENDIX

The rest of the documentation details each of the object methods. Internal 
methods are usually preceded with a _

=cut


package Bio::EnsEMBL::DBSQL::KaryotypeBandAdaptor;

use strict;

use vars qw(@ISA);

use Bio::EnsEMBL::KaryotypeBand;
use Bio::EnsEMBL::Utils::Exception qw(throw);
use Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor;

@ISA = qw(Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor);

#_tables
#
#  Arg [1]    : none
#  Example    : none
#  Description: PROTECTED Implementation of abstract superclass method to
#               provide the name of the tables to query
#  Returntype : string
#  Exceptions : none
#  Caller     : internal


sub _tables {
  my $self = shift;

  return (['karyotype','k'])
}


#_columns

#  Arg [1]    : none
#  Example    : none
#  Description: PROTECTED Implementation of abstract superclass method to 
#               provide the name of the columns to query 
#  Returntype : list of strings
#  Exceptions : none
#  Caller     : internal

sub _columns {
  my $self = shift;

  #warning _objs_from_sth implementation depends on ordering
  return qw (
       k.karyotype_id
       k.seq_region_id
       k.seq_region_start
       k.seq_region_end
       k.band
       k.stain );
}


sub _objs_from_sth {
  my ($self, $sth) = @_;
  my $db = $self->db();
  my $slice_adaptor = $db->get_SliceAdaptor();

  my @features;
  my %slice_cache;

  my($karyotype_id,$seq_region_id,$seq_region_start,$seq_region_end,
     $band,$stain);

  $sth->bind_columns(\$karyotype_id, \$seq_region_id, \$seq_region_start,
                     \$seq_region_end, \$band, \$stain);

  while($sth->fetch()) {
    my $slice = $slice_cache{$seq_region_id} ||=
      $slice_adaptor->fetch_by_seq_region_id($seq_region_id);

    push @features, Bio::EnsEMBL::KaryotypeBand->new
      (-START   => $seq_region_start,
       -END     => $seq_region_end,
       -SLICE   => $slice,
       -ADAPTOR => $self,
       -DBID    => $karyotype_id,
       -BAND    => $band,
       -STAIN   => $stain);
  }

  return \@features;
}



=head2 fetch_all_by_chr_name

  Arg [1]    : string $chr_name
               Name of the chromosome from which to retrieve band objects 
  Example    : @bands=@{$karyotype_band_adaptor->fetch_all_by_chr_name('X')}; 
  Description: Fetches all the karyotype band objects from the database for the
               given chromosome. 
  Returntype : listref of Bio::EnsEMBL::KaryotypeBand in chromosomal 
               (assembly) coordinates 
  Exceptions : none 
  Caller     : general 

=cut

sub fetch_all_by_chr_name {
    my ($self,$chr_name) = @_;

    throw('Chromosome name argument expected') if(!$chr_name);

    my $slice =
      $self->db->get_SliceAdaptor->fetch_by_region('chromosome', $chr_name);
    return $self->fetch_by_Slice($slice);
}


=head2 fetch_by_chr_band

  Arg  [1]   : string $chr_name
               Name of the chromosome from which to retrieve the band
  Arg  [2]   : string $band
               The name of the band to retrieve from the specified chromosome
  Example    : $band = $kary_adaptor->fetch_all_by_chr_band('4', 'q23');
  Description: Fetches the karyotype band object from the database
               for the given chromosome and band name.  If no such band
               exists, undef is returned instead.
  Returntype : Bio::EnsEMBL::KaryotypeBand in chromosomal coordinates.
  Exceptions : none
  Caller     : general

=cut

sub fetch_by_chr_band {
  my ($self, $chr_name, $band) = @_;

  throw('Chromosome name argument expected') if(!$chr_name);
  throw('Band argument expected') if(!$band);

  my $slice = $self->db->get_SliceAdaptor->fetch_by_region('chromosome',
                                                           $chr_name);

  my $constraint = "k.band = '$band'";
  my $result = $self->fetch_by_Slice_constraint($slice,$constraint);

  return undef if(!@$result);
  my ($kb) = @$result;

  return $kb;
}

1;
