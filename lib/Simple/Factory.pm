use strict;
use warnings;
package Simple::Factory;

#ABSTRACT: simple factory 

use feature 'switch';
use Carp qw(carp confess);
use Module::Runtime qw(use_module);

use Moo;
use MooX::HandlesVia;
use MooX::Types::MooseLike::Base qw(HasMethods HashRef Any Bool);
use namespace::autoclean;

has build_class => (
    is       => 'ro',
    required => 1,
    coerce   => sub { 
        my ($class) = @_; 
        use_module($class); 
    }
);

has build_conf => (
    is          => 'ro',
    isa         => HashRef [Any],
    required    => 1,
    handles_via => 'Hash',
    handles => { 
        has_build_conf_for  => 'exists', 
        get_build_conf_for  => 'get',
        _add_build_conf_for => 'set',
    }
);

has fallback     => ( is => 'ro', predicate => 1 );
has build_method => ( is => 'ro', default   => sub { "new" } );
has autoderef    => ( is => 'ro', isa       => Bool, default => sub { 1 } );
has silence      => ( is => 'ro', isa       => Bool, default => sub { 0 } );
has default      => ( is => 'ro', default   => sub { undef } );
has cache        => ( is => 'ro', isa       => HasMethods [qw(get set remove)], predicate => 1 );

sub BUILDARGS {
    my ( $self, @args ) = @_;

    unshift @args, "build_class" if scalar(@args) == 1;
    
    my (%hash_args) = @args;

    if (   scalar(@args) >= 2
        && !exists $hash_args{build_class}
        && !exists $hash_args{build_conf} )
    {
        my $build_class = $args[0];
        my $build_conf  = $args[1];

        $hash_args{build_class} = $build_class;
        $hash_args{build_conf}  = $build_conf;
    }

    \%hash_args;
}

sub _build_object_from_args {
    my ( $self, $args, $key ) = @_;

    my $class  = $self->build_class;
    my $method = $class->can( $self->build_method )
      or confess "class '$class' does not support build method: "
      . $self->build_method;

    if ( $self->autoderef && defined ref($args) ) {
        given ( ref($args) ) {
            when ('ARRAY')  { return $class->$method( @{$args} ); }
            when ('HASH')   { return $class->$method( %{$args} ); }
            when ('SCALAR') { return $class->$method($$args); }
            when ('REF')    { return $class->$method($$args); }
            when ('GLOB')   { return $class->$method(*$args); }
            when ('CODE')   { return $class->$method( $args->($key) ); }
            default {
                carp(   "cant autoderef argument ref('"
                      . ref($args)
                      . "') for class '$class'" ) if ! $self->silence;
            }
        }
    }

    return $class->$method($args);
}

sub _resolve_object {
    my ( $self, $key ) = @_;

    my $class = $self->build_class;
    if ( $self->has_build_conf_for($key) ) {
        return $self->_build_object_from_args(
            $self->get_build_conf_for($key), $key );
    }
    elsif ( $self->has_fallback ) {
        return $self->_build_object_from_args( $self->fallback, $key );
    }
   
    confess("instance of '$class' named '$key' not found");
}

sub add_build_conf_for {
    my ($self, $key, $conf ) = @_;

    if ( $self->has_cache && $self->has_build_conf_for( $key ) ){
        # if we are using cache
        # and we substitute the configuration for some reason
        # we should first remove the cache for this particular key
        $self->cache->remove( $key );
    }

    $self->_add_build_conf_for( $key => $conf );
}

sub resolve {
    my ( $self, $key ) = @_;

    if ( $self->has_cache ) {
        my $instance = $self->cache->get($key);
        return $instance->[0] if defined($instance);
    }

    my $instance = $self->_resolve_object($key);

    if ( $self->has_cache ) {
        $instance = $self->cache->set( $key => [ $instance ])->[0];
    }

    return $instance;
};

1;

