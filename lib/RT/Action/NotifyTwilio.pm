package RT::Action::NotifyTwilio;

use base qw(RT::Action::NotifySMS);

use strict;
use warnings;
use LWP::UserAgent;
use JSON qw(decode_json);

=head2 NotifyTwilio

Send a message using the Twilio web api, requires the follow
config values from RT_SiteConfig.pm:

        Set($TwilioAccounId, 'Secret');
        Set($TwilioAuthToken, 'Secret');
        Set($APIURL, 'https://api.twilio.com/2010-04-01/Accounts/');
        Set($APIDomain, 'api.twilio.com:443');
        Set($APIRealm, 'Twilio API');
        Set($MessageSender, '0123456789');

To obtain the Twilio AuthToken and AccountId create a new project of type
programmable sms. Once done setting up the project you will have access to
the projects AccountId and AuthToken.
=cut

sub SendMessage {
    my $self = shift;
    my %args = (
        Recipients => undef,
        Msg        => undef,
        @_
    );

    foreach my $config (
        qw /TwilioAccounId TwilioAuthToken APIDomain APIRealm MessageSender/)
    {
        return ( 0, 'Need to set ' . $config . ' in RT_SiteConfig.pm' )
            unless RT::Config->Get($config);
    }

    my %Credentials = (
        account_id => RT::Config->Get('TwilioAccounId'),
        auth_token => RT::Config->Get('TwilioAuthToken'),
    );

    my %Twilio = (
        api_domain => RT::Config->Get('APIDomain'),
        api_realm  => RT::Config->Get('APIRealm'),
        api_url    => RT::Config->Get('APIURL'),
        from       => RT::Config->Get('MessageSender')
    );

    my $ua = LWP::UserAgent->new;
    $ua->credentials(
        $Twilio{api_domain},      $Twilio{api_realm},
        $Credentials{account_id}, $Credentials{auth_token}
    );

    foreach my $to ( @{$args{'Recipients'}} ) {
        my %text_message = (
            From => $Twilio{'from'},
            To   => $to,
            Body => $args{Msg},
        );
        my $response = $ua->post(
              $Twilio{api_url}
            . $Credentials{account_id}
            . '/Messages.json',
            \%text_message
        );

        if ( $response->is_error ) {
            my $result = decode_json( $response->content );

            if ( $result->{message} ) {
                RT::Logger->error( "$result->{message}" );
            }
        }
    }

    return ( 1, 'Message(s) sent' );
}

1;
