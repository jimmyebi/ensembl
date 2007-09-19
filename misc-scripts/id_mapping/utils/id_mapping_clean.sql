#
# some useful stable ID mapping related SQL
# just fragments for copy/paste, not intended to be run as an "SQL script"
#

# get counts from all stable ID related tables
SELECT COUNT(*) FROM gene_stable_id;
SELECT COUNT(*) FROM transcript_stable_id;
SELECT COUNT(*) FROM translation_stable_id;
SELECT COUNT(*) FROM exon_stable_id;
SELECT COUNT(*) FROM mapping_session;
SELECT COUNT(*) FROM stable_id_event;
SELECT COUNT(*) FROM gene_archive;
SELECT COUNT(*) FROM peptide_archive;

# backup all stable ID related tables
CREATE TABLE gene_stable_id_bak SELECT * FROM gene_stable_id;
CREATE TABLE transcript_stable_id_bak SELECT * FROM transcript_stable_id;
CREATE TABLE translation_stable_id_bak SELECT * FROM translation_stable_id;
CREATE TABLE exon_stable_id_bak SELECT * FROM exon_stable_id;
CREATE TABLE mapping_session_bak SELECT * FROM mapping_session;
CREATE TABLE stable_id_event_bak SELECT * FROM stable_id_event;
CREATE TABLE gene_archive_bak SELECT * FROM gene_archive;
CREATE TABLE peptide_archive_bak SELECT * FROM peptide_archive;

# now prune all of them
DELETE FROM gene_stable_id;
DELETE FROM transcript_stable_id;
DELETE FROM translation_stable_id;
DELETE FROM exon_stable_id;
DELETE FROM mapping_session;
DELETE FROM stable_id_event;
DELETE FROM gene_archive;
DELETE FROM peptide_archive;

