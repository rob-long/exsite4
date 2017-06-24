package Local;
use strict;

=pod

=head1 Local.pm

B<Local.pm> - shareable website localizations.

This is a stub module, for holding any 3rd-party subroutines,
functions, or other code that may be used by ExSite, but which does
not depend on ExSite at all.

=head2 store_conf_disabled(), store_conf()

The persistent data store is set up before configuration settings are
available (since we try to load our configuration from the store
first).  That means we cannot configure the store itself through
%config.  Instead we load the store configuration from this routine
to bootstrap the system.

In the default distribution of ExSite, the store is disabled,
and is an optional feature.  To enable the store, you need to do
a few things:

=over 4

=item * remove "_disabled" from this subroutine name

=item * run ../bin/store.pl --reset to initialize the store

=item * (optional) tune any of the parameters noted in this routine

=back

=cut

sub store_conf_disabled {
    return { 
	name => "STORE",         # database file name
	lifetime => 3600,        # 1 hour
	purge_interval => 900,   # purge every 15 minutes
	purge_load => 10,        # ... unless load is over 10
	log => 0,                # logging is off
	loglimit => 100,         # length of log
	lock => "STORE.lock",    # lock file
	retry => 3,              # max number of tries on a nonblocking lock
    }
}

# EOF

1;

