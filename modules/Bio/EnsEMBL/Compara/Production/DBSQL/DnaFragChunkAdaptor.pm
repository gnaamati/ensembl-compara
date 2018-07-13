=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2019] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

  Questions may also be sent to the Ensembl help desk at
  <http://www.ensembl.org/Help/Contact>.

=head1 NAME

Bio::EnsEMBL::Compara::Production::DBSQL::DnaFragChunkAdaptor

=cut

package Bio::EnsEMBL::Compara::Production::DBSQL::DnaFragChunkAdaptor;

use strict;
use warnings;

use Bio::EnsEMBL::Compara::Production::DnaFragChunk;

use Bio::EnsEMBL::Compara::DBSQL::DnaFragAdaptor;
use Bio::EnsEMBL::Compara::DBSQL::SequenceAdaptor;

use Bio::EnsEMBL::Utils::Scalar qw(:assert);

use DBI qw(:sql_types);

use base qw(Bio::EnsEMBL::Compara::DBSQL::BaseAdaptor);


#############################
#
# store methods
#
#############################

=head2 store

  Arg[1]     : one or many DnaFragChunk objects
  Example    : $adaptor->store($chunk);
  Description: stores DnaFragChunk objects into compara database
  Returntype : none
  Exceptions : none
  Caller     : general

=cut

sub store {
  my ($self, $dfc)  = @_;

  assert_ref($dfc, 'Bio::EnsEMBL::Compara::Production::DnaFragChunk', 'dfc');

  $dfc->sequence_id($self->db->get_SequenceAdaptor->store($dfc->sequence)) if $dfc->sequence;

  my $dbID;

  if (my $other_dfc = $self->_synchronise($dfc)) {
      $dbID = $other_dfc->dbID;

  } else {
      $dbID = $self->generic_insert('dnafrag_chunk', {
              'dnafrag_id'            => $dfc->dnafrag_id,
              'sequence_id'           => $dfc->sequence_id // 0,
              'dnafrag_start'         => $dfc->dnafrag_start,
              'dnafrag_end'           => $dfc->dnafrag_end,
              'dnafrag_chunk_set_id'  => $dfc->dnafrag_chunk_set_id,
          }, 'dnafrag_chunk_id');
  }
  $self->attach($dfc, $dbID);

  return $dfc;
}


sub update_sequence
{
  my $self = shift;
  my $dfc  = shift;

  return 0 unless($dfc);
  return 0 unless($dfc->isa('Bio::EnsEMBL::Compara::Production::DnaFragChunk'));
  return 0 unless($dfc->dbID);
  return 0 unless(defined($dfc->sequence));
  return 0 unless(length($dfc->sequence) <= ($self->_max_allowed_packed-500000));  #limited by myslwd max_allowed_packet=12M

  my $seqDBA = $self->db->get_SequenceAdaptor;
  my $newSeqID = $seqDBA->store($dfc->sequence);

  return if($dfc->sequence_id == $newSeqID); #sequence unchanged

  my $sth = $self->prepare("UPDATE dnafrag_chunk SET sequence_id=? where dnafrag_chunk_id=?");
  $sth->execute($newSeqID, $dfc->dbID);
  $sth->finish();
  $dfc->sequence_id($newSeqID);
  return $newSeqID;
}

# Should be in DBConnection, but not sure Core would like it
sub _max_allowed_packed {
    my $self = shift;
    unless ($self->{_max_allowed_packed}) {
        my (undef, $max_allowed_packet) =  $self->dbc->db_handle->selectrow_array( 'SHOW VARIABLES LIKE "max_allowed_packet"' );
        $self->{_max_allowed_packed} = $max_allowed_packet;
    }
    return $self->{_max_allowed_packed};
}

###############################################################################
#
# fetch methods
#
###############################################################################


=head2 fetch_all_by_DnaFragChunkSet

  Arg [1...] : Bio::EnsEMBL::Compara::Production::DnaFragChunkSet 
  Example    : $dfc = $adaptor->fetch_all_by_(1234);
  Description: Returns an array of DnaFragChunks created from the database from a DnaFragChunkSet
  Returntype : listref of Bio::EnsEMBL::Compara::Production::DnaFragChunk objects
  Exceptions : thrown if $dnafrag_chunk_set is not defined
  Caller     : general

=cut

sub fetch_all_by_DnaFragChunkSet {
  my $self = shift;
  my $dnafrag_chunk_set = shift;

  assert_ref($dnafrag_chunk_set, 'Bio::EnsEMBL::Compara::Production::DnaFragChunkSet');

  my $dnafrag_chunk_set_id = $dnafrag_chunk_set->dbID;
  $self->bind_param_generic_fetch($dnafrag_chunk_set_id, SQL_INTEGER);
  my $constraint = 'dfc.dnafrag_chunk_set_id = ?';

  #printf("fetch_all_by_DnaFragChunkSet has contraint\n$constraint\n");

  return $self->generic_fetch($constraint);
}


############################
#
# INTERNAL METHODS
#
############################

#internal method used in multiple calls above to build objects from table data

sub object_class {
    return 'Bio::EnsEMBL::Compara::Production::DnaFragChunk';
}


sub _tables {
  my $self = shift;

  return (['dnafrag_chunk', 'dfc'] );
}

sub _columns {
  my $self = shift;

  return qw (dfc.dnafrag_chunk_id
             dfc.dnafrag_chunk_set_id
             dfc.dnafrag_id
             dfc.dnafrag_start
             dfc.dnafrag_end
             dfc.sequence_id
            );
}

sub _unique_attributes {
    my $self = shift;

    return qw(
        dnafrag_chunk_set_id
        dnafrag_id
        dnafrag_start
        dnafrag_end
    );
}

sub _objs_from_sth {
  my ($self, $sth) = @_;

  return $self->generic_objs_from_sth($sth, 'Bio::EnsEMBL::Compara::Production::DnaFragChunk', [
          'dbID',
          'dnafrag_chunk_set_id',
          'dnafrag_id',
          'dnafrag_start',
          'dnafrag_end',
          'sequence_id',
      ] );
}

1;
