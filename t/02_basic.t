use strict;
use warnings;
use Test::More;
use Test::Exception; 
use CHI;
use Scalar::Util qw(refaddr);
use Simple::Factory;

subtest "basic test" => sub {
    my $ref = { epoch => 2 };
    my $factory = Simple::Factory->new(
        build_class  => 'DateTime',
        build_method => 'from_epoch',
        build_conf   => {
            one      => { epoch => 1 },
            two      => \$ref,
            thousand => [ epoch => 1000 ]
        },
        fallback => sub { epoch => $_[0] },
    );

    ok $factory->autoderef, 'autoderef should be true';
    ok !defined( $factory->default ),
      'default value should be undef ( but useless on autodie mode )';

    is $factory->resolve('one')->epoch, 1, 'should be one';
    is $factory->resolve('two')->epoch, 2, 'should be two ( from ref ref )';
    is $factory->resolve('thousand')->epoch, 1000,
      'should be thousand ( by arrayref )';
    is $factory->resolve(1024)->epoch, 1024,
'should use the identifier as argument if the fallback is ref code and autoderef is true';

    my $a = $factory->resolve('one');
    my $b = $factory->resolve('one');

    ok !$factory->has_cache, 'should not had cache';
    ok refaddr($a) ne refaddr($b),
      'should return different instances without cache';

};

subtest 'cache' => sub {
    my $hash    = {};
    my $factory = Simple::Factory->new(
        build_class  => 'DateTime',
        build_method => 'from_epoch',
        build_conf   => { now => { epoch => time } },
        cache        => CHI->new( driver => 'RawMemory', datastore => $hash )
    );

    my $a = $factory->resolve('now');
    my $b = $factory->resolve('now');

    ok $factory->has_cache, 'should had cache';
    ok refaddr($a) eq refaddr($b),
      'should return the same instances with cache';
};

subtest "class Foo" => sub {
    my $factory = Simple::Factory->new(
        build_class => 'IO::File',
        build_conf  => { null => [qw(/dev/null w)], },
    );

    isa_ok $factory->resolve('null'), 'IO::File', 'builder->resolve( null )';

    throws_ok { 
        $factory->resolve('not exist');
    } qr/instance of 'IO::File' named 'not exist' not found/, 'should die';
};

subtest "class Foo with simple args" => sub {
    my $factory = Simple::Factory->new(
        'IO::File' => { null => [qw(/dev/null w)], },
    );

    isa_ok $factory->resolve('null'), 'IO::File', 'builder->resolve( null )';
};

done_testing;
