package RT::Action::NotifySMS;

use base qw(RT::Action::Notify);

use strict;
use warnings;
use LWP::UserAgent;

sub Prepare {
    my $self = shift;
    $self->SetRecipients( 'MobilePhone' );

    @{ $self->{'SMS'} } = (
      @{ $self->{'To'} },
      @{ $self->{'Cc'} },
      @{ $self->{'Bcc'} },
      @{ $self->{'PseudoTo'} }
    );

     unless ( $self->TemplateObj->MIMEObj ) {
        my ( $ret, $msg ) = $self->TemplateObj->Parse(
            Argument       => $self->Argument,
            TicketObj      => $self->TicketObj,
            TransactionObj => $self->TransactionObj
        );
        RT::Logger->error( "Could not parse SMS template: $msg" ) unless $ret;
    }

    return scalar @{ $self->{'SMS'} };
}

# We overlay the SetRecipients method here in order to get users who may have a
# Mobile Phone value but no email.
sub SetRecipients {
    my $self = shift;
    my $type = shift || 'EmailAddress';

    my $ticket = $self->TicketObj;

    my $arg = $self->Argument;
    $arg =~ s/\bAll\b/Owner,Requestor,AdminCc,Cc/;

    my ( @To, @PseudoTo, @Cc, @Bcc );


    if ( $arg =~ /\bRequestor\b/ ) {
        push @To, $ticket->Requestors->UserMembersObj;
    }

    # custom role syntax:   gives:
    #   name                  (undef,    role name,  Cc)
    #   RT::CustomRole-#      (role id,  undef,      Cc)
    #   name/To               (undef,    role name,  To)
    #   RT::CustomRole-#/To   (role id,  undef,      To)
    #   name/Cc               (undef,    role name,  Cc)
    #   RT::CustomRole-#/Cc   (role id,  undef,      Cc)
    #   name/Bcc              (undef,    role name,  Bcc)
    #   RT::CustomRole-#/Bcc  (role id,  undef,      Bcc)

    # this has to happen early because adding To addresses affects how Cc
    # is handled

    my $custom_role_re = qr!
                           ( # $1 match everything for error reporting

                           # word boundary
                           \b

                           # then RT::CustomRole-# or a role name
                           (?:
                               RT::CustomRole-(\d+)    # $2 role id
                             | ( \w+ )                 # $3 role name
                           )

                           # then, optionally, a type after a slash
                           (?:
                               /
                               (To | Cc | Bcc)         # $4 type
                           )?

                           # finally another word boundary, either from
                           # the end of role identifier or from the end of type
                           \b
                           )
                         !x;
    while ($arg =~ m/$custom_role_re/g) {
        my ($argument, $role_id, $name, $type) = ($1, $2, $3, $4);
        my $role;

        if ($name) {
            # skip anything that is a core Notify argument
            next if $name eq 'All'
                 || $name eq 'Owner'
                 || $name eq 'Requestor'
                 || $name eq 'AdminCc'
                 || $name eq 'Cc'
                 || $name eq 'OtherRecipients'
                 || $name eq 'AlwaysNotifyActor'
                 || $name eq 'NeverNotifyActor';

            my $roles = RT::CustomRoles->new( $self->CurrentUser );
            $roles->Limit( FIELD => 'Name', VALUE => $name, CASESENSITIVE => 0 );

            # custom roles are named uniquely, but just in case there are
            # multiple matches, bail out as we don't know which one to use
            $role = $roles->First;
            if ( $role ) {
                $role = undef if $roles->Next;
            }
        }
        else {
            $role = RT::CustomRole->new( $self->CurrentUser );
            $role->Load( $role_id );
        }

        unless ($role && $role->id) {
            $RT::Logger->debug("Unable to load custom role from scrip action argument '$argument'");
            next;
        }

        my @role_members = (
            $ticket->RoleGroup($role->GroupType)->UserMembersObj,
            $ticket->QueueObj->RoleGroup($role->GroupType)->UserMembersObj,
        );

        if (!$type || $type eq 'Cc') {
            push @Cc, @role_members;
        }
        elsif ($type eq 'Bcc') {
            push @Bcc, @role_members;
        }
        elsif ($type eq 'To') {
            push @To, @role_members;
        }
    }

    if ( $arg =~ /\bCc\b/ ) {

        #If we have a To, make the Ccs, Ccs, otherwise, promote them to To
        if (@To) {
            push ( @Cc, $ticket->Cc->UserMembersObj );
            push ( @Cc, $ticket->QueueObj->Cc->UserMembersObj  );
        }
        else {
            push ( @Cc, $ticket->Cc->UserMembersObj  );
            push ( @To, $ticket->QueueObj->Cc->UserMembersObj  );
        }
    }

    if (   $arg =~ /\bOwner\b/
        && $ticket->OwnerObj->id != RT->Nobody->id
        && not $ticket->OwnerObj->Disabled
    ) {
        # If we're not sending to Ccs or requestors,
        # then the Owner can be the To.
        if (@To) {
            push ( @Bcc, $ticket->OwnerObj );
        }
        else {
            push ( @To, $ticket->OwnerObj );
        }

    }

    if ( $arg =~ /\bAdminCc\b/ ) {
        push ( @Bcc, $ticket->AdminCc->UserMembersObj  );
        push ( @Bcc, $ticket->QueueObj->AdminCc->UserMembersObj  );
    }

    if ( RT->Config->Get('UseFriendlyToLine') ) {
        unless (@To) {
            push @PseudoTo,
                sprintf RT->Config->Get('FriendlyToLineFormat'), $arg, $ticket->id;
        }
    }

    my $getUsersAttr = sub {
      my $collection = shift;

      my @temp = ();
      foreach my $users ( @{$collection} ) {
          if ( ref $users eq 'RT::User' ) {
              next unless $users->$type;
              push @temp, $users->$type;
          }
          else {
              while ( my $user = $users->Next ) {
                  next unless $user->$type;
                  push @temp, $user->$type;
              }
          }
      };

      return @temp;
    };

    @{ $self->{'To'} }       = &$getUsersAttr ( \@To );
    @{ $self->{'Cc'} }       = &$getUsersAttr ( \@Cc );
    @{ $self->{'Bcc'} }      = &$getUsersAttr ( \@Bcc );
    @{ $self->{'PseudoTo'} } = &$getUsersAttr ( \@PseudoTo );

    if ( $arg =~ /\bOtherRecipients\b/ ) {
        if ( my $attachment = $self->TransactionObj->Attachments->First ) {
            push @{ $self->{'NoSquelch'}{'Cc'} ||= [] }, map $_->address,
                Email::Address->parse( $attachment->GetHeader('RT-Send-Cc') );
            push @{ $self->{'NoSquelch'}{'Bcc'} ||= [] }, map $_->address,
                Email::Address->parse( $attachment->GetHeader('RT-Send-Bcc') );
        }
    }
}

sub Commit {
    my $self = shift;

    my $content = $self->TemplateObj->MIMEObj->as_string;
    unless ( $content ) {
        RT::Logger->debug( 'No message found, not sending SMS' );
        return 1;
    }

    my ( $ret, $msg ) = $self->SendMessage(
        Recipients => $self->{'SMS'},
        Msg        => $content,
    );
    if ( $ret ) {
        my $transaction
          = RT::Transaction->new( $self->TransactionObj->CreatorObj );

        ( $ret, $msg ) = $transaction->Create(
          Ticket         => $self->TicketObj->Id,
          Type           => 'SMS',
          MIMEObj        => $self->TemplateObj->MIMEObj,
          ActivateScrips => 0
      );
      RT::Logger->error( "Failed to create transaction for SMS notification: $msg" ) unless $ret;
    }
    else {
        RT::Logger->error( $msg );
    }

    return $ret;
}

=pod
We need to overlay this method as our recipients array is an array
of phone numbers and not emails. Which results in an error if we try
to call C<Encode::decode("UTF-8",$self->TemplateObj->MIMEObj->head->get($field));>
=cut

sub AddressesFromHeader {
    my $self      = shift;
    my $field     = shift;
    return (());
}

1;
