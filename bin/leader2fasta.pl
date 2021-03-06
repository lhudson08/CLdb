#!/usr/bin/env perl

=pod

=head1 NAME

leader2fasta.pl -- write CRISPR leader sequences in fasta format

=head1 SYNOPSIS

leader2fasta.pl [flags] > leaders.fasta

=head2 Required flags

=over

=item -database  <char>

CLdb database.

=back

=head2 Optional flags

=over

=item -gap  <bool>

Remove gaps from the sequences? [FALSE]

=item -subtype  <char>

Refine query to specific a subtype(s) (>1 argument allowed).

=item -taxon_id  <char>

Refine query to specific a taxon_id(s) (>1 argument allowed).

=item -taxon_name  <char>

Refine query to specific a taxon_name(s) (>1 argument allowed).

=item -help  <bool>

This help message

=back

=head2 For more information:

CLdb --perldoc -- leader2fasta.pl

=head1 DESCRIPTION

Get leader sequences from the CRISPR database
and write them in fasta format.

Use arrayFastaAddInfo.pl to add more
metadata (eg., subtype) to each sequence name.

=head2 OUTPUT: sequence names

locus_id|Leader_start|Leader_end

=head1 EXAMPLES

=head2 Write all spacers to a fasta:

CLdb -- leader2fasta -data CLdb.sqlite 

=head2 Write all direct repeats to a fasta:

CLdb -- leader2fasta -data CLdb.sqlite -r

=head2 Refine spacer sequence query:

CLdb --sql -q "where LOCUS_ID=1" -- leader2fasta -da CLdb.sqlite 

=head2 Refine spacer query to a specific subtype & 2 taxon_id's

CLdb -- leader2fasta -da CLdb.sqlite -sub I-B -taxon_id 6666666.4038 6666666.40489

=head1 AUTHOR

Nick Youngblut <nyoungb2@illinois.edu>

=head1 AVAILABILITY

https://github.com/nyoungb2/CLdb

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
use DBI;

# CLdb #
use FindBin;
use lib "$FindBin::RealBin/../lib";
use CLdb::query qw/
	table_exists
	n_entries
	join_query_opts/;
use CLdb::utilities qw/
	file_exists 
	connect2db/;


### args/flags
pod2usage("$0: No files given.") if ((@ARGV == 0) && (-t STDIN));


my ($verbose, $database_file, $gap_rm);
my (@subtype, @taxon_id, @taxon_name);
my $extra_query = "";
GetOptions(
	   "database=s" => \$database_file,
	   "query=s" => \$extra_query,
	   "subtype=s{,}" => \@subtype,
	   "taxon_id=s{,}" => \@taxon_id,
	   "taxon_name=s{,}" => \@taxon_name, 
	   "gaps" => \$gap_rm,
	   "verbose" => \$verbose,
	   "help|?" => \&pod2usage # Help
	   );

#--- I/O error & defaults ---#
file_exists($database_file, "database");

#--- MAIN ---#
# connect 2 db #
my $dbh = connect2db($database_file);

# joining query options (for table join) #
my $join_sql = "";
$join_sql .= join_query_opts(\@subtype, "subtype");
$join_sql .= join_query_opts(\@taxon_id, "taxon_id");
$join_sql .= join_query_opts(\@taxon_name, "taxon_name");


# getting leaderss of interest from database #
my $leaders_r = get_leaders($dbh, $extra_query, $join_sql);

# writing fasta #
write_leaders_fasta($leaders_r);

# disconnect #
$dbh->disconnect();
exit;


### Subroutines
sub write_leaders_fasta{
  # writing arrays as fasta
  my ($leaders_r) = @_;
  
  foreach my $locus_id (keys %$leaders_r){
    print join("\n", 
	       join("|", 
		    ">$locus_id", 
		    'Leader', 'NA', 'NA'
		    ),
	       $leaders_r->{$locus_id}{'Leader_sequence'}
	      ), "\n";
  }
}

sub get_leaders{
  my ($dbh, $extra_query, $join_sql) = @_;
  
  # make query #
  my $query = "SELECT loci.Locus_ID, leaders.Leader_sequence
FROM Loci, Leaders
WHERE loci.locus_id = leaders.locus_id
$join_sql";
  $query = join(" ", $query, $extra_query);

  # status #
  print STDERR "$query\n" if $verbose;

  # query db #
  my $ret = $dbh->selectall_arrayref($query);
  die " ERROR: no matching entries!\n"
    unless $$ret[0];
  
  my %leaders;
  foreach my $row (@$ret){
    $$row[1] =~ s/-//g if $gap_rm; 		# removing gaps
#    $leaders{$$row[0]}{'Leader_start'} = $$row[1];
#    $leaders{$$row[0]}{'Leader_end'} = $$row[2];
    $leaders{$$row[0]}{'Leader_sequence'} = $$row[1];
  }
  
  #print Dumper %leaders; exit;
  return \%leaders;
}

