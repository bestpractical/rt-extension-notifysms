package RT::Action::NotifyTwilio;

use base qw(RT::Action::NotifySMS);

use strict;
use warnings;
use LWP::UserAgent;
use JSON qw(decode_json);

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
