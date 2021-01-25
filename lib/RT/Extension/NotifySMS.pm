use strict;
use warnings;

package RT::Extension::NotifySMS;

our $VERSION = '0.01';

=head1 NAME

RT-Extension-NotifySMS - Provide additional actions to send text messages

=head1 RT VERSION

Works with RT 5.

=head1 INSTALLATION

=over

=item C<perl Makefile.PL>

=item C<make>

=item C<make install>

May need root permissions

=item C<make initdb>

Only run this the first time you install this module.

If you run this twice, you may end up with duplicate data
in your database.

=item Edit your F</opt/rt5/etc/RT_SiteConfig.pm>

Add this line:

    Plugin('RT::Extension::NotifySMS');

You will also need to set other config values depending on which
SMS action is being used. See L<CONFIGURATION> for details.

=item Clear your mason cache

    rm -rf /opt/rt5/var/mason_data/obj

=item Restart your webserver

=back


=head1 DESCRIPTION

Provide additional actions for Scrips, that allow for the sending of SMS
messages based on actions in RT.

Notify SMS actions use the Mobile Phone value from each user record. If the
user has no Mobile Phone set, no message is sent.

After installation you will see new notification actions are available for your RT scrips.

If notifying a more specific role on a ticket is desired, create a new
action in the RT web UI:

    Admin->Global->Actions

The "Action Module" is "NotifyTwilio". In the "Parameters to Pass" section
provide one or more of the following:

    All, Owner, Requestor, AdminCc, Cc

The content of your outgoing SMS alerts is set using RT templates the same
way email notification content is set. One caveat is that SMS notification
templates should not have any header values, meaning that they will have a
blank line as the first line in the template ( Only applicable for Perl templates ).

To send "on reply" content via SMS use the following template:

{$Transaction->Content()}

With an empty line before the above code.

=head1 CONFIGURATION

Currently this extension supports the Twilio SMS service.

=head2 Twilio

To send a message using the Twilio web API, set the following values in RT_SiteConfig.pm:

        Set( $TwilioAccounId, 'Secret' );
        Set( $TwilioAuthToken, 'Secret' );
        Set( $APIURL, 'https://api.twilio.com/2010-04-01/Accounts/' );
        Set( $APIDomain, 'api.twilio.com:443' );
        Set( $APIRealm, 'Twilio API' );
        Set( $MessageSender, '0123456789' );

To obtain a Twilio AuthToken and AccountId, create a new project of type
programmable SMS in the Twilio console. These values can be found in
your L<Twilio account|https://www.twilio.com/console>.

=cut

=head1 AUTHOR

Best Practical Solutions, LLC E<lt>modules@bestpractical.comE<gt>

=head1 BUGS

All bugs should be reported via email to

    L<bug-RT-Extension-NotifySMS@rt.cpan.org|mailto:bug-RT-Extension-NotifySMS@rt.cpan.org>

or via the web at

    L<rt.cpan.org|http://rt.cpan.org/Public/Dist/Display.html?Name=RT-Extension-NotifySMS>.

=head1 LICENSE AND COPYRIGHT

This software is Copyright (c) 2018 by Bestpractical Solutions

This is free software, licensed under:

  The GNU General Public License, Version 2, June 1991

=cut

1;
