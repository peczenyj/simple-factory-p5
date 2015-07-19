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

sub add_build_conf_for {
    my ($self, $identifier, $conf ) = @_;

    if ( $self->has_cache && $self->has_build_conf_for( $identifier ) ){
        # if we are using cache
        # and we substitute the configuration for some reason
        # we should first remove the cache for this particular identifier
        $self->cache->remove( $identifier );
    }

    $self->_add_build_conf_for( $identifier => $conf );
}

has fallback     => ( is => 'ro', predicate => 1 );
has build_method => ( is => 'ro', default   => sub { "new" } );
has autodie      => ( is => 'ro', isa       => Bool, default => sub { 1 } );
has autoderef    => ( is => 'ro', isa       => Bool, default => sub { 1 } );
has default      => ( is => 'ro', default   => sub { undef } );
has cache        => ( is => 'ro', isa => HasMethods [qw(get set remove)], predicate => 1 );
has error        => ( is => 'rwp', predicate => 1, clearer => 1 );

sub BUILDARGS {
    my ( $self, @args ) = @_;

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
    my ( $self, $args, $identifier ) = @_;

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
            when ('CODE')   { return $class->$method( $args->($identifier) ); }
            default {
                carp(   "cant autoderef argument ref('"
                      . ref($args)
                      . "') for class '$class'" )
            }
        }
    }

    return $class->$method($args);
}

sub _resolve_object {
    my ( $self, $identifier ) = @_;

    my $class = $self->build_class;
    if ( $self->has_build_conf_for($identifier) ) {
        return $self->_build_object_from_args(
            $self->get_build_conf_for($identifier), $identifier );
    }
    elsif ( $self->has_fallback ) {
        return $self->_build_object_from_args( $self->fallback, $identifier );
    }
   
    $self->_set_error("instance of '$class' named '$identifier' not found");
    
    confess($self->error) if $self->autodie;

    return $self->default;
}

sub resolve {
    my ( $self, $identifier ) = @_;

    $self->clear_error;
    if ( $self->has_cache ) {
        my $instance = $self->cache->get($identifier);
        return $instance->[0] if defined($instance);
    }

    my $instance = $self->_resolve_object($identifier);

    if ( $self->has_cache ) {
        $instance = $self->cache->set( $identifier => [ $instance ])->[0];
    }

    return $instance;
};

1;

