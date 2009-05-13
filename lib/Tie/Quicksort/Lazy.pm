package Tie::Quicksort::Lazy;
@Tie::Quicksort::Lazy::Stable::ISA = qw/ Tie::Quicksort::Lazy /;

use Carp;

use 5.006001;
use strict;
use warnings;

our $VERSION = '0.02';
sub DEBUG() { 0 };

# object field names:
BEGIN {
   my $i = 0;
   for (qw/comparator array ready stack/){
      eval "sub $_ () {".$i++.'}'
   }
}

our $trivial = ( DEBUG ? 3 : 127 );

sub import {
	shift; # lose package name
        my %args = @_;
        $trivial = $args{TRIVIAL} || $trivial;
};

sub Tie::Quicksort::Lazy::Stable::TIEARRAY{
   my $obj = bless [];
   shift; # lose package name
   my $first = shift;
   if ( ( ref $first ) eq 'CODE' ) {
      $obj->[comparator] = $first
   }else{
      $obj->[comparator] = sub {
 DEBUG and ((defined $_[0] and defined $_[1] ) or Carp::confess "undefined arg to comparator");
 $_[0] cmp $_[1] };
      unshift @_, $first
   };
   my @array = @_;

   $obj->[ready] = 0;
   $obj->[array] = \@array;
   $obj->[stack] = [ $#array ];  # the stack contains the indices of the high ends of the unsorted partitions

   return $obj;
};
sub TIEARRAY{
   my $obj = bless [];
   shift; # lose package name
   my $first = shift;
   if ( ( ref $first ) eq 'CODE' ) {
      $obj->[comparator] = $first
   }else{
      $obj->[comparator] = sub {
 DEBUG and ((defined $_[0] and defined $_[1] ) or Carp::confess "undefined arg to comparator");
 $_[0] cmp $_[1] };
      unshift @_, $first
   };
   my @array = @_;

   for (0 .. $#array){
      # scramble to elude the dreaded quadratic situation
      my $rand = rand(@array);
      @array[$_,$rand] = @array[$rand, $_];
   };
   $obj->[ready] = 0;
   $obj->[array] = \@array;
   $obj->[stack] = [ $#array ];  # the stack contains the indices of the high ends of the unsorted partitions

   return $obj;
};


sub _sort {
   my $obj = shift;
   my $arr = $obj->[array];
   my $comp_func = $obj->[comparator];
   my $stack = $obj->[stack];
   DEBUG and warn "On entering _sort, stack is [@$stack]\n";

   MAKE_PARTITION:
   !@$stack and do {
      require Carp;
      Carp::confess( "OUT OF PARTITIONS");
   };
   my $partition_end = pop @$stack;
   my @ThisPart = @{$arr}[0 .. $partition_end];
   DEBUG and warn "working with partition 0 .. $partition_end [@ThisPart]\n";
   if (@ThisPart <= $trivial ) {
      $obj->[ready] = @ThisPart;  # size of @ThisPart
      DEBUG and warn "trivial partition,@{[$obj->[ready]]} ready elts\n";
      $partition_end or return;
      DEBUG and warn "sorting block 0 .. $partition_end\n";
      DEBUG and warn "BEFORE: [@$arr]\n";
      @{$arr}[0 .. $partition_end] = sort { $comp_func->($a,$b) } @ThisPart;
      DEBUG and warn " AFTER: [@$arr]\n";
      return
   };
   my @HighSide = ();
   my @LowSide = ();

   # by choosing the last elt as the pivot
   # and putting equal elts on the end of the low side
   # we get a stable sort -- which doesn't matter because
   # we scrambled the input

   my $pivot = pop @ThisPart;

   while (@ThisPart) {
      my $subject = shift @ThisPart;
      if ($comp_func->($pivot, $subject) < 0 ){
         # we are looking at an elt that comes after the pivot
         push @HighSide, $subject
      }else{
         push @LowSide, $subject
      };
   };
   @{$arr}[0 .. $partition_end] = (@LowSide, $pivot, @HighSide);
   @HighSide and push @$stack, $#HighSide; # defer the high side
   push @$stack, 0; # this pivot,
   @LowSide and push @$stack, $#LowSide; # defer the low side
   DEBUG and warn "stack now @$stack\n";
   goto MAKE_PARTITION;

}


sub FETCHSIZE { 
	scalar @{ $_[0]->[array] } 
}

sub SHIFT {
	# $_[0]->_sort unless $_[0]->[ready]--;

#       CHECK_READY:
#       DEBUG and warn "in SHIFT, have ",$_[0]->[ready], " ready elts\n";
#       if ($_[0]->[ready]--){
#           return shift(@{ $_[0]->[array] });
#        }else{
#           $_[0]->_sort;
#           goto CHECK_READY;
#        }

# observing the taboo against goto, that's
       DEBUG and warn "in SHIFT, have ",$_[0]->[ready], " ready elts\n";
       while ( $_[0]->[ready]-- == 0){
           $_[0]->_sort;
       };
       shift(@{ $_[0]->[array] });
}

*STORE = *PUSH = *UNSHIFT = *FETCH =
*STORESIZE = *POP = *EXISTS = *DELETE =
*CLEAR = sub {
   require Carp;
   Carp::croak ('"shift" is the only accessor defined for a '.
               __PACKAGE__ . " array");
};

1;
__END__

=head1 NAME

Tie::Quicksort::Lazy - a lazy quicksort with tiearray interface

=head1 SYNOPSIS

  use Tie::Quicksort::Lazy TRIVIAL => 1023;
  tie my @producer, Tie::Quicksort::Lazy, @input;
  while (@producer){
    my $first_remaining = shift @producer;
    ...
  };
  
  use sort 'stable';
  tie my @StableProducer, Tie::Quicksort::Lazy::Stable, \&comparator,  @input;
  ...

=head1 DESCRIPTION

A pure-perl lazy quicksort.  The only defined way to
access the resulting tied array is with C<shift>.

Sorting is deferred until an item is required.

=head2 memory use

This module operates on a copy of the input array.

Internal copies are made during the partitioning process
to greatly improve readability, instead of doing in-place
swaps and tracking a lot of array indices.  Future releases
of this module, if any, may do it differently.

So initially the Tie::Quicksort::Lazy object will include 
an array the size of the input array, and the first partitioning
will use a temporary array that size too.  Later partitions will
be smaller.  Since the first partitioning is deferred until the
first shift operation, if we have enough memory to build the object,
and then forget about the input, we will have enough memory to
partition it.

     tie my @LazySorted, Tie::Quicksort::Lazy get_unsorted_data();
     while (@LazySorted) {
          my $first = shift @LazySorted;
          ...
     };

=head2 stability

For a stable variant, tie to Tie::Quicksort::Lazy::Stable instead
and use a stable perl sort for the trivial sort or set 
"TRIVIAL" to 1 on the use line.

=head2 BYO (Bring Your Own) comparator

when the first parameter is an unblessed coderef,
that coderef will be used as the sort
comparison function. The default is

   sub { $_[0] cmp $_[1] }

Ergo, if you want to use this module to sort a list of coderefs,
you will need to bless the first one.

=head2 trivial partition

A constant C<trivial> is defined which declares the size of a partition
that we simply hand off to Perl's sort for sorting. This defaults to
127.

=head1 INSPIRATION

this module was inspired by an employment interview question
concerning the quicksort-like method of selecting the first k
from n items ( see L<http://en.wikipedia.org/wiki/Quicksort#Selection-based_pivoting> )

=head1 HISTORY

=over 8

=item 0.01

Original version; created by h2xs 1.23 with options

  -ACX
	-b
	5.6.1
	-n
	Tie::Quicksort::Lazy

=item 0.02

revised to use perl arrays for partitioning operations instead of a
confusing profusion of temporary index variables

=back



=head1 SEE ALSO

L<Tie::Array::Sorted::Lazy> is vaguely similar

=head1 AUTHOR

David L. Nicol davidnico@cpan.org

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009 by the author

This library is free software; you may redistribute and/or modify
it under the same terms as Perl.


=cut

