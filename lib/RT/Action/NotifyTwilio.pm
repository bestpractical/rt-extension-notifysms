package RT::Action::NotifyTwilio;

use base qw(RT::Action::NotifySMS);

use strict;
use warnings;
use LWP::UserAgent;

=head2 NotifyTwilio

Send a message using the Twilio web api, requires the follow
config values from RT_SiteConfig.pm:

        Set($TwilioAccounId, 'Secret');
        Set($TwilioAuthToken, 'Secret');
        Set($APIDomain, 'api.twilio.com:443');
        Set($APIRealm, 'Twilio API');
        Set($MessageSender,  0123456789);

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

    return ( 0, 'Please provide a message to send' ) unless $args{Msg};
    return ( 0, 'Please provide a recipient' )
        unless scalar $args{Recipients};

    my %Credentials = (
        account_id => RT::Config->Get('TwilioAccounId'),
        auth_token => RT::Config->Get('TwilioAuthToken'),
    );

    my %Twilio = (
        api_domain => RT::Config->Get('APIDomain'),
        api_realm  => RT::Config->Get('APIRealm'),
        from       => RT::Config->Get('MessageSender'),

        api_url => 'https://api.twilio.com/2010-04-01/Accounts/'
            . $Credentials{account_id}
            . '/Messages'
    );

    my $ua = LWP::UserAgent->new;
    $ua->credentials(
        $Twilio{api_domain},      $Twilio{api_realm},
        $Credentials{account_id}, $Credentials{auth_token}
    );

    foreach my $to ( $args{Recipients} ) {
        my %text_message = (
            From => $Twilio{'from'},
            To   => $to,
            Body => $args{Msg},
        );
        my $response = $ua->post( $Twilio{api_url}, \%text_message );

        if ( $response->is_success ) {
            RT::Logger->debug( 'Sending message to: ' . $to );
        } else {
            RT::Logger->error( 'Failed to send message to: ' . $to );
        }
    }

    return ( 1, 'Message(s) sent' );
}

1;
