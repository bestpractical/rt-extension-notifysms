package RT::Action::NotifySMS;

use base qw(RT::Action);

use strict;
use warnings;
use LWP::UserAgent;

my @recipients;

sub Prepare {
    my $self = shift;

    return 0 unless $self->SetRecipients();
    $self->SUPER::Prepare();
}

sub SetRecipients {
    my $self = shift;

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
    while ( $arg =~ m/$custom_role_re/g ) {
        my ( $argument, $role_id, $name, $type ) = ( $1, $2, $3, $4 );
        my $role;

        if ($name) {

            # skip anything that is a core Notify argument
            next
                if $name eq 'All'
                || $name eq 'Owner'
                || $name eq 'Requestor'
                || $name eq 'AdminCc'
                || $name eq 'Cc'
                || $name eq 'OtherRecipients'
                || $name eq 'AlwaysNotifyActor'
                || $name eq 'NeverNotifyActor';

            my $roles = RT::CustomRoles->new( $self->CurrentUser );
            $roles->Limit(
                FIELD         => 'Name',
                VALUE         => $name,
                CASESENSITIVE => 0
            );

            # custom roles are named uniquely, but just in case there are
            # multiple matches, bail out as we don't know which one to use
            $role = $roles->First;
            if ($role) {
                $role = undef if $roles->Next;
            }
        } else {
            $role = RT::CustomRole->new( $self->CurrentUser );
            $role->Load($role_id);
        }

        unless ( $role && $role->id ) {
            $RT::Logger->debug(
                "Unable to load custom role from scrip action argument '$argument'"
            );
            next;
        }

        my @role_members = (
            $ticket->RoleGroup( $role->GroupType )->UserMembersObj,
            $ticket->QueueObj->RoleGroup( $role->GroupType )
                ->UserMembersObj,
        );
        push @To, @role_members;
    }

    if ( $arg =~ /\bCc\b/ ) {
        push( @To, $ticket->Cc->UserMembersObj );
        push( @To, $ticket->QueueObj->Cc->UserMembersObj );
    }
    if (   $arg =~ /\bOwner\b/
        && $ticket->OwnerObj->id != RT->Nobody->id
        && not $ticket->OwnerObj->Disabled )
    {
        my $role_group = $self->TicketObj->RoleGroup('Owner');
        push( @To, $role_group->UserMembersObj );
    }

    if ( $arg =~ /\bAdminCc\b/ ) {
        push( @To, $ticket->AdminCc->UserMembersObj );
        push( @To, $ticket->QueueObj->AdminCc->UserMembersObj );
    }

    if ( RT->Config->Get('UseFriendlyToLine') ) {
        unless (@To) {
            push @PseudoTo,
                sprintf RT->Config->Get('FriendlyToLineFormat'), $arg,
                $ticket->id;
        }
    }

    my @NoSquelch;
    if ( $arg =~ /\bOtherRecipients\b/ ) {
        if ( my $attachment = $self->TransactionObj->Attachments->First ) {
            push @NoSquelch, map $_->address,
                Email::Address->parse( $attachment->GetHeader('RT-Send-Cc') );
            push @NoSquelch, map $_->address,
                Email::Address->parse(
                $attachment->GetHeader('RT-Send-Bcc') );
        }
    }

    # See if we can get some phone numbers from our NoSquelched emails
    if ( @NoSquelch ) {
        my $user = RT::User->new(RT->SystemUser);
        foreach my $email (@NoSquelch) {
            my ($ret, $msg) = $user->Load($email);
            RT::Logger->info($msg) unless $ret;

            push @To, $user->MobilePhone unless ! $user->MobilePhone;
        }
    }

    my $user = RT::User->new( RT->SystemUser );
    my @recipients;

    foreach my $role (@To) {
        while (my $user = $role->Next) {
            push @recipients, $user->MobilePhone
                unless !$user->MobilePhone;
        }
    }
    return 0 unless scalar @recipients;

    @{ $self->{'Recipients'} } = @recipients;
}

sub Commit {
    my $self = shift;

    unless ( $self->TemplateObj->MIMEObj ) {
        my ( $result, $message ) = $self->TemplateObj->Parse(
            Argument       => $self->Argument,
            TicketObj      => $self->TicketObj,
            TransactionObj => $self->TransactionObj
        );
    }

    my $content = $self->TemplateObj->MIMEObj->as_string;

    my ( $ret, $msg ) = $self->ScripActionObj->Action->SendMessage(
        Recipients => $self->{Recipients},
        Msg        => $content,
    );

    RT::Logger->error($msg) unless $ret;

    return $ret;
}

1;
