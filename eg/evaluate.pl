#!/usr/bin/perl

# A sample of using AI::Categorize::Evaluate

use lib 'blib/lib';
use AI::Categorize::Evaluate;

my $data_dir = 'drmath-1.00';

my @stopwords = `cat $data_dir/SMART.stoplist`;
chomp @stopwords;

my $e = new AI::Categorize::Evaluate
  (
   #'packages'     => ['AI::Categorize::NaiveBayes','AI::Categorize::kNN'],
   #'packages'     => ['AI::Categorize::kNN'],
   'training_set' => "$data_dir/training",
   #'test_size'    => 5,
   #'iterations'   => 3,
   'test_set'     => "$data_dir/test",
   'categories'   => "$data_dir/cats.txt",
   'stopwords'    => \@stopwords,  #[qw(the a of to is that you for and)],
   #'data_dir'     => "$data_dir/data",
   'save'         => "$data_dir/save",
  );
#$e->add('AI::Categorize::NaiveBayes', args => [features_kept => 0  ]);
$e->add('AI::Categorize::kNN', args => [features_kept => 0.1]);


$e->parse_training_data;
$e->show_test_docs;
$e->crunch;
$e->categorize_test_set;
