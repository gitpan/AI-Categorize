package AI::Categorize::NaiveBayes;

use strict;
use AI::Categorize;

use vars qw(@ISA);
@ISA = qw(AI::Categorize);

sub new {
  my $package = shift;
  return $package->SUPER::new(@_);
}

sub add_document {
  my ($self, $document, $cats, $content) = @_;
  # In the future, $content may be allowed to be a filehandle

  # Record the category information
  $cats = [$cats] unless ref $cats;
  $self->{category_map}->add_document($document, $cats);
  
  my $words = $self->extract_words($content);
  
  foreach my $cat (@$cats) {
    while (my ($word, $count) = each %$words) {
      $self->{cache}{$cat}{$word} += $count;
    }
  }
}

sub crunch {
  my ($self) = @_;
  
  $self->{logtotal} = 0;
  foreach my $cat (keys %{$self->{cache}}) {
    my $total = $self->total($self->{cache}{$cat});
    $self->{categories}{$cat}{logcount} = log($total);
    $self->{logtotal} += $total;
    foreach my $word (keys %{$self->{cache}{$cat}}) {
      $self->{cache}{$cat}{$word} = log($self->{cache}{$cat}{$word}/$total);
    }
  }
  $self->{logtotal} = log($self->{logtotal});
}

sub total {
  # Takes a hashref and figures out the total of its *values* (hey, seems to be handy...)
  my ($self, $href) = @_;
  my $total = 0;
  foreach (values %$href) {$total += $_}
  return $total;
}

sub categorize {
  my $self = shift;
  my $newdoc = $self->extract_words(shift);
  
  # Note that we're using the log(prob) here.  That's why we add instead of multiply.

  my $i;
  local $|=1;
  my %scores;
  while (my ($cat,$words) = each %{$self->{cache}}) {
    my $fake_prob = log(0.5) - $self->{categories}{$cat}{logcount}; # Like a very infrequent word
    $scores{$cat} = $self->{categories}{$cat}{logcount} - $self->{logtotal};
    
    while (my ($word, $count) = each %$newdoc) {
      $scores{$cat} += ($words->{$word} || $fake_prob)*$count;
    }
    #print "$cat: $scores{$cat}\n";
    #print "." unless $i++ % 5;
  }

  my $num_words = keys %$newdoc;
  my $avg_prob  = -6.82884235791492; # For now
  my $threshold = $num_words * $avg_prob;
  #print "num_words: $num_words\nthreshold: $threshold\n";
  
  return $self->{results_class}->new(scores => \%scores,
				     threshold => $threshold);
}

1;

__END__

=head1 NAME

AI::Categorize::NaiveBayes - Naive Bayes Algorithm For AI::Categorize

=head1 SYNOPSIS

  use AI::Categorize::NaiveBayes;
  my $c = AI::Categorize::NaiveBayes->new;
  my $c = AI::Categorize::NaiveBayes->new(load_data => 'filename');
  
  # See AI::Categorize for more details

=head1 DESCRIPTION

This is an implementation of the Naive Bayes decision-making
algorithm, applied to the task of document categorization (as defined
by the AI::Categorize module).  See L<AI::Categorize> for a
description of the interface.

=head1 THEORY

Bayes' Theorem is a way of inverting a conditional probability. It
states:

                P(y|x) P(x)
      P(x|y) = -------------
                   P(y)

The notation C<P(x|y)> means "the probability of C<x> given C<y>."  See also
L<"http://forum.swarthmore.edu/dr.math/problems/battisfore.03.22.99.html">
for a simple but complete example of Bayes' Theorem.

In this case, we want to know the probability of a given category given a
certain string of words in a document, so we have:

                    P(words | cat) P(cat)
  P(cat | words) = --------------------
                           P(words)

We have applied Bayes' Theorem because C<P(cat | words)> is a difficult
quantity to compute directly, but C<P(words | cat)> and C<P(cat)> are accessible
(see below).

The greater the expression above, the greater the probability that the given
document belongs to the given category.  So we want to find the maximum
value.  We write this as

                                 P(words | cat) P(cat)
  Best category =   ArgMax      -----------------------
                   cat in cats          P(words)


Since C<P(words)> doesn't change over the range of categories, we can get rid
of it.  That's good, because we didn't want to have to compute these values
anyway.  So our new formula is:

  Best category =   ArgMax      P(words | cat) P(cat)
                   cat in cats

Finally, we note that if C<w1, w2, ... wn> are the words in the document,
then this expression is equivalent to:

  Best category =   ArgMax      P(w1|cat)*P(w2|cat)*...*P(wn|cat)*P(cat)
                   cat in cats

That's the formula I use in my document categorization code.  The last
step is the only non-rigorous one in the derivation, and this is the
"naive" part of the Naive Bayes technique.  It assumes that the
probability of each word appearing in a document is unaffected by the
presence or absence of each other word in the document.  We assume
this even though we know this isn't true: for example, the word
"iodized" is far more likely to appear in a document that contains the
word "salt" than it is to appear in a document that contains the word
"subroutine".  Luckily, as it turns out, making this assumption even
when it isn't true may have little effect on our results, as the
following paper by Pedro Domingos argues:
L<"http://www.cs.washington.edu/homes/pedrod/mlj97.ps.gz">

=head1 CALCULATIONS

The various probabilities used in the above calculations are found
directly from the training documents.  For instance, if there are 5000
total tokens (words) in the "sports" training documents and 200 of
them are the word "curling", then C<P(curling|sports) = 200/5000 =
0.04> .  If there are 10,000 total tokens in the training corpus and
5,000 of them are in documents belonging to the category "sports",
then C<P(sports)> = 5,000/10,000 = 0.5> .

Because the probabilities involved are often very small and we
multiply many of them together, the result is often a tiny tiny
number.  This could pose problems of floating-point underflow, so
instead of working with the actual probabilities we work with the
logarithms of the probabilities.  This also speeds up various
calculations in the C<categorize()> method.

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

"On the Optimality of the Simple Bayesian Classifier under Zero-One
Loss" by Pedro Domingos
L<"http://www.cs.washington.edu/homes/pedrod/mlj97.ps.gz">

A simple but complete example of Bayes' Theorem from Dr. Math
L<"http://www.mathforum.com/dr.math/problems/battisfore.03.22.99.html">

=cut
