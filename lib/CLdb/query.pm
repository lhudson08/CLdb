package CLdb::query;

# module use #
## core ##
use strict;
use warnings FATAL => 'all';
use Carp  qw( carp confess croak );
use Data::Dumper;
use DBI;

## CLdb ##
use CLdb::seq qw/
	revcomp/;


# export #
use base 'Exporter';
our @EXPORT_OK = qw/
table_exists
n_entries
join_query_opts
get_array_seq
get_leader_pos
get_array_seq
list_columns
/;

	
=head1 NAME

CLdb::query

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

Subroutines for querying CLdb

=head1 EXPORT_OK

table_exists
n_entries
join_query_opts
get_array_seq

=cut

sub list_columns{
#-- description --#
# listing all columns in specified table (table must exist) 
# lists column names
#-- input --#
# $dbh = DBI object
# $tbl = sql table of interest
# $silent_ret = no verbose & exit; return column names
	my ($dbh, $tbl, $silent_ret) = @_;
	my $all = $dbh->selectall_arrayref("pragma table_info($tbl)");

	my %tmp;
	foreach (@$all){ 
		$$_[1] =~ tr/A-Z/a-z/;		# lower case for matching
		$tmp{$$_[1]} = 1; 
		}
		
	if(defined $silent_ret){ return \%tmp; }
	else{  print "Columns:\n", join(",\n", keys %tmp), "\n\n";  exit; }
	}




sub orient_byArray{
    # orienting (rev-comp if needed) by array start-end
    # if array_start > array_end, revcomp element
    # else: revcomp
  # columns:
    # locus_ID
    # element_ID
    # eleement_seq
    # element_start
    # element_end
    # array_start
    # array_end
    
    my ($row) = @_;

    if ($$row[5] <= $$row[6]) { # array start > array end
        return [@$row[0..2]];
        
    }
    else {
        $$row[2] = revcomp($$row[2]);
        return [@$row[0..2]];
       
    }

}


sub orient_byleader{
    # orienting (rev-comp if needed) by leader
    # if leader comes prior to element, no rev-comp
    # else: revcomp
  # columns:
    # locus_ID
    # element_ID
    # eleement_seq
    # element_start
    # element_end
    # leader_stat
    # leader_end
    
    my ($row) = @_;

    if ($$row[3] >= $$row[6]) { #array_start >= leader_end position
        return [@$row[0..2]];
        
    }
    else {
        $$row[2] = revcomp($$row[2]);
        return [@$row[0..2]];
       
    }
    
}


sub get_array_seq{
#-- description --#
# Getting spacer or DR cluster repesentative sequence from either table
#-- input --#
# $dbh = DBI database object
# $opts_r = hash of options 
#-- options --#
# spacer_DR_b = spacer or DR [spacer]
# extra_query = extra sql
# cutoff = cluster sequenceID cutoff [1]
# join_sql = "AND" statements 
	
	my ($dbh, $opts_r) = @_;
	
	# checking for opts #
	map{ confess "ERROR: cannot find option: '$_'" 
		unless exists $opts_r->{$_} } qw/spacer_DR_b extra_query join_sql/;
	
	# getting table info #
	my ($tbl_oi, $tbl_prefix) = ("spacers","spacer");	
	($tbl_oi, $tbl_prefix) = ("DRs","DR") if $opts_r->{"spacer_DR_b"};		# DR instead of spacer

# columns:
#	locus_ID
#	spacer|DR
#	spacer/DR_ID
# 	clusterID
# 	sequence

	my $query; 
	if(defined $opts_r->{by_cluster}){ # selecting by cluster
	
	  # by group default options #
	  $opts_r->{"cutoff"} = 1 unless exists $opts_r->{'cutoff'}; 	
	
	  $query = "SELECT 
'NA',
'$tbl_prefix',
'NA',
$tbl_prefix\_clusters.cluster_ID,
$tbl_prefix\_clusters.Rep_sequence
FROM $tbl_prefix\_clusters, loci 
WHERE loci.locus_id = $tbl_prefix\_clusters.locus_id 
AND $tbl_prefix\_clusters.cutoff = $opts_r->{'cutoff'}
$opts_r->{'join_sql'}";
      }
	else{ # selecting all spacers
	$query = "SELECT
$tbl_oi.Locus_ID,
'$tbl_prefix',
$tbl_oi.$tbl_prefix\_ID,
'NA',
$tbl_prefix\_clusters.Rep_sequence
FROM $tbl_oi, $tbl_prefix\_clusters, loci
WHERE loci.locus_id = $tbl_oi.locus_id
AND $tbl_oi.locus_id = $tbl_prefix\_clusters.locus_id
AND $tbl_oi.$tbl_prefix\_ID = $tbl_prefix\_clusters.$tbl_prefix\_ID 
AND $tbl_prefix\_clusters.cutoff = 1
$opts_r->{'join_sql'}";
	}

	$query =~ s/[\n\t]+/ /g;
	$query = join(" ", $query, $opts_r->{"extra_query"});

	# adding group by  & order if clustering
	$query .= " GROUP BY $tbl_prefix\_clusters.cluster_ID ORDER BY $tbl_prefix\_clusters.cluster_ID"
	  if defined $opts_r->{by_cluster}; # selecting by cluster
	  


#print Dumper $tbl_prefix;
#print Dumper $query; exit;
	
	# query db #
	my $ret = $dbh->selectall_arrayref($query);
	confess "ERROR: no matching $tbl_prefix entries!\n"
		unless $$ret[0];

		#print Dumper @$ret; exit;
	return $ret;
	}

sub join_query_opts{
# joining query options for with 'AND' 
	my ($vals_r, $cat) = @_;
	
	return "" unless @$vals_r;	
	
	map{ s/"*(.+)"*/"$1"/ } @$vals_r;
	return join("", " AND loci.$cat IN (", join(", ", @$vals_r), ")");
	}

sub table_exists {
# checking for the existence of a table #
	my ($dbh, $table) = @_;
	confess "ERROR: Provide a DBI database object!\n" if ! defined $dbh;
	confess "ERROR: Provide a CLdb table name!\n" if ! defined $table;
	
	my $res = $dbh->selectall_hashref("SELECT tbl_name FROM sqlite_master", "tbl_name"); 
	
	confess "ERROR: '$table' table not found in CLdb!\n" 
		unless grep(/^$table$/i, keys %$res);
	}

sub n_entries {
# getting number of entries in a table #
	my ($dbh, $table) = @_;
	confess "ERROR: Provide a DBI database object!\n" if ! defined $dbh;
	confess "ERROR: Provide a CLdb table name!\n" if ! defined $table;
	
	my $q = "SELECT count(*) FROM $table";
	my $res = $dbh->selectall_arrayref($q);

	return $$res[0][0];
	}

sub get_leader_pos{
# getting spacer or DR sequence from either table #
#-- input --#
# $dbh = DBI database object
# $opts_r = hash of options 
#-- options --#
# extra_query = extra sql
# join_sql = "AND" statements 
	
	my ($dbh, $opts_r) = @_;
	
	my $query = "SELECT leaders.locus_ID, leaders.leader_start, leaders.leader_end
		FROM leaders, loci WHERE loci.locus_id = leaders.locus_id $opts_r->{'join_sql'}";
	
	$query =~ s/[\n\t]+/ /g;
	$query = join(" ", $query, $opts_r->{"extra_query"});
	
	# query db #
	my $ret = $dbh->selectall_arrayref($query);
	confess " ERROR: no matching entries!\n"
		unless $$ret[0];

	# making hash of sequences #
	my %leaders;
	foreach my $row (@$ret){
		$leaders{$$row[0]}{"start"} = $$row[1];
		$leaders{$$row[0]}{"end"} = $$row[2];
		}

		#print Dumper %leaders; exit;
	return \%leaders;	
	}


=head1 AUTHOR

Nick Youngblut, C<< <nyoungb2 at illinois.edu> >>

=head1 BUGS


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc CLdb::query


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=CRISPR_db>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/CRISPR_db>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/CRISPR_db>

=item * Search CPAN

L<http://search.cpan.org/dist/CRISPR_db/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2013 Nick Youngblut.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.

=cut

1; 