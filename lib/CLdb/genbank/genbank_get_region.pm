#!/usr/bin/env perl

### modules
use strict;
use warnings;
use Pod::Usage;
use Data::Dumper;
use Getopt::Long;
use File::Spec;
use Bio::SeqIO;
use Set::IntervalTree;
use Regexp::Common;
use Carp  qw( carp confess croak );

# export #
use base 'Exporter';
our @EXPORT_OK = qw/
genbank_get_region/;


#--- main ---#
sub genbank_get_region{
#--- Description ---#
# getting features in select regions of genbank
#--- Input ---#
# @regions = start,end
# $genbank_file = genbank file
# $tRNA = include tRNAs? [false]
# $strand_b = all on + strand? [false]
	my @regions = @_[0..2];		# start, end, scaffold
	my ($genbank_file, $tRNA, $strand_b, $verbose) = @_[3..$#_];
	
	# I/O check #
	my $regions_r;
	if(@regions){ $regions_r = \@regions; }
	else{ confess " ERROR: provide a region (scaffold,start,end)\n"; }
	confess " ERROR: you must provide: scaffold ,start, & end for the region!\n"
		unless scalar @$regions_r == 3;
	
	# loading features #
	my $feats_r = load_genbank_features($genbank_file,$tRNA);
	
	my $itrees_r = load_itrees($feats_r);
	my $ret_r = get_regions_scaffold($itrees_r, $regions_r, $strand_b);

	return $ret_r;
	}


#--- accessory subroutines ---#
sub get_regions_scaffold{
# getting CDS tag info that falls into regions #
	my ($itrees_r, $regions_r, $strand_b) = @_;
	
	my %feat_tags;
	my %tags;
	my $res;
	if( exists $itrees_r->{$$regions_r[0]} ){
		if($$regions_r[1] <= $$regions_r[2]){			# if 'start' is <= 'end'
			$res = $itrees_r->{$$regions_r[0]}->fetch($$regions_r[1], $$regions_r[2]);
			}
		else{			# flippng start and end
			$res = $itrees_r->{$$regions_r[0]}->fetch($$regions_r[2], $$regions_r[1]);
			}
		}
	else{ warn "WARNING: '$$regions_r[0]' not found in genbank or no features for that scaffold in genbank!\n"; }
	
	my $feat_id = 0;
	foreach my $feat (@$res){
		$feat_id++;
		foreach my $tag ($feat->get_all_tags){
			$feat_tags{$feat_id}{$tag} = [$feat->get_tag_values($tag)];
			$tags{$tag} = 1;
			}
		$feat_tags{$feat_id}{"start"} = [($feat->location->start)];
		$feat_tags{$feat_id}{"end"} = [($feat->location->end)];
		$feat_tags{$feat_id}{"contig"} = [($feat->location->seq_id)];
		$feat_tags{$feat_id}{"strand"} = [($feat->location->strand)];
		}

	# flipping start-end if strand = -1 #
	unless($strand_b){
		foreach my $feat (keys %feat_tags){
			if(${$feat_tags{$feat}{"strand"}}[0] == -1){
				(${$feat_tags{$feat}{"start"}}[0],${$feat_tags{$feat}{"end"}}[0]) =
					(${$feat_tags{$feat}{"end"}}[0], ${$feat_tags{$feat}{"start"}}[0]);
				}
			}	
		}
	
	# returning features #
	my @ret;
	my @tags = ("contig", "start", "end");
	push(@tags, sort keys %tags);
	push @ret, ["Feature_num", @tags];
	
	foreach my $feat (keys %feat_tags){
		my @line;
		foreach my $tag (@tags){
			if(exists $feat_tags{$feat}{$tag}){
				push(@line, join("::", @{$feat_tags{$feat}{$tag}}));
				}
			else{
				push(@line, "NA");
				}
			}
		push @ret, [$feat, @line];
		}
		
		#print Dumper @ret; exit;
	return \@ret;
	}
	
sub get_regions{
# getting CDS tag info that falls into regions #
	my ($itree, $regions_r, $strand_b) = @_;
	
	my %feat_tags;
	my %tags;
	for(my $i=0; $i<=$#$regions_r; $i+=2){
		my $res;
		if($$regions_r[$i] <= $$regions_r[$i+1]){			# if 'start' is <= 'end'
			$res = $itree->fetch($$regions_r[$i], $$regions_r[$i+1]);
			}
		else{			# flippng start and end
			$res = $itree->fetch($$regions_r[$i+1], $$regions_r[$i]);
			}
		
		my $feat_id = 0;
		foreach my $feat (@$res){
			$feat_id++;
			foreach my $tag ($feat->get_all_tags){
				$feat_tags{$feat_id}{$tag} = [$feat->get_tag_values($tag)];
				$tags{$tag} = 1;
				}
			$feat_tags{$feat_id}{"start"} = [($feat->location->start)];
			$feat_tags{$feat_id}{"end"} = [($feat->location->end)];
			$feat_tags{$feat_id}{"strand"} = [($feat->location->strand)];
			}
		}
	
	# flipping start-end if strand = -1 #
	unless($strand_b){
		foreach my $feat (keys %feat_tags){
			if(${$feat_tags{$feat}{"strand"}}[0] == -1){
				(${$feat_tags{$feat}{"start"}}[0],${$feat_tags{$feat}{"end"}}[0]) =
					(${$feat_tags{$feat}{"end"}}[0], ${$feat_tags{$feat}{"start"}}[0]);
				}
			}	
		}
	
	# writing out features #
	my @ret;
	my @tags = ("start", "end");
	push(@tags, sort keys %tags);
	push @ret, ["Feature_num", @tags];
	
	foreach my $feat (keys %feat_tags){
		my @line;
		foreach my $tag (@tags){
			if(exists $feat_tags{$feat}{$tag}){
				push(@line, join("::", @{$feat_tags{$feat}{$tag}}));
				}
			else{
				push(@line, "NA");
				}
			}
		push @ret, [$feat, @line];
		}
	return \@ret;
	}

=head2 load_itrees

Loading hash of interval trees with feature start-end info.
{scaffold}=>itree

=cut

sub load_itrees{
  my ($feats_r) = @_;
  
  my %itrees;
  foreach my $feat (@$feats_r){
    my $scaf = $feat->location->seq_id;
    
    # sanity checks
    unless( defined $scaf ){
      print STDERR " WARNING: no scaffold ID found for feature. Skipping feature\n";
      next;
    }	
    if( $feat->location->start !~ /$RE{num}{real}/ or
	$feat->location->start !~ /$RE{num}{real}/ ){
	print STDERR " WARNING: feature start-end not numeric. Skipping feature\n";
	next;
      }	  

    # loading itree
    $itrees{$scaf} = Set::IntervalTree->new() unless exists $itrees{$scaf};	
    $itrees{$scaf} -> insert($feat, $feat->location->start, $feat->location->end);
  }
  
  return \%itrees;
}
	
sub load_itree{
	my ($feats_r) = @_;

	my $itree = Set::IntervalTree->new();
	foreach my $feat (@$feats_r){
		$itree -> insert($feat, $feat->location->start, $feat->location->end);
		}
	
	return $itree;
	}

sub load_genbank_features{
	my ($genbank_file, $tRNA) = @_;
	my $seqio = Bio::SeqIO->new(-file => $genbank_file, -format => "genbank");
	my @feats;
	while ( my $seqo = $seqio->next_seq){
		push(@feats, grep { $_->primary_tag eq 'CDS' } $seqo->get_SeqFeatures);
		push(@feats, grep { $_->primary_tag eq 'tRNA' } $seqo->get_SeqFeatures) if $tRNA;
		}
		
		#print Dumper @feats; exit;
	return \@feats;
	}

sub load_regions{
# loading file w/ regions of interest #
	my ($infile) = @_;
	open IN, $infile or confess $!;
	my @regions;
	while(<IN>){
		chomp;
		s/#.+//;
		next if /^\s*$/;
		
		push(@regions, split /[ ,]+/);
		}
	return \@regions;
	}



__END__

=pod

=head1 NAME

genbank_get_region.pl -- Get all CDS features in >=1 specified genome region

=head1 SYNOPSIS

genbank_get_region.pl [options] [region_file] < file.gbk > region.txt

=head2 arguments

region_file = comma-delimited; each line = (contig), region_start, region_stop

Contig name is optional (needed if multi-locus genbank; ie. multiple '//').

=head2 options

=over

=item -region  <int>

List of region start/stop values (use instead of region_file). 
Example: '-r 1 1000' for region {1-1000}  
Example: '-r contig_1 1 1000' for region {contig_1: 1-1000}

=item -tRNA  <bool>

Include rRNA features? [FALSE]

=item -help  <bool>

This help message

=back

=head2 For more information:

perldoc genbank_get_region.pl

=head1 DESCRIPTION

Get all CDS features in >=1 specified genome region.
Regions can be provided either by '-region' flag or
by a region file.

The tag values of all features falling at least 
partially with a region are written out in a table.
"NA" is written if the tag value is not present in
the feature. Multiple values for the same tag are 
combined with "::"

Contig name is optional (needed if multi-locus genbank).

=head1 EXAMPLES

=head2 CDS features in 1-locus genbank (positions: 1-1000bp):

genbank_get_region.pl -r 1 1000 < file.gbk > regions.txt

=head2 CDS features in multi-locus genbank (positions: 1-1000bp)::

genbank_get_region.pl -r Contig_1 1 1000 < file.gbk > regions.txt

=head2 CDS & tRNA features in 1-locus genbank:

genbank_get_region.pl -r 1 1000 -t < file.gbk > regions.txt

=head1 AUTHOR

Nick Youngblut <nyoungb2@illinois.edu>

=head1 AVAILABILITY

sharchaea.life.uiuc.edu:/home/git/annotation/

=head1 COPYRIGHT

Copyright 2010, 2011
This software is licensed under the terms of the GPLv3

=cut
