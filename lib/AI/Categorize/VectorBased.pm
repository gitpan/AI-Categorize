package AI::Categorize::VectorBased;

use strict;
use AI::Categorize;

use vars qw(@ISA);
@ISA = qw(AI::Categorize);

sub add_document {
  my ($self, $document, $cats, $content) = @_;
  
  # Record the category information
  $cats = [$cats] unless ref $cats;
  $self->{category_map}->add_document($document, $cats);

  $self->{stopwords} ||= $self->stopword_hash;
  my $words = $self->extract_words($content);
  
  while (my ($word,$count) = each %$words) {
    $self->{cache}{$document}{$word} = $count;
    $self->{docword}{$word}++;
  }
}

sub trim_features {
  my ($self, $target) = @_;
  my $dw = $self->{docword};
  my $num_words = keys %$dw;
  print "Trimming features - total words = $num_words\n" if $self->{verbose};
  
  # This is algorithmic overkill, but the sort seems fast enough.
  my @new_docword = (sort {$dw->{$b} <=> $dw->{$a}} keys %$dw)[0 .. $target*$num_words];
  
  %$dw = map {$_,$dw->{$_}} @new_docword;

  while (my ($doc,$wordlist) = each %{$self->{cache}}) {
    my %newlist = map { $dw->{$_} ? ($_, $wordlist->{$_}) : () } keys %$wordlist;
    $self->{cache}{$doc} = {%newlist};
  }

  warn "Finished trimming features - words = " . @new_docword . "\n" if $self->{verbose};
}


sub norm {
  # Takes a hashref and figures out the norm of its *values* (hey, seems to be handy...)
  my ($self, $href) = @_;
  my $norm = 0;
  foreach (values %$href) {$norm += $_**2 }
  return sqrt($norm);
}

sub normalize {
  # Normalizes the values.
  my ($self, $href) = @_;
  my $norm = $self->norm($href);
  while (my ($key) = each %$href) {
    $href->{$key} /= $norm;
  }
}

sub dot_product {
  my ($self, $v1, $v2) = @_;
  my $result = 0;
  foreach (keys %$v1) {
    next unless $v2->{$_};
    $result += $v1->{$_} * $v2->{$_};
  }
  return $result;
}

1;

__END__

=head1 NAME

AI::Categorize::VectorBased - Base class for other algorithms

=head1 SYNOPSIS

  use AI::Categorize::VectorBased;
  @ISA = qw(AI::Categorize::VectorBased);
  ...

=head1 DESCRIPTION

This class implements a few things that vector-based approaches to
document categorization may need.  It's not a complete categorization
class in itself, but it can function as the parent for classes like
C<AI::Categorize::kNN> and C<AI::Categorize::SVM>.

The rest of this document describes some of the implementation details
of this class.  Again, this is not useful in itself for
categorization, but rather describes the shared interface between the
parent and child classes.

=head1 METHODS

=over 4

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

=back

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
