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
  # This uses a simple document-frequency criterion.  Other criteria may follow later.
  my ($self, $target) = @_;
  my $dw = $self->{docword};
  my $num_words = keys %$dw;
  print "Trimming features - total words = $num_words\n" if $self->{verbose};
  
  # This is algorithmic overkill, but the sort seems fast enough.
  my @new_docword = (sort {$dw->{$b} <=> $dw->{$a}} keys %$dw)[0 .. $target*$num_words];
  
  $self->{wordlist} = [sort @new_docword];
  %$dw = map {$_,$dw->{$_}} @new_docword;

  while (my ($doc,$wordlist) = each %{$self->{cache}}) {
    my %newlist = map { $dw->{$_} ? ($_, $wordlist->{$_}) : () } keys %$wordlist;
    $self->{cache}{$doc} = {%newlist};
  }

  print "Finished trimming features - words = " . @new_docword . "\n" if $self->{verbose};
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

  package Some::Other::Categorizer;
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

The following methods are provided.

=over 4

=item * dot_product(\%hash1, \%hash2)

Treats C<%hash1> and C<%hash2> as vectors, where the keys represent
the vector coordinates and the values represent the coordinate values,
and returns the dot product of the two vectors.

For instance, if C<%hash1> contains C<< (x=>4, y=>5) >> and C<%hash2>
contains C<< (x=>2, y=>7) >>, then C<dot_product(\%hash1, \%hash2)>
will return C<4*2+5*7>, i.e. C<43>.  If any keys are present in one
hash but not the other, they will be treated as if they have the value
zero in the hash where they are nonexistant.  So if C<%hash1> contains
C<< (x=>4, y=>5) >> and C<%hash2> contains C<< (y=>1, z=>6) >>, then 
C<dot_product(\%hash1, \%hash2)> will return C<5*1>, i.e. C<5>.

Perl is actually pretty good at doing dot products, because the
intersection of the set of keys of two hashes can be found very
quickly.

=item * norm(\%hash)

Returns the Euclidean norm of the values of C<%hash>, i.e. 
C<sqrt(sum(values %hash)>.

=item * normalize(\%hash)

Divides each value in C<%hash> by C<norm(\%hash)>.

=item * trim_features($target)

Reduces the number of features (words) considered in the training
data.  We try to find the "best" features, i.e. the ones that will
help us the most when we try to categorize documents later.  Right now
we just use a "Document Frequency" criterion, which means we keep the
features that appear in the most documents.  This is surprisingly
reasonable considering its simplicity, as shown in Yiming Yang's paper
"A Comparative Study on Feature Selection in Text Categorization"
(http://www-2.cs.cmu.edu/~yiming/publications.html).

=head1 AUTHOR

Ken Williams, ken@forum.swarthmore.edu

=head1 COPYRIGHT

Copyright 2000-2001 Ken Williams.  All rights reserved.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

AI::Categorize(3)

=cut

