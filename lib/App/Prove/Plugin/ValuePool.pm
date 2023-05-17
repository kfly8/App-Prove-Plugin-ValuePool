package App::Prove::Plugin::ValuePool;
use strict;
use warnings;

our $VERSION = "0.01";

use File::Temp;
use POSIX::AtFork;
use Test::ValuePool;
use JSON ();

sub load {
    my ($class, $prove) = @_;
    my @args     = @{ $prove->{args} };
    my $lib      = $prove->{ app_prove }->lib;
    my $blib     = $prove->{ app_prove }->blib;
    my $includes = $prove->{ app_prove }->includes;

    my $setup_class = $args[ 0 ];
    warn "setup_class: $setup_class\n";

    my $share_file = File::Temp->new(); # deleted when DESTROYed
    my $pool       = Test::ValuePool->new(
        share_file => $share_file->filename,
        values => ['test1', 'test2'], # FIXME
    );
    $pool->prepare;

    $prove->{ app_prove }{ __PACKAGE__ } = [ $pool, $share_file ]; # ref++
    $prove->{ app_prove }->formatter('TAP::Formatter::ValuePool');

    $ENV{ PERL_APP_PROVE_PLUGIN_VALUEPOOL_SHARE_FILE } = $share_file->filename;

    POSIX::AtFork->add_to_child(create_child_hook($$));

    1;
}

sub create_child_hook {
    my ($ppid) = @_;
    return sub {
        my ($call) = @_;

        # we're in the test process

        # prove uses 'fork' to create child processes
        # our own 'ps -o pid ...' uses 'backtick'
        # only hook 'fork'
        ($call eq 'fork')
            or return;

        # restrict only direct child of prove
        (getppid() == $ppid)
            or return;

        my $share_file = $ENV{ PERL_APP_PROVE_PLUGIN_VALUEPOOL_SHARE_FILE }
            or return;

        my $value = Test::ValuePool->new( share_file => $share_file )->alloc;

        # use this in tests
        $ENV{ PERL_TEST_VALUEPOOL_VALUE } = encode_json($value);
    };
}

{
    my $JSON = JSON->new->allow_nonref;
    sub encode_json {
        my ($value) = @_;
        return $JSON->encode($value);
    }
}

{
    package TAP::Formatter::ValuePool::Session;
    use parent 'TAP::Formatter::Console::Session';

    sub close_test {
        my $self = shift;

        my $share_file = $ENV{ PERL_APP_PROVE_PLUGIN_VALUEPOOL_SHARE_FILE }
            or return;
        Test::ValuePool->new( share_file => $share_file )->dealloc_unused;

        $self->SUPER::close_test(@_);
    }
}

{
    package TAP::Formatter::ValuePool;
    use parent 'TAP::Formatter::Console';

    sub open_test {
        my $self = shift;

        bless $self->SUPER::open_test(@_), 'TAP::Formatter::ValuePool::Session';
    }
}

1;
__END__

=head1 NAME

App::Prove::Plugin::ValuePool - pool of values reused while testing

=head1 SYNOPSIS

    prove -j4 -PValuePool=test1,test2 t

        or

    prove -j4 -PValuePool=MyApp::Test::Setup t

=head1 DESCRIPTION

App::Prove::Plugin::ValuePool is ...


    package MyApp::Test::Setup {
        use Test::mysqld;

        my @mysqlds;

        sub prepare {
            my ($pool) = @_;

            @mysqlds = Test::mysqld->start_mysqlds(200); # TODO accept args
            $pool->values([map { $_->dsn } @mysqlds]);

            my $orig = $SIG{INT};
            $SIG{INT} = sub {
                $pool->teardown();

                if ($orig) {
                    $orig->();
                } else {
                    $SIG{INT} = 'DEFAULT';
                    kill INT => $$;
                }
            };
        }

        sub teardown {
            my ($pool) = @_;
            Test::mysqld->stop_mysqlds(grep { defined($_) } @mysqlds);
            @mysqlds = ();
        }
    }

=head1 LICENSE

Copyright (C) kobaken.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

kobaken E<lt>kentafly88@gmail.comE<gt>

=cut

