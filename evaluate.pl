#!/usr/bin/perl

# A sample of using AI::Categorize::Evaluate

use lib 'blib/lib';
use AI::Categorize::Evaluate;

my $e = new AI::Categorize::Evaluate
  (
   'packages'     => ['AI::Categorize::NaiveBayes','AI::Categorize::kNN'],
   'training_set' => 'test_data/training',
   #'test_size'    => 5,
   'test_set'     => 'test_data/test',
   'categories'   => 'test_data/cats.txt',
   'stopwords'    => [qw(the a of to is that you for and)],
   'data_dir'     => 'test_data/data',
  );

$e->parse_training_data;
$e->crunch;
$e->categorize_test_set;


