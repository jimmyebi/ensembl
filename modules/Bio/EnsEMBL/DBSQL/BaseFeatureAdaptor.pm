#
# EnsEMBL module for Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor
#
# Copyright (c) 2003 EnsEMBL
#
# You may distribute this module under the same terms as perl itself


=head1 NAME

Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor - An Abstract Base class for all
                                          FeatureAdaptors

=head1 SYNOPSIS

Abstract class - should not be instantiated.  Implementation of
abstract methods must be performed by subclasses.

=head1 DESCRIPTION

This is a base adaptor for feature adaptors. This base class is simply a way
of eliminating code duplication through the implementation of methods
common to all feature adaptors.

=head1 CONTACT

Contact EnsEMBL development list for info: <ensembl-dev@ebi.ac.uk>

=cut

package Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor;
use vars qw(@ISA);
use strict;

use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::EnsEMBL::Utils::Cache;
use Bio::EnsEMBL::Utils::Exception qw(warning throw deprecate);
use Bio::EnsEMBL::Utils::Argument qw(rearrange);

@ISA = qw(Bio::EnsEMBL::DBSQL::BaseAdaptor);

our $SLICE_FEATURE_CACHE_SIZE = 4;


=head2 new

  Arg [1]    : list of args @args
               Superclass constructor arguments
  Example    : none
  Description: Constructor which just initializes internal cache structures
  Returntype : Bio::EnsEMBL::BaseFeatureAdaptor
  Exceptions : none
  Caller     : implementing subclass constructors

=cut

sub new {
  my $caller = shift;

  my $class = ref($caller) || $caller;

  my $self = $class->SUPER::new(@_);

  #initialize an LRU cache
  my %cache;
  tie(%cache, 'Bio::EnsEMBL::Utils::Cache', $SLICE_FEATURE_CACHE_SIZE);
  $self->{'_slice_feature_cache'} = \%cache;

  return $self;
}


=head2 generic_fetch

  Arg [1]    : (optional) string $constraint
               An SQL query constraint (i.e. part of the WHERE clause)
  Arg [2]    : (optional) string $logic_name
               the logic_name of the analysis of the features to obtain
  Example    : $fts = $a->generic_fetch('contig_id in (1234, 1235)', 'Swall');
  Description: Performs a database fetch and returns feature objects in
               contig coordinates.
  Returntype : listref of Bio::EnsEMBL::SeqFeature in contig coordinates
  Exceptions : none
  Caller     : BaseFeatureAdaptor, ProxyDnaAlignFeatureAdaptor::generic_fetch

=cut

sub generic_fetch {
  my ($self, $constraint, $logic_name, $mapper, $slice) = @_;

  my @tabs = $self->_tables;
  my $columns = join(', ', $self->_columns());

  my $db = $self->db();

  if($logic_name) {
    #determine the analysis id via the logic_name
    my $an = $db->get_AnalysisAdaptor()->fetch_by_logic_name($logic_name);

    if(!defined($an) || !$an->dbID()) {
      warning("No analysis for logic name [$logic_name] exists\n");
      return [];
    }

    my $analysis_id = $an->dbID();

    #get the synonym for the primary table
    my $syn = $tabs[0]->[1];

    if($constraint) {
      $constraint .= " AND ${syn}.analysis_id = $analysis_id";
    } else {
      $constraint = " ${syn}.analysis_id = $analysis_id";
    }
  }

  #
  # Construct a left join statement if one was defined, and remove the
  # left-joined table from the table list
  #
  my @left_join_list = $self->_left_join();
  my %left_join_hash = map { $_->[0], $_->[1] } @left_join_list;
  my $left_join = '';
  my @tables;
  if(@left_join_list) {
    while(my $t = shift @tabs) {
      if( exists $left_join_hash{ $t->[0] } ) {
	my $condition = $left_join_hash{ $t->[0] };
        my $syn = $t->[1];
        $left_join .=  "LEFT JOIN ".$t->[0]." $syn ON $condition ";
      } else {
        push @tables, $t;
      }
    }
  } else {
    @tables = @tabs;
  }

  #construct a nice table string like 'table1 t1, table2 t2'
  my $tablenames = join(', ', map({ join(' ', @$_) } @tables));

  my $sql = "SELECT $columns FROM $tablenames $left_join";

  my $default_where = $self->_default_where_clause;
  my $final_clause = $self->_final_clause;

  #append a where clause if it was defined
  if($constraint) {
    $sql .= " where $constraint ";
    if($default_where) {
      $sql .= " and $default_where ";
    }
  } elsif($default_where) {
    $sql .= " where $default_where ";
  }

  #append additional clauses which may have been defined
  $sql .= " $final_clause";

  my $sth = $db->prepare($sql);

  $sth->execute;

  return $self->_objs_from_sth($sth, $mapper, $slice);
}


=head2 fetch_by_dbID

  Arg [1]    : int $id
               The unique database identifier for the feature to be obtained
  Example    : $feat = $adaptor->fetch_by_dbID(1234));
               $feat = $feat->transform('contig');
  Description: Returns the feature created from the database defined by the
               the id $id.  The feature will be returned in its native
               coordinate system.  That is, the coordinate system in which it
               is stored in the database.  In order to convert it to a
               particular coordinate system use the transfer() or transform()
               method.  If the feature is not found in the database then
               undef is returned instead
  Returntype : Bio::EnsEMBL::Feature or undef
  Exceptions : thrown if $id arg is not provided
               does not exist
  Caller     : general

=cut

sub fetch_by_dbID{
  my ($self,$id) = @_;

  throw("id argument is required") if(!defined $id);

  #construct a constraint like 't1.table1_id = 123'
  my @tabs = $self->_tables;
  my ($name, $syn) = @{$tabs[0]};
  my $constraint = "${syn}.${name}_id = $id";

  #Should only be one
  my ($feat) = @{$self->generic_fetch($constraint)};

  return undef if(!$feat);

  return $feat;
}





=head2 fetch_all_by_Slice

  Arg [1]    : Bio::EnsEMBL::Slice $slice
               the slice from which to obtain features
  Arg [2]    : (optional) string $logic_name
               the logic name of the type of features to obtain
  Example    : $fts = $a->fetch_all_by_Slice($slice, 'Swall');
  Description: Returns a listref of features created from the database 
               which are on the Slice defined by $slice. If $logic_name is 
               defined only features with an analysis of type $logic_name 
               will be returned. 
  Returntype : listref of Bio::EnsEMBL::SeqFeatures in Slice coordinates
  Exceptions : none
  Caller     : Bio::EnsEMBL::Slice

=cut

sub fetch_all_by_Slice {
  my ($self, $slice, $logic_name) = @_;

  #fetch by constraint with empty constraint
  return $self->fetch_all_by_Slice_constraint($slice, '', $logic_name);
}


=head2 fetch_all_by_Slice_and_score

  Arg [1]    : Bio::EnsEMBL::Slice $slice
               the slice from which to obtain features
  Arg [2]    : (optional) float $score
               lower bound of the the score of the features retrieved
  Arg [3]    : (optional) string $logic_name
               the logic name of the type of features to obtain
  Example    : $fts = $a->fetch_all_by_Slice($slice, 'Swall');
  Description: Returns a list of features created from the database which are 
               are on the Slice defined by $slice and which have a score 
               greated than $score. If $logic_name is defined, 
               only features with an analysis of type $logic_name will be 
               returned. 
  Returntype : listref of Bio::EnsEMBL::SeqFeatures in Slice coordinates
  Exceptions : none
  Caller     : Bio::EnsEMBL::Slice

=cut

sub fetch_all_by_Slice_and_score {
  my ($self, $slice, $score, $logic_name) = @_;
  my $constraint;

  if(defined $score) {
    #get the synonym of the primary_table
    my @tabs = $self->_tables;
    my $syn = $tabs[0]->[1];
    $constraint = "${syn}.score > $score";
  }

  return $self->fetch_all_by_Slice_constraint($slice, $constraint, 
					      $logic_name);
}


=head2 fetch_all_by_Slice_constraint

  Arg [1]    : Bio::EnsEMBL::Slice $slice
               the slice from which to obtain features
  Arg [2]    : (optional) string $constraint
               An SQL query constraint (i.e. part of the WHERE clause)
  Arg [3]    : (optional) string $logic_name
               the logic name of the type of features to obtain
  Example    : $fs = $a->fetch_all_by_Slice_constraint($slc, 'perc_ident > 5');
  Description: Returns a listref of features created from the database which 
               are on the Slice defined by $slice and fulfill the SQL 
               constraint defined by $constraint. If logic name is defined, 
               only features with an analysis of type $logic_name will be 
               returned. 
  Returntype : listref of Bio::EnsEMBL::SeqFeatures in Slice coordinates
  Exceptions : thrown if $slice is not defined
  Caller     : Bio::EnsEMBL::Slice

=cut

sub fetch_all_by_Slice_constraint {
  my($self, $slice, $constraint, $logic_name) = @_;

  if(!defined($slice) || !ref($slice) || !$slice->isa("Bio::EnsEMBL::Slice")) {
    throw("Slice arg must be a Bio::EnsEMBL::Slice not a [$slice]\n");
  }

  $logic_name ||= '';
  $constraint ||= '';

  #check the cache and return if we have already done this query
  my $key = uc(join(':', $slice->name, $constraint, $logic_name));

  if(exists($self->{'_slice_feature_cache'}->{$key})) {
    return $self->{'_slice_feature_cache'}->{$key};
  }

  my $slice_start  = $slice->start();
  my $slice_end    = $slice->end();
  my $slice_strand = $slice->strand();
  my $slice_cs     = $slice->coord_system();
  my $slice_seq_region = $slice->seq_region_name();

  #get the synonym and name of the primary_table
  my @tabs = $self->_tables;
  my ($tab_name, $tab_syn) = @{$tabs[0]};

  #find out what coordinate systems the features are in
  my $csa = $self->db->get_CoordSystemAdaptor();
  my @feat_css = @{$csa->fetch_all_by_feature_table($tab_name)};

  my $asma = $self->db->get_AssemblyMapperAdaptor();
  my @features;

  # fetch the features from each coordinate system they are stored in
  COORD_SYSTEM: foreach my $feat_cs (@feat_css) {
    my $mapper;
    my @coords;
    my @ids;

    if($feat_cs->equals($slice_cs)) {
      #no mapping is required if this is the same coord system

      # obtain seq_region_id of this slice from db
      my $seq_region_id = 
        $self->db->get_SliceAdaptor->get_seq_region_id($slice);
      $constraint .= " AND " if($constraint);
      $constraint .=
          "${tab_syn}.seq_region_id = $seq_region_id AND " .
          "${tab_syn}.seq_region_start <= $slice_end AND " .
          "${tab_syn}.seq_region_end >= $slice_start";
      my $fs = $self->generic_fetch($constraint,$logic_name,undef,$slice);

      #features may still have to have coordinates made relative to slice start
      $fs = $self->_remap($fs, $mapper, $slice);

      push @features, @$fs;
    } else {
      $mapper = $asma->fetch_by_CoordSystems($slice_cs, $feat_cs);

      # Get a list of coordinates and corresponding internal ids for the
      # regions we are interested in
      @coords = $mapper->map($slice_seq_region, $slice_start, $slice_end,
                                $slice_strand, $slice_cs);

      @coords = grep {!$_->isa('Bio::EnsEMBL::Mapper::Gap')} @coords;

      next COORD_SYSTEM if(!@coords);

      @ids = map {$_->id()} @coords;
      @ids = @{$asma->seq_regions_to_ids($feat_cs, \@ids)};

      #if the regions are large and only partially spanned
      #it is faster to to limit the query with start and end constraints
      #however, it is difficult to tell if a region is large and only partially
      #wanted. The easy approach is just to limit the queries if there are less
      #than a certain number of regions. As well seperate queries are needed
      #otherwise the indices will not be useful
      if(@coords > 3) {
        #do one query, and do not limit with start / end constraints
        my $id_str = join(',', @ids);
        $constraint .= " AND " if($constraint);
        $constraint .= "${tab_syn}.seq_region_id IN ($id_str)";

        my $fs = 
          $self->generic_fetch($constraint, $logic_name, $mapper, $slice);

        $fs = $self->_remap($fs, $mapper, $slice);

        push @features, @$fs;

      } else {
        #do multiple queries using start / end constraints
        my $len = @coords;
        for(my $i = 0; $i < $len; $i++) {
          $constraint .= " AND " if($constraint);
          $constraint .=
            "${tab_syn}.seq_region_id = "     . $ids[$i] . " AND " .
            "${tab_syn}.seq_region_start <= " . $coords[$i]->end() . " AND " .
            "${tab_syn}.seq_region_end >= "   . $coords[$i]->start();
          my $fs = $self->generic_fetch($constraint,$logic_name,
                                        $mapper,$slice);

          $fs = $self->_remap($fs, $mapper, $slice);

          push @features, @$fs;
        }
      }
    }
  }

  $self->{'_slice_feature_cache'}->{$key} = \@features;

  return \@features;
}


#
# Given a list of features checks if they are in the correct coord system
# by looking at the first features slice.  If they are not then they are
# converted and placed on the slice.
#
sub _remap {
  my ($self, $features, $mapper, $slice) = @_;

  #check if any remapping is actually needed
  if(@$features && (!$features->[0]->isa('Bio::EnsEMBL::Feature') ||
                    $features->[0]->slice == $slice)) {
    return $features;
  }

  #remapping has not been done, we have to do our own conversion from
  #to slice coords

  my @out;

  my $slice_start = $slice->start();
  my $slice_end   = $slice->end();
  my $slice_strand = $slice->strand();
  my $slice_cs    = $slice->coord_system();

  my ($seq_region, $start, $end, $strand);

  foreach my $f (@$features) {
    #since feats were obtained in contig coords, attached seq is a contig
    my $fslice = $f->slice();
    my $fseq_region = $fslice->seq_region_name();
    my $fcs = $fslice->coord_system();

    if(!$slice_cs->equals($fcs)) {
      #slice of feature in different coord system, mapping required

      ($seq_region, $start, $end, $strand) =
        $mapper->fastmap($fseq_region,$f->start(),$f->end(),$f->strand(),$fcs);

      # undefined start means gap
      next if(!defined $start);
    } else {
      $start  = $f->start();
      $end    = $f->end();
      $strand = $f->strand();
    }

    # maps to region outside desired area
    next if ($start > $slice_end) || ($end < $slice_start);

    #shift the feature start, end and strand in one call
    if($slice_strand == -1) {
      $f->move( $slice_end - $end + 1, $slice_end - $start + 1, $strand * -1 );
    } else {
      $f->move( $start - $slice_start + 1, $end - $slice_start + 1, $strand );
    }

    $f->slice($slice);

    push @out,$f;
  }

  return \@out;
}


=head2 store

  Arg [1]    : list of Bio::EnsEMBL::SeqFeature
  Example    : $adaptor->store(@feats);
  Description: ABSTRACT  Subclasses are responsible for implementing this 
               method.  It should take a list of features and store them in 
               the database.
  Returntype : none
  Exceptions : thrown method is not implemented by subclass
  Caller     : general

=cut

sub store{
  my $self = @_;

  throw("Abstract method store not defined by implementing subclass\n");
}


=head2 remove

  Arg [1]    : A feature $feature 
  Example    : $feature_adaptor->remove($feature);
  Description: This removes a feature from the database.  The table the
               feature is removed from is defined by the abstract method
               _tablename, and the primary key of the table is assumed
               to be _tablename() . '_id'.  The feature argument must 
               be an object implementing the dbID method, and for the
               feature to be removed from the database a dbID value must
               be returned.
  Returntype : none
  Exceptions : thrown if $feature arg does not implement dbID(), or if
               $feature->dbID is not a true value
  Caller     : general

=cut


sub remove {
  my ($self, $feature) = @_;

  if(!$feature || !ref($feature) || !$feature->isa('Bio::EnsEMBL::Feature')) {
    throw('Feature argument is required');
  }

  if(!$feature->is_stored($self->db)) {
    throw("This feature is not stored in this database");
  }

  my @tabs = $self->_tables;
  my ($table) = @{$tabs[0]};

  my $sth = $self->prepare("DELETE FROM $table WHERE ${table}_id = ?");
  $sth->execute($feature->dbID());

  #unset the feature dbID ad adaptor
  $feature->dbID(undef);
  $feature->adaptor(undef);

  return;
}


=head2 remove_by_Slice

  Arg [1]    : Bio::Ensembl::Slice $slice
  Example    : $feature_adaptor->remove_by_RawContig($slice);
  Description: This removes features from the database which lie on a region
               represented by the passed in slice.  Only features which are
               fully contained by the slice are deleted; features which overlap
               the edge of the slice are not removed.
               The table the features are removed from is defined by
               the abstract method_tablename.
  Returntype : none
  Exceptions : thrown if no slice is supplied
  Caller     : general

=cut

sub remove_by_Slice {
  my ($self, $slice) = @_;

  if(!$slice || !ref($slice) || !$slice->isa('Bio::EnsEMBL::Slice')) {
    throw("Slice argument is required");
  }

  my @tabs = $self->_tables;
  my ($table_name) = @{$tabs[0]};

  my $seq_region_id = $self->db->get_SliceAdaptor->get_seq_region_id($slice);
  my $start = $slice->start();
  my $end   = $slice->end();

  #
  # Delete only features fully on the slice, not overlapping ones
  #
  my $sth = $self->prepare("DELETE FROM $table_name " .
                           "WHERE seq_region_id = ? " .
                           "AND   seq_region_start >= ? " .
                           "AND   seq_region_end <= ?");

  $sth->execute($seq_region_id, $start, $end);
  $sth->finish();
}





=head2 _tables

  Args       : none
  Example    : $tablename = $self->_table_name()
  Description: ABSTRACT PROTECTED Subclasses are responsible for implementing
               this method.  It should list of [tablename, alias] pairs.  
               Additionally the primary table (with the dbID, analysis_id, and
               score) should be the first table in the list.
               e.g:
               ( ['repeat_feature',   'rf'],
                 ['repeat_consensus', 'rc']);
               used to obtain features.  
  Returntype : list of [tablename, alias] pairs
  Exceptions : thrown if not implemented by subclass
  Caller     : BaseFeatureAdaptor::generic_fetch

=cut

sub _tables {
  my $self = shift;

  throw("abstract method _tables not defined by implementing" .
               " subclass of BaseFeatureAdaptor");
  return undef;
}


=head2 _columns

  Args       : none
  Example    : $tablename = $self->_columns()
  Description: ABSTRACT PROTECTED Subclasses are responsible for implementing
               this method.  It should return a list of columns to be used
               for feature creation
  Returntype : list of strings
  Exceptions : thrown if not implemented by subclass
  Caller     : BaseFeatureAdaptor::generic_fetch

=cut

sub _columns {
  my $self = shift;

  throw("abstract method _columns not defined by implementing" .
               " subclass of BaseFeatureAdaptor");
}



=head2 _default_where_clause

  Arg [1]    : none
  Example    : none
  Description: May be overridden to provide an additional where constraint to 
               the SQL query which is generated to fetch feature records.
               This constraint is always appended to the end of the generated
               where clause
  Returntype : string
  Exceptions : none
  Caller     : generic_fetch

=cut

sub _default_where_clause {
  my $self = shift;

  return '';
}



=head2 _left_join

  Arg [1]    : none
  Example    : none
  Description: Can be overridden by a subclass to specify any left joins
               which should occur. The table name specigfied in the join
               must still be present in the return values of 
  Returntype : a {'tablename' => 'join condition'} pair 
  Exceptions : none
  Caller     : general

=cut

sub _left_join {
  my $self = shift;

  return ([]);
}



=head2 _final_clause

  Arg [1]    : none
  Example    : none
  Description: May be overriden to provide an additional clause to the end
               of the SQL query used to fetch feature records.  
               This is useful to add a required ORDER BY clause to the 
               query for example.
  Returntype : string
  Exceptions : none
  Caller     : generic_fetch

=cut

sub _final_clause {
  my $self = shift;

  return '';
}

=head2 _objs_from_sth

  Arg [1]    : DBI::row_hashref $hashref containing key-value pairs 
               for each of the columns specified by the _columns method
  Example    : my @feats = $self->_obj_from_hashref
  Description: ABSTRACT PROTECTED The subclass is responsible for implementing
               this method.  It should take in a DBI row hash reference and
               return a list of created features in contig coordinates.
  Returntype : list of Bio::EnsEMBL::*Features in contig coordinates
  Exceptions : thrown if not implemented by subclass
  Caller     : BaseFeatureAdaptor::generic_fetch

=cut

sub _objs_from_sth {
  my $self = shift;

  throw("abstract method _obj_from_sth not defined by implementing"
             . " subclass of BaseFeatureAdaptor");
}

=head2 deleteObj

  Arg [1]    : none
  Example    : none
  Description: Cleans up internal caches and references to other objects so
               that correct garbage collection may occur.
  Returntype : none
  Exceptions : none
  Caller     : Bio::EnsEMBL::DBConnection::deleteObj

=cut

sub deleteObj {
  my $self = shift;

  #flush feature cache
  %{$self->{'_slice_feature_cache'}} = ();
}





=head2 fetch_all_by_RawContig_constraint

  Description: DEPRECATED use fetch_all_by_RawContig_constraint instead

=cut

sub fetch_all_by_RawContig_constraint {
  my $self = shift;
  deprecate('Use fetch_all_by_Slice_constraint() instead.');
  return $self->fetch_all_by_slice_constraint(@_);
}

=head2 fetch_all_by_RawContig

  Description: DEPRECATED use fetch_all_by_Slice instead

=cut

sub fetch_all_by_RawContig {
  my $self = shift;
  deprecate('Use fetch_all_by_Slice() instead.');
  return $self->fetch_all_by_Slice(@_);
}

=head2 fetch_all_by_RawContig_and_score

  Description: DEPRECATED use fetch_all_by_Slice_and_score instead

=cut

sub fetch_all_by_RawContig_and_score{
  my $self = shift;
  deprecate('Use fetch_all_by_Slice_and_score() instead.');
  return $self->fetch_all_by_Slice_and_score(@_);
}

=head2 remove_by_RawContig

  Description: DEPRECATED use remove_by_Slice instead

=cut

sub remove_by_RawContig {
  my $self = shift;
  deprecate("Use remove_by_Slice instead");
  return $self->remove_by_Slice(@_);
}


1;


