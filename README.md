# NAME

Action::CircuitBreaker - Module to try to perform an action, with an option to suspend execution after a number of failures.

# VERSION

version 0.1

# SYNOPSIS

    # Will execute the code, as the circuit will be closed by default.

    # OO interface
    use Action::CircuitBreaker;
    Action::CircuitBreaker->new()->run(sub { do_stuff; });

# ATTRIBUTES

## error\_if\_code

    ro, CodeRef

The code to run to check if the error should count towards the circuit breaker. It defaults to:

    # Returns true if there were an exception evaluating to something true
    sub { $_[0] }

It will be given these arguments:

- as first argument, a scalar which is the value of any exception that were
raised by the `$attempt_code`. Otherwise, undef.
- as second argument, a HashRef, which contains these keys:

- action\_retry

    it's a reference on the ActionRetry instance. That way you can have access to
    the other attributes.

- attempt\_result

    It's a scalar, which is the result of `$attempt_code`. If `$attempt_code`
    returned a list, then the scalar is the reference on this list.

- attempt\_parameters

    It's the reference on the parameters that were given to `$attempt_code`.

`error_if_code` return value will be interpreted as a boolean : true return
value means the execution of `$attempt_code` was a failure and should count
towards breaking the ciruit. False means it went well.

Here is an example of code that gets the arguments properly:

    my $action = Action::CircuitBreaker->new(
      error_if_code => sub {
        my ($error, $h) = @_;

        my $attempt_code_result = $h->{attempt_result};
        my $attempt_code_params = $h->{attempt_parameters};

        my @results = @$attempt_code_result;
        # will contains (2, 4);

        my @original_parameters = @$attempt_code_params;
        # will contains (1, 2);

      }
    );
    my @results = $action->run(sub { print @_; }, 1, 2);

## on\_failure\_code

    ro, CodeRef, optional

If given, will be executed when an execution fails.

It will be given the same arguments as `error_if_code`. See `error_if_code` for their descriptions

## on\_circuit\_open

    ro, CodeRef, optional

If given, will be executed the circuit gets opened.

It will be given the same arguments as `error_if_code`. See `error_if_code` for their descriptions

## on\_circuit\_close

    ro, CodeRef, optional

If given, will be executed the circuit gets closed again.

It will be given no arguments

## max\_retries\_number

    ro, int, optional

Maximum number of retries before opening circuit.

## open\_time

    ro, int, optional

Time in number of seconds to open the circuit for after `max_retries_number` have failed.

# METHODS

## run

Does the following:

- step 1

    Tests the value of `_circuit_open_until`. If it is positive and the current
    timestamp is before the value, an error is thrown, because the circuit is
    still open. If the value is positive, but before the current timestamp,
    the circuit is closed (by setting `_circuit_open_until` to 0) and optionally,
    `on_circuit_close` is run.

- step 2

    If the value of `_circuit_open_until` is 0, the circuit is closed, and the
    passed sub gets executed. Then it runs the `error_if_code` CodeRef in
    scalar context, giving it as arguments `$error`, and the return values
    of `$attempt_code`. If it returns true, we consider that it was a failure,
    and move to step 3. Otherwise, we consider it
    means success, and return the return values of `$attempt_code`.

- step 3

    Increase the value of `_current_retries_number` and check whether it is
    larger than `max_retries_number`. If it is, then open the circuit by setting
    `_circuit_open_until` to the current time plus `open_time`, and optionally
    run `on_circuit_open`. Then, die with the `$error` from `$attempt_code`.

- step 4

    Runs the `on_failure_code` CodeRef in the proper context, giving it as
    arguments `$error`, and the return values of `$attempt_code`, and returns the
    results back to the caller.

Arguments passed to `run()` will be passed to `$attempt_code`. They will also
passed to `on_failure_code` as well if the case arises.

# SEE ALSO

This code is heavily based on [Action::Retry](https://metacpan.org/pod/Action::Retry).

# AUTHOR

hangy

# COPYRIGHT AND LICENSE

This software is copyright (c) 2018 by hangy.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
