#!/usr/bin/env perl

=pod

=head1 NAME

CLdb_arrayBlastGetAlign.pl -- making fasta alignment of crDNA & protospacer

=head1 SYNOPSIS

CLdb_arrayBlastGetAlign.pl [flags] < blast_hits_crDNA_proto_aln.srl > aln.fasta

=head2 Required flags

=over

=back

=head2 Optional flags

=over

=item -database  <char>

CLdb sqlite file name 
(if getting metadata on spacer sequences. eg., taxon_name)

=head3 If -database provided:

=item -subtype  <char>

Refine query to specific a subtype(s) (>1 argument allowed).

=item -taxon_id  <char>

Refine query to specific a taxon_id(s) (>1 argument allowed).

=item -taxon_name  <char>

Refine query to specific a taxon_name(s) (>1 argument allowed).

=item -query  <char>

Extra sql to refine CLdb query (must start with 'AND').

=head3 Output

=item -outfmt  <char>

Output columns added to spacer-protospacer alignments.
See DESCRIPTION for more details.

=head3 Other

=item array  <bool>

Write out hits to spacers in CRISPR arrays (instead of
hits to protospacers)? [FALSE]

=item -verbose  <bool>

Verbose output. [TRUE]

=item -help  <bool>

This help message.

=back

=head2 For more information:

perldoc CLdb_arrayBlastGetAlign.pl

=head1 DESCRIPTION

CLdb_arrayBlastAlignProto.pl must be
run before this script!

Get alignments of crDNA & protospacer.

=head2 -outfmt

This flag designates the format
of each sequence in the output fasta.
The first 4 columns are always:
'crDNA/protospacer', 'locus_id', 'spacer_id', 'hsp_id'.
These are the unique ID for the spacer blast hit. 

Additional columns can be designated with a
comma-seperated list.

Example output (no '-outfmt'): 
">crRNA|1|10|l2puealx43xU"

'crRNA' = crRNA (not protospacer)

'1' = locus_id

'10' = spacer_id (for that locus)

'l2puealx43xU' = blast hsp unique ID


=head3 Support columns:

=over

=item * subtype

=item * taxon_name

=item * taxon_id

=item * scaffold   (of spacer/crDNA)

=item * crDNA_start

=item * crDNA_end

=item * array_sense_strand

=item * blastdb

=item * subject_scaffold

=item * proto_start

=item * proto_end

=item * protoX_start  (X = proto + extension)

=item * protoX_end

=item * proto_strand

=item * identity

=item * evalue

=item * bitscore

=back

=head1 EXAMPLES

=head2 Basic Usage:


=head1 AUTHOR

Nick Youngblut <nyoungb2@illinois.edu>

=head1 AVAILABILITY

sharchaea.life.uiuc.edu:/home/git/CLdb/

=head1 COPYRIGHT

Copyright 2010, 2011
This software is licensed under the terms of the GPLv3

=cut


### modules
use strict;
use warnings;
use Pod::Usage;
use Data::Dumper;
use Getopt::Long;
use File::Spec;
use Sereal qw/ encode_sereal /;

### CLdb
use CLdb::arrayBlast::sereal qw/ decode_file /;
use CLdb::arrayBlast::GetAlign qw/ get_alignProto 
				   parse_outfmt/;
use CLdb::query qw/ table_exists
		    n_entries
		    join_query_opts
		    getLociSpacerInfo/;
use CLdb::utilities qw/ file_exists
			connect2db/;


### args/flags
pod2usage("$0: No files given.") if ((@ARGV == 0) && (-t STDIN));

my ($verbose);
my $database_file;
my $outfmt;
my $array;
my $query = "";
my (@subtype, @taxon_id, @taxon_name);
GetOptions(
	   "database=s" => \$database_file,
	   "array" => \$array,
	   "outfmt=s" => \$outfmt,
           "subtype=s{,}" => \@subtype,
           "taxon_id=s{,}" => \@taxon_id,
           "taxon_name=s{,}" => \@taxon_name,	   
	   "query=s" => \$query,
	   "verbose" => \$verbose,
	   "help|?" => \&pod2usage # Help
	   );

#--- I/O error & defaults ---#
file_exists($database_file, 'database') if defined $database_file;
my $outfmt_r = parse_outfmt($outfmt);

#--- MAIN ---#
# decoding spacer and DR srl
my $spacer_r = decode_file( fh => \*STDIN );


# if database: connect & query
my $queries_r;   # 
if(defined $database_file){
  my $dbh = connect2db($database_file);
  table_exists($dbh, 'loci');
  table_exists($dbh, 'spacers');

  my $join_sql = "";
  $join_sql .= join_query_opts(\@subtype, 'subtype');
  $join_sql .= join_query_opts(\@taxon_id, 'taxon_id');
  $join_sql .= join_query_opts(\@taxon_name, 'taxon_name');
  
  $queries_r = getLociSpacerInfo(dbh => $dbh, 
		    extra_sql => join(" ", $join_sql, $query), 
		    columns => [keys %{$outfmt_r->{CLdb}}]
		   );

  $dbh->disconnect;
}


# querying blastDBs for proteospacers
get_alignProto( blast => $spacer_r,
		outfmt => $outfmt_r,
		queries => $queries_r,
		array => $array,
		verbose => $verbose );

# encoding
#print encode_sereal( $spacer_r );

