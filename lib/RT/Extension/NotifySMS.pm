use strict;
use warnings;

package RT::Extension::NotifySMS;

our $VERSION = '0.01';

=head1 NAME

RT-Extension-Text-Messages - Provide addional actions to send text messages.

=head1 DESCRIPTION

Provide addional actions for Scrips, that allow for the sending of messages
inplace of email. The new action can be loaded in the web UI from:

Global -> Actions -> Create

where the action module is one of the notify option from this extension:

"NotifyTwilio"

For the action you can choose to pass the following parameters:

All, Owner, Requestor, AdminCc, Cc

=head1 RT VERSION

Works with RT 4.4.0

=head1 INSTALLATION

=over

=item C<perl Makefile.PL>

=item C<make>

=item C<make install>

May need root permissions

=item Edit your F</opt/rt4/etc/RT_SiteConfig.pm>

If you are using RT 4.4 or greater, add this line:

    Plugin('RT::Extension::NotifySMS');

You will need to set the following config values as well as other specific
to the notify action being implemented:

    Set(@MessageRoles, 'AdminCc');

=item Clear your mason cache

    rm -rf /opt/rt4/var/mason_data/obj

=item Restart your webserver

=back

=head1 AUTHOR

Best Practical Solutions, LLC E<lt>modules@bestpractical.comE<gt>

=head1 BUGS

All bugs should be reported via email to

    L<bug-RT-Extension-Text-Messages@rt.cpan.org|mailto:bug-RT-Extension-Text-Messages@rt.cpan.org>

or via the web at

    L<rt.cpan.org|http://rt.cpan.org/Public/Dist/Display.html?Name=RT-Extension-Text-Messages>.

=head1 LICENSE AND COPYRIGHT

This software is Copyright (c) 2018 by Bestpractical Solutions

This is free software, licensed under:

  The GNU General Public License, Version 2, June 1991

=cut

1;
