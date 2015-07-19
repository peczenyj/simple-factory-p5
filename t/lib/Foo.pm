package Foo;

use Moo;

has value => ( is => 'ro', default => sub { 0 });

sub BUILDARGS {
    my ( $self, @args ) = @_;

    if ( scalar(@args) == 1 ) {
        unshift @args, 'value'; 
    }

    return { @args }
}

1;
