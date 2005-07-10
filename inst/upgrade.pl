#!/usr/bin/perl -w

=head1 NAME

upgrade.pl - installation script to gather upgrade information

=head1 VERSION

$LastChangedRevision$

=head1 DATE

$LastChangedDate$

=head1 DESCRIPTION

This script is called by "make upgrade" to prepare for an upgrade.
Gathers configuration information from the user and install.db if
available.  Outputs to the various .db files used by later stages of
the install.

=head1 AUTHOR

Sam Tregar <stregar@about-inc.com>

=head1 SEE ALSO

L<Bric::Admin>

=cut

use strict;
use FindBin;
use lib "$FindBin::Bin/lib";
use Bric::Inst qw(:all);
use File::Spec::Functions qw(:ALL);
use Data::Dumper;

# make sure we're root, otherwise uninformative errors result
unless ($> == 0) {
    print "This process must (usually) be run as root.\n";
    exit 1 unless ask_yesno("Continue as non-root user?", 1);
}

# setup default root
our %UPGRADE = ( BRICOLAGE_ROOT => $ENV{BRICOLAGE_ROOT} ||
                                   '/usr/local/bricolage' );
our $INSTALL;

# determine version being installed
use lib './lib';
require Bric;
our $VERSION = $Bric::VERSION;

print q{
##########################################################################

  We strongly recommend that you `make clone` your existing installation
  (using the sources for that version ) BEFORE running `make upgrade`.
  This is so that if there are any problems with the upgrade, you can
  delete the installation, install the clone, fix the problems, and then
  try `make upgrade` again.

##########################################################################

};

exit 1 unless ask_yesno("Continue with the upgrade?", 1);

print "\n\n==> Setting-up Bricolage Upgrade Process <==\n\n";

get_bricolage_root();
read_install_db();
check_version();
confirm_paths();
output_dbs();

print "\n\n==> Finished Setting-up Bricolage Upgrade Process <==\n\n";

# find the bricolage to update
sub get_bricolage_root {
    ask_confirm("Bricolage Root Directory to Upgrade?",
                \$UPGRADE{BRICOLAGE_ROOT});

    # verify that we have a Bricolage install here
    hard_fail("No Bricolage installation found in $UPGRADE{BRICOLAGE_ROOT}.\n")
        unless -e catfile($UPGRADE{BRICOLAGE_ROOT}, "conf", "bricolage.conf");

    # verify that this Bricolage was installed with "make install"
    hard_fail("The Bricolage Installation found in $UPGRADE{BRICOLAGE_ROOT}\n",
              "was installed manually and cannot be automatically upgraded.")
        unless -e catfile($UPGRADE{BRICOLAGE_ROOT}, "conf", "install.db");
}

# read the install.db file from the chosen bricolage root
sub read_install_db {
    my $install_file = catfile($UPGRADE{BRICOLAGE_ROOT}, "conf", "install.db");
    if (-e $install_file) {
        # read it in if it exists
        do $install_file or die "Failed to read $install_file : $!";
    }
}

# check that the version number exists in the version database, note
# the versions need to upgrade to current version
sub check_version {
    my @todo;

    # make sure we're not trying to install the same version twice
    if ($INSTALL->{VERSION} eq $VERSION) {
        print <<END;
The installed version ("$VERSION") is the same as this version!  "make
upgrade" is only designed to work to upgrade from one version to
another.  Please use "make install if you wish to overwrite your
current install.

END
        exit 1 unless ask_yesno("Continue with upgrade? [no] ", 0);
        @todo = ($VERSION);

    } else {
        # read in versions.txt
        my @versions;
        open(VER, "inst/versions.txt") or die "Cannot open inst/versions.txt : $!";
        while (<VER>) {
            chomp;
            next if /^#/ or /^\s*$/;
            push @versions, $_;
        }
        close VER;

        # find this version
        my $found;
        for my $i (0 .. $#versions) {
            if ($versions[$i] eq $INSTALL->{VERSION}) {
                $found = 1;
                @todo = @versions[$i + 1 .. $#versions];
                last;
            }
        }

        # didn't find the version?
        hard_fail(<<END) unless $found;
Couldn't find version "$INSTALL->{VERSION}" in inst/versions.txt.  Are
you trying to install an older version over a newer one?  That won't
work.
END
    }

    # save todo list for later
    $UPGRADE{TODO} = \@todo;

    # note the plan of action
    print "Found existing version $INSTALL->{VERSION}.\n";
    print "Will run database upgrade scripts for version(s) ",
      join(', ', @todo), "\n"
        if @todo;
}

# confirm paths listed in install.db
sub confirm_paths {
    print "\nPlease confirm the Bricolage target directories.\n\n";
    ask_confirm("Bricolage Perl Module Directory",
                \$INSTALL->{CONFIG}{MODULE_DIR});
    ask_confirm("Bricolage Executable Directory",
                \$INSTALL->{CONFIG}{BIN_DIR});
    ask_confirm("Bricolage Man-Page Directory (! to skip)",
                \$INSTALL->{CONFIG}{MAN_DIR});
    ask_confirm("Mason Component Directory",
                \$INSTALL->{CONFIG}{MASON_COMP_ROOT});
}

# output .db files used by installation steps
sub output_dbs {
    # fake up the .dbs from %INSTALL
    my %dbs = ( PG     => "postgres.db",
                CONFIG => "config.db",
                AP     => "apache.db"  );
    while ( my ($key, $file) = each %dbs) {
        # We must have a version number for PostgreSQL.
        next if $key eq 'PG' && !$INSTALL->{$key}{version};
        open(FILE, ">$file") or die "Unable to open $file : $!";
        print FILE Data::Dumper->Dump([$INSTALL->{$key}], [$key]);
        close(FILE);
    }

    # output upgrade.db
    open(FILE, ">upgrade.db") or die "Unable to open upgrade.db : $!";
    print FILE Data::Dumper->Dump([\%UPGRADE], ["UPGRADE"]);
    close(FILE);
}
