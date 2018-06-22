package RT::Action::NotifySMS;

use base qw(RT::Action);

use strict;
use warnings;
use LWP::UserAgent;

my @recipients;

sub Prepare {
    my $self = shift;

    $self->SetRecipients();
    $self->SUPER::Prepare();
}

sub SetRecipients {
    my $self = shift;

    my $ticket = $self->TicketObj;

    my $arg = $self->Argument;
    $arg =~ s/\bAll\b/Owner,Requestor,AdminCc,Cc/;

    my ( @To, @PseudoTo, @Cc, @Bcc );

    if ( $arg =~ /\bRequestor\b/ ) {
        push @To, $ticket->Requestors->MemberEmailAddresses;
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
            $ticket->RoleGroup( $role->GroupType )->MemberEmailAddresses,
            $ticket->QueueObj->RoleGroup( $role->GroupType )
                ->MemberEmailAddresses,
        );

        if ( !$type || $type eq 'Cc' ) {
            push @Cc, @role_members;
        } elsif ( $type eq 'Bcc' ) {
            push @Bcc, @role_members;
        } elsif ( $type eq 'To' ) {
            push @To, @role_members;
        }
    }

    if ( $arg =~ /\bCc\b/ ) {

        #If we have a To, make the Ccs, Ccs, otherwise, promote them to To
        if (@To) {
            push( @Cc, $ticket->Cc->MemberEmailAddresses );
            push( @Cc, $ticket->QueueObj->Cc->MemberEmailAddresses );
        } else {
            push( @Cc, $ticket->Cc->MemberEmailAddresses );
            push( @To, $ticket->QueueObj->Cc->MemberEmailAddresses );
        }
    }

    if (   $arg =~ /\bOwner\b/
        && $ticket->OwnerObj->id != RT->Nobody->id
        && $ticket->OwnerObj->EmailAddress
        && not $ticket->OwnerObj->Disabled )
    {
        # If we're not sending to Ccs or requestors,
        # then the Owner can be the To.
        if (@To) {
            push( @Bcc, $ticket->OwnerObj->EmailAddress );
        } else {
            push( @To, $ticket->OwnerObj->EmailAddress );
        }

    }

    if ( $arg =~ /\bAdminCc\b/ ) {
        push( @Bcc, $ticket->AdminCc->MemberEmailAddresses );
        push( @Bcc, $ticket->QueueObj->AdminCc->MemberEmailAddresses );
    }

    if ( RT->Config->Get('UseFriendlyToLine') ) {
        unless (@To) {
            push @PseudoTo,
                sprintf RT->Config->Get('FriendlyToLineFormat'), $arg,
                $ticket->id;
        }
    }

    if ( $arg =~ /\bOtherRecipients\b/ ) {
        if ( my $attachment = $self->TransactionObj->Attachments->First ) {
            push @{ $self->{'NoSquelch'}{'Cc'} ||= [] }, map $_->address,
                Email::Address->parse( $attachment->GetHeader('RT-Send-Cc') );
            push @{ $self->{'NoSquelch'}{'Bcc'} ||= [] }, map $_->address,
                Email::Address->parse(
                $attachment->GetHeader('RT-Send-Bcc') );
        }
    }

    my @roles = \@To;
    push @roles, \@Cc;
    push @roles, \@Bcc;
    push @roles, \@PseudoTo;

    my $user = RT::User->new( RT->SystemUser );
    my @recipients;

    foreach my $role (@roles) {
        foreach my $user_email ( @{$role} ) {
            my ( $ret, $msg ) = $user->LoadByEmail($user_email);
            RT::Logger->error($msg) unless $ret;

            push @recipients, $user->MobilePhone
                unless !$user->MobilePhone;
        }
    }
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
