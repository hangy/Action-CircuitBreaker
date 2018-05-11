package Action::CircuitBreaker;

# ABSTRACT: Module to try to perform an action, with an option to suspend execution after a number of failures.

use Scalar::Util qw(blessed);
use Time::HiRes qw(gettimeofday);
use Carp;

use base 'Exporter';
our @EXPORT = ((caller())[1] eq '-e' ? @EXPORT_OK : ());

use Moo;

=head1 SYNOPSIS

  # Simple usage, will attempt to run the code, retrying if it dies, retrying
  # 10 times max, sleeping 1 second between retries

  # OO interface
  use Action::CircuitBreaker;
  Action::CircuitBreaker->new()->run(sub { do_stuff; });

=cut

=attr error_if_code

  ro, CodeRef

The code to run to check if the error should count towards the circuit breaker. It defaults to:

  # Returns true if there were an exception evaluating to something true
  sub { $_[0] }

It will be given these arguments:

=over

=item * 

as first argument, a scalar which is the value of any exception that were
raised by the C<attempt_code>. Otherwise, undef.

=item *

as second argument, a HashRef, which contains these keys:

=over

=item action_retry

it's a reference on the ActionRetry instance. That way you can have access to
the other attributes.

=item attempt_result

It's a scalar, which is the result of C<attempt_code>. If C<attempt_code>
returned a list, then the scalar is the reference on this list.

=item attempt_parameters

It's the reference on the parameters that were given to C<attempt_code>.

=back

=back

C<error_if_code> return value will be interpreted as a boolean : true return
value means the execution of C<attempt_code> was a failure and should count
towards breaking the ciruit. False means it went well.

Here is an example of code that gets the arguments properly:

  my $action = Action::CircuitBreaker->new(
    attempt_code => sub { do_stuff; } )->run();
    attempt_code => sub { map { $_ * 2 } @_ }
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
  my @results = $action->run(1, 2);

=cut

has error_if_code => (
    is => 'ro',
    required => 1,
    isa => sub { ref $_[0] eq 'CODE' },
    default => sub { sub { $_[0] }; },
);

=attr on_failure_code

  ro, CodeRef, optional

If given, will be executed when an execution fails.

It will be given the same arguments as C<error_if_code>. See C<error_if_code> for their descriptions

=cut

has on_failure_code => (
    is => 'ro',
    isa => sub { ref $_[0] eq 'CODE' },
    predicate => 1,
);

=attr on_circuit_open

  ro, CodeRef, optional

If given, will be executed the circuit gets opened.

It will be given the same arguments as C<error_if_code>. See C<error_if_code> for their descriptions

=cut

has on_circuit_open => (
    is => 'ro',
    isa => sub { ref $_[0] eq 'CODE' },
    predicate => 1,
);

=attr on_circuit_close

  ro, CodeRef, optional

If given, will be executed the circuit gets closed again.

It will be given no arguments

=cut

has on_circuit_close => (
    is => 'ro',
    isa => sub { ref $_[0] eq 'CODE' },
    predicate => 1,
);

=cut

=attr max_retries_number

  ro, int, optional

Maximum number of retries before opening circuit.

=cut

has max_retries_number => (
    is => 'ro',
    lazy => 1,
    default => sub { 10 },
);

# the current number of retries
has _current_retries_number => (
    is => 'rw',
    lazy => 1,
    default => sub { 0 },
    init_arg => undef,
    clearer => 1,
);

=attr open_time

  ro, int, optional

Time in number of seconds to open the circuit for after C<max_retries_number> have failed.

=cut

has open_time => (
    is => 'ro',
    lazy => 1,
    default => sub { 10 },
);

# Timestamp at which the circuit is available again
has _circuit_open_until => (
    is => 'rw',
    default => sub { 0 },
    init_arg => undef,
);

=method run

Does the following:

=over

=item step 1

Runs the C<attempt_code> CodeRef in the proper context in an eval {} block,
saving C<$@> in C<$error>.

=item step 2

Runs the C<error_if_code> CodeRef in scalar context, giving it as arguments
C<$error>, and the return values of C<attempt_code>. If it returns true, we
consider that it was a failure, and move to step 3. Otherwise, we consider it
means success, and return the return values of C<attempt_code>.

=item step 3

Ask the C<strategy> if it's still useful to retry. If yes, sleep accordingly,
and go back to step 2. If not, go to step 4.

=item step 4

Runs the C<on_failure_code> CodeRef in the proper context, giving it as
arguments C<$error>, and the return values of C<attempt_code>, and returns the
results back to the caller.

=back

Arguments passed to C<run()> will be passed to C<attempt_code>. They will also
passed to C<on_failure_code> as well if the case arises.

=cut

sub run {
    my ($self, $attempt_code) = @_;

    if (my $timestamp = $self->_circuit_open_until) {
        # we can't execute until the timestamp has done
        my ($seconds, $microseconds) = gettimeofday;
        $seconds * 1000 + int($microseconds / 1000) >= $timestamp
          or die 'The circuit is open and cannot be executed.';
        $self->_circuit_open_until(0);
        $self->has_on_circuit_close
          and $self->on_circuit_close->();
    }

    my $error;
    my @attempt_result;
    my $attempt_result;
    my $wantarray;
          
    if (wantarray) {
        $wantarray = 1;
        @attempt_result = eval { $attempt_code->(@_) };
        $error = $@;
    } elsif ( ! defined wantarray ) {
        eval { $attempt_code->(@_) };
        $error = $@;
    } else {
        $attempt_result = eval { $attempt_code->(@_) };
        $error = $@;
    }

    my $h = { action_retry => $self,
              attempt_result => ( $wantarray ? \@attempt_result : $attempt_result ),
              attempt_parameters => \@_,
            };


    if ($self->error_if_code->($error, $h)) {
        $self->_current_retries_number($self->_current_retries_number + 1);
        if ($self->_current_retries_number >= $self->max_retries_number) {
            my ($seconds, $microseconds) = gettimeofday;
            my $open_until = ($self->open_time * 1000) + ($seconds * 1000 + int($microseconds / 1000));
            $self->_circuit_open_until($open_until);
            $self->has_on_circuit_open
              and $self->on_circuit_open->();
        }
    } else {
        return $h->{attempt_result};
    }
}

=back

=head1 SEE ALSO

This code is heavily based on L<Action::Retry>.

=back

=cut

1;
