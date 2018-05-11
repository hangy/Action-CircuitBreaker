use Action::CircuitBreaker;

use strict;
use warnings;

use Test::More;

use Try::Tiny;

{
    my $var = 0;
    my $action = Action::CircuitBreaker->new(
        attempt_code => sub { $var++; die "plop" },
    );
    try {
        $action->run();
    } catch {
        # That's OK
    };

    is($var, 10, "expected 10 tries to be run");
}

{
    my $opened = 0;
    my $action = Action::CircuitBreaker->new(
        attempt_code => sub { die "plop" },
        on_circuit_open => sub { $opened++; },
   );
    try {
        $action->run();
    } catch {
        # That's OK
   };

    is($opened, 1, "expected circuit to be opened once");
}

{
    my $closed = 0;
    my $succeed = 0;
    my $action = Action::CircuitBreaker->new(
        attempt_code => sub { return 42 if $succeed or die "plop" },
        on_circuit_close => sub { $closed++; },
        open_time => 1,
    );
    try {
        $action->run();
    } catch {
        # That's OK
    };

    sleep(2);
    $succeed = 1;
    
    my $actual = $action->run();

    is($closed, 1, "expected circuit to be closed once");
    is($actual, 42, "expected original value to be returned");
}

{
    my $action = Action::CircuitBreaker->new(
        attempt_code => sub { return 42; },
    );
    my $actual = $action->run();
    is($actual, 42, "expected original value to be returned");
}

done_testing;
