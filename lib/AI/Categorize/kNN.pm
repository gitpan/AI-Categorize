package AI::Categorize::kNN;

use strict;
use AI::Categorize::VectorBased;

use vars qw(@ISA);
@ISA = qw(AI::Categorize::VectorBased);

sub new {
  my $package = shift;
  return $package->SUPER::new('k' => 20,
			      'ratio_held_out' => 0.2,
			      'features_kept' => 0.2,
			      @_);
}

sub crunch {
  my ($self) = @_;

  $self->trim_features($self->{features_kept}) if $self->{features_kept};

  # Normalize all document vectors
  foreach my $document (keys %{$self->{cache}}) {
    $self->normalize($self->{cache}{$document});
  }
  $self->learn_thresholds;
}

sub learn_thresholds {
  # Choose several random documents to hold out for each category
  # (determined by $self->{ratio_held_out}) and optimize the category's
  # threshold to maximize accuracy on the held out data.

  my ($self) = @_;

  # This implementation seems terrible so far.

  my @all_cats = $self->{category_map}->categories;
  my @all_docs = $self->{category_map}->documents;

  foreach my $cat (@all_cats) {
    print " ---Setting threshold: $cat => " if $self->{verbose};
    my @docs;
    my %docs = map {$_,1} (@docs = $self->{category_map}->documents_of($cat));
    my $num_held = int($self->{ratio_held_out} * @docs);
    if ($num_held < 2) {
      print "0.5 (default - insufficient data)\n" if $self->{verbose};
      $self->{thresholds}{$cat} = 0.5;
      next;
    }

    my %held;
    for (1..$num_held) {
      $held{$docs[rand @docs]} = 1;
    }

    my %others;
    while (keys(%others) < $num_held) {
      my $i = rand @all_docs;
      next if $docs{$all_docs[$i]};
      $others{$all_docs[$i]} = 1;
    }
    
    # Now we have equal numbers of docs in $cat (%held) and docs not
    # in $cat (%others).  Run each of them through the categorizer and
    # get the score for $cat, and store the results in %held and %others.

    foreach my $h (\%held, \%others) {
      foreach my $doc (keys %$h) {
	my $scores = $self->get_scores(vector => $self->{cache}{$doc}, avoid_docs => \%held);
	$h->{$doc} = $scores->{$cat};
      }
    }

    # Choose a threshold that maximizes F1
    $self->{thresholds}{$cat} = $self->maximize_F1(\%held, \%others);
    if ($self->{thresholds}{$cat}) {
      print "$self->{thresholds}{$cat}\n" if $self->{verbose};
    } else {
      # Guard against threshold of zero
      print "0.5 (default - found zero threshold)\n" if $self->{verbose};
      $self->{thresholds}{$cat} = 0.5;
    }
  }
}

sub maximize_F1 {
  my ($self, $correct, $incorrect) = @_;
  
  my @all = sort {$a<=>$b} 0,values(%$correct),values(%$incorrect);
  my @candidates;
  foreach (0..$#all-1) {
    my $x = ($all[$_] + $all[$_+1])/2;
    push @candidates, $x if $x;  # Don't use zero
  }

  my ($best_thresh, $best_F1) = (0,0);
  foreach my $candidate (@candidates) {
    my @outcome = ((grep {$correct->{$_}   > $candidate} keys %$correct),
		   (grep {$incorrect->{$_} > $candidate} keys %$incorrect));
    my $F1 = $self->F1(\@outcome, [keys %$correct]);
    ($best_thresh,$best_F1) = ($candidate,$F1) if $F1 > $best_F1;
  }
  return $best_thresh;
}

sub get_scores {
  my ($self, %args) = @_;
  $args{avoid_docs} ||= {};
  
  my %doc_scores;
  my $i;
  local $|=1;
  while (my ($doc, $words) = each %{$self->{cache}}) {
    next if exists $args{avoid_docs}{$doc};
    $doc_scores{$doc} = $self->dot_product($words, $args{vector});
    #print "." unless $i++ % 5;
    #warn "$doc: $doc_scores{$doc}\n";
  }
  
  my $limit = $self->{k} > keys %doc_scores ? keys %doc_scores : $self->{k}-1;
  my @top_k_docs = (sort {$doc_scores{$b} <=> $doc_scores{$a}} keys %doc_scores)[0..$limit-1];
  
  my %scores;
  foreach my $doc (@top_k_docs) {
    my @cats = $self->{category_map}->categories_of($doc);
    foreach my $cat (@cats) {
      $scores{$cat} += $doc_scores{$doc};
    }
  }

  return \%scores;
}

sub categorize {
  my $self = shift;
  my $newdoc = $self->extract_words($_[0]);
  $self->normalize($newdoc);
  
  my $scores = $self->get_scores(vector => $newdoc);
  
  # Adjust all scores so that the common threshold is 1
  foreach my $cat (keys %$scores) {
    #warn "$cat: $scores->{$cat}\n";
    $scores->{$cat} /= $self->{thresholds}{$cat};
  }


  return $self->{results_class}->new(scores => $scores,
                                     threshold => 1);
}

1;

__END__

=head1 NAME

AI::Categorize::kNN - k-Nearest-Neighbor Algorithm For AI::Categorize

=head1 SYNOPSIS

  use AI::Categorize::kNN;
  my $c = AI::Categorize::kNN->new;
  my $c = AI::Categorize::kNN->new(load_data => 'filename');
  
  # See AI::Categorize for more details

=head1 DESCRIPTION

This is an implementation of the k-nearest-neighbor decision-making
algorithm, applied to the task of document categorization (as defined
by the AI::Categorize module).  The basic concept behind the algorithm
is to find the C<k> documents from the training corpus that are most
similar to the given document (C<k> is often a number like 20 or so),
then use the categories of those similar documents to determine a
reasonable set of categories for the given document.

"Similarity" of two documents is defined to be the cosine of the angle
between the documents' word-frequency vectors.  Each word-frequency
vector is a many-dimensional vector whose components represent all the
words present in the document, and whose component values represent
the number of times each word appears in the document.

After we find the C<k> training documents most similar to the given
document (we'll call them the "similar documents"), we look up the
categories of the similar documents.  The appropriateness score for
each category is then the sum of the scores of the similar documents
belonging to that category.  If any of the similar documents belongs
to multiple categories, it counts for all.

Once this procedure has been followed to determine the given
document's appropriateness score for each category, we check each
score against a per-category threshold (learned from the training data
- see L<"ratio_held_out"> below).  If the score is higher than the
threshold, the given document is assigned to that category.  If not,
the document is not assigned to that category.

At this stage, an appropriateness score for one category is not
comparable to an appropriateness score for another category.  To
correct this, before returning its output the C<categorize()> methods
will normalize all scores so that a score higher than 1 indicates
category membership, and a score lower than 1 indicates category
nonmembership.  The details of this fact may change in future releases
of this code.

=head1 METHODS

The C<AI::Categorize::kNN> class inherits from the C<AI::Categorize>
class, so all of its methods are available unless explicitly mentioned
here.

=head2 new()

The C<new()> method accepts several parameters that help determine the
behavior of the categorizer.

=over 4

=item * k

This is the C<k> in k-Nearest-Neigbor.  It is the number of similar
documents to consider during the C<categorize()> method.  The default
value is 20.  Experiment to find out a value that suits your needs.

=item * ratio_held_out

This is the portion of the training corpus that will be used to
determine the per-category membership threshold.  The default value is
0.2, which means that for each category 80% of the training documents
will be parsed, then the remaining 20% will be used to determine the
threshold.  The threshold will be set to a value that maximizes F1 on
the held out data (see L<AI::Categorize/F1>).

We require that there be at least 2 documents in the held out set for
each category.  If there aren't enough, some dumb default value will
be used instead.

=item * features_kept

This parameter determines what portion of the features (words) from
the training documents will be kept and what features will be
discarded.  The parameter is a number between 0 and 1.  The default is
0.2, indicating that 20% of the features will be kept.  To determine
which features should be kept, we use the document-frequency
criterion, in which we keep the features that appear in the greatest
number of training documents.  This algorithm is simple to implement
and reasonably effective.

To keep all features, pass a C<features_kept> parameter of 0.

=back

=head1 TO DO

Something seems screwy with the threshold-setting procedure.  It
allows more categories to be assigned than it should, as evidenced by
the fact that usually the top 1 or 2 scoring categories are correct,
but additional false categories are thrown in too.  I think this is
probably because the thresholds are set using a document set that
doesn't reflect the category distribution of the training/testing
copora.

=head1 AUTHOR

Ken Williams, ken@forum.swarthmore.edu

=head1 COPYRIGHT

Copyright 2000-2001 Ken Williams.  All rights reserved.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

AI::Categorize(3)

"A re-examination of text categorization methods" by Yiming Yang
L<http://www.cs.cmu.edu/~yiming/publications.html>

=cut
