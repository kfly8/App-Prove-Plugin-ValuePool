package Test::ValuePool;
use strict;
use warnings;

use Cache::FastMmap;

sub new {
    my ($class, %args) = @_;

    unless (exists $args{share_file}) {
        die "share_file is required";
    }

    unless (exists $args{_owner_pid}) {
        $args{_owner_pid} = $$;
    }

    bless \%args => $class;
}

sub values     { $_[0]->{values}  }
sub share_file { $_[0]->{share_file} }
sub _owner_pid { $_[0]->{_owner_pid} }

sub cache         { $_[0]->{cache}        ||= $_[0]->_build_cache }
sub prepare_hook  { $_[0]->{prepare_hook} ||= $_[0]->_build_prepare_hook }
sub teardown_hook { $_[0]->{teardown_hook} ||= $_[0]->_build_teardown_hook }

sub _build_cache {
    my $self = shift;

    # dont let Cache::FastMmap delete the share_file,
    # File::Temp does that
    return Cache::FastMmap->new(
        share_file     => $self->share_file,
        init_file      => 0,
        empty_on_exit  => 0,
        unlink_on_exit => 0,
        cache_size     => '1k',
    );
}

sub _build_prepare_hook {
    return sub {
        my ($self) = @_;
        # do nothing
    }
}

sub _build_teardown_hook {
    return sub {
        my ($self) = @_;
        # do nothing
    }
}

sub EMPTY() { 0 }

sub prepare {
    my $self = shift;

    $self->prepare_hook->($self);

    $self->cache->clear;
    $self->cache->set( spaces => {
        map { $_ => EMPTY } 0 .. @{ $self->values } - 1
    });
}

sub alloc {
    my ($self) = @_;

    my $result_index;
    do {
        $self->cache->get_and_set( spaces => sub {
            my (undef, $spaces) = @_;

            for my $index (keys %$spaces) {
                if ( $spaces->{ $index } == EMPTY ) {
                    # alloc one from unused
                    $result_index = $index;
                    $spaces->{ $index } = $$; # record pid
                    return $spaces;
                }
            }

            return $spaces;
        });

        return $self->values->[$result_index] if defined $result_index;

        sleep 1;

    } while ( ! defined $result_index );
}

sub dealloc_unused {
    my ($self) = @_;

    $self->cache->get_and_set( spaces => sub {
        my (undef, $spaces) = @_;
        for my $index (keys %$spaces) {

            my $pid = $spaces->{ $index };
            next if $pid == EMPTY;

            if ( ! $self->_pid_lives( $pid ) ) {
                $spaces->{ $index } = EMPTY; # dealloc
            }
        }

        return $spaces;
    });
}

sub _pid_lives {
    my ($self, $pid) = @_;

    my $command = "ps -o pid -p $pid | grep $pid";
    my @lines   = qx{$command};
    return scalar @lines;
}

sub teardown {
    my ($self) = @_;
    if ($$ == $self->_owner_pid) {
        $self->teardown_hook->($self);
    }
}

sub DESTROY {
    my $self = shift;
    $self->teardown();
}

1;
__END__

=head1 NAME

Test::ValuePool - create a pool of values

=head1 SYNOPSIS

  use Test::ValuePool;

  my $pool = Test::ValuePool->new(
    values => ['dsn1', 'dsn2', 'dsn3'],
  );

  my $dsn1 = $pool->alloc; # in process 1
  my $dsn2 = $pool->alloc; # in process 2
  # my $dsn3 = $pool->alloc; # blocks

  # after process 1 death
  $pool->dealloc_unused;

  my $dsn3 = $pool->alloc; # in process 3 (get dsn from pool; reused $dsn of process 1)

=cut
