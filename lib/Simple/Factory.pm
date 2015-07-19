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

__END__ 

=head1 NAME

Simple::Factory - a simple factory to create objects easily, with cache, autoderef and fallback supports

=head1 SYNOPSYS

    use Simple::Factory;

    my $factory = Simple::Factory->new(
        'My::Class' => {
            first  => { value => 1 },
            second => [ value => 2 ],
        },
        fallback => { value => undef }, # optional. in absent, will die if find no key
    );

    my $first  = $factory->resolve('first');  # will build a My::Class instance with arguments 'value => 1'
    my $second = $factory->resolve('second'); # will build a My::Class instance with arguments 'value => 2'
    my $last   = $factory->resolve('last');   # will build a My::Class instance with fallback arguments

=head1 DESCRIPTION

This is one way to implement the Factory Pattern L<http://www.oodesign.com/factory-pattern.html>. The main objective is substitute one hashref of objects ( or coderefs who can build/return objects ) by something more intelligent, who can support caching and fallbacks. If the creation rules are simple we can use C<Simple::Factory> to help us to build instances.

We create instances with C<resolve> method. It is lazy. If you need build all instances (to store in the cache) consider try to resolve them first.

If you need something more complex, consider some framework of Inversion of Control (IoC).

For example, we can create a simple factory to create DateTime objects, using CHI as cache:

   my $factory = Simple::Factory->new(
        build_class  => 'DateTime',
        build_method => 'from_epoch',
        build_conf   => {
            one      => { epoch => 1 },
            two      => { epoch => 2 },
            thousand => { epoch => 1000 }
        },
        fallback => sub { epoch => $_[0] }, # fallback can receive the key
        cache    => CHI->new( driver => 'Memory', global => 1),
    );

  $factory->resolve( 1024 )->epoch # returns 1024

IMPORTANT: if the creation fails ( like some excetion from the constructor ), we will B<not> call the C<fallback>. We expect some error handling from your side.

=head1 ATTRIBUTES

=head2 build_class

Specify the perl package ( class ) used to create instances. Using C<Method::Runtime>, will die if can't load the package.

This argument is required. You can omit by using the C<build_class> as a first argument of the constructor.

=head2 build_args

Specify the mapping of key => arguments, storing in a hashref.

This argument is required. You can omit by using the C<build_class> and C<build_args> as a first pair of arguments.

Important: if C<autoderef> is true, we will try to deref the value before use to create an instance. 
=head2 fallback

The default behavior is die if we try to resolve an instance using one non-existing key.

But if fallback is present, we will use this on the constructor.

If C<autoderef> is true and fallback is a code reference, we will call the code and pass the key as an argument.

=head2 build_method

By default the C<Simple::Factory> calls the method C<new> but you can override and specify your own build method.

Will croak if the C<build_class> does not support the method on C<resolve>.

=head2 autoderef

If true ( default ), we will try to deref the argument present in the C<build_conf> only if it follow this rules:

- will deref only references
- if the reference is an array, we will call the C<build_method> with C<@$array>.  
- if the reference is a hash, we will call the C<build_method> with C<%$hash>.
- if the reference is a scalar or other ref, we will call the C<build_method> with C<$$ref>.
- if the reference is a glob, we will call the C<build_method> with C<*$glob>.
- if the reference is a code, we will call the C<build_method> with $code->( $key ) ( same thinf for the fallback ) 
- other cases (like Regexes) we will carp if it is not in C<silence> mode. 

=head2 silence

If true ( default is false ), we will omit the carp message if we can't C<autoderef>.

=head2 cache

If present, we will cache the result of the method C<resolve>. The cache should responds to C<get>, C<set> and C<remove> like L<CHI>.

We will also cache fallback cases.

If we need add a new build_conf via C<add_build_conf_for>, and override one existing configuration, we will remove it from the cache if possible.

default: not present

=head1 METHODS

=head2 add_build_conf_for

usage: add_build_conf_for( key => configuration )

Can add a new build configuration for one specific key. It is possible add new or just override.

Will remove C<cache> if possible.

Example:
    $factory->add_build_conf_for( last => { foo => 1, bar => 2 })

=cut
=head2 resolve

usage: resolve( key )

The main method. Will build one instance of C<build_class> using the C<build_conf> and C<build_method>. 

Should receive a key and if does not exist a C<build_conf> will try use the fallback if specified, or will die ( confess ).

If the C<cache> is present, will try to return first one object from the cache using the C<key>, or will resolve and
store in the cache for the next call.

If we have some exception when we try to create an instance for one particular key, we will not call the C<fallback>. 
We use C<fallback> when we can't find the C<build_conf> based on the key. 

=head1 SEE ALSO

=over 4

=item L<Bread-Board>

A solderless way to wire up your application components.

=item L<IOC>

A lightweight IOC (Inversion of Control) framework

=back

=head1 AUTHOR

Tiago Peczenyj <tiago (dot) peczenyj (at) gmail (dot) com>

=head1 BUGS

Please report any bugs or feature requests on the bugtracker website
https://github.com/peczenyj/simple-factory-p5/issues

