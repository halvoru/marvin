package Marvin::Adapter::XMPP;

use Marvin::Adapter;
use Mojo::Base 'Marvin::Adapter';

has 'client';

use AnyEvent;
use AnyEvent::XMPP::Client;
use AnyEvent::XMPP::IM::Message;
use AnyEvent::XMPP::Ext::Disco;
use AnyEvent::XMPP::Ext::MUC;

sub register {
  my $self   = shift;
  my $config = $self->config;
  $self->client(
    AnyEvent::XMPP::Client->new(debug => $self->config->{debug} // 0));
  $self->client->add_account($config->{user}, $config->{pass},
    $config->{host});
  $self->client->reg_cb(
    session_ready => sub {
      my ($cl, $acc) = @_;
      $cl->set_presence(undef,
        $config->{tagline} || "Life ? Don't talk to me about life .", 10);
      my $con = $acc->connection;
      $con->add_extension(my $disco = AnyEvent::XMPP::Ext::Disco->new);
      $con->add_extension(my $muc
          = AnyEvent::XMPP::Ext::MUC->new(disco => $disco));

      $muc->join_room($con, $_, $config->{nick}) for (@{$config->{rooms}});
      $muc->reg_cb(
        message => sub {
          my ($cl, $room, $msg, $is_echo) = @_;
          return if $is_echo;
          return if $msg->is_delayed;
          my $nick = $config->{nick};
          if ($msg->any_body =~ /^\s*\Q$nick\E:/) {
            $self->emit(message => $msg->any_body, $room->jid);
          }
        },
        enter => sub {
          my ($cl, $room, $me) = @_;
          $self->emit(joined => $room->jid, $me);
          $self->{rooms}->{$room->jid} = $room;
        },
        leave => sub {
          my ($cl, $room, $me) = @_;
          $self->emit(parted => $room->jid, $me);
          delete $self->{rooms}->{$room->jid};
        },
      );
    },
    disconnect => sub {
      my ($cl, $acc, $h, $p, $reas) = @_;
      $self->emit(disconnected => $h, $p);
    },
    error => sub {
      my ($cl, $acc, $err) = @_;
      print "ERROR: " . $err->string . "\n";
    },
  );
  $self->on(
    'notify',
    sub {
      my ($e, $jid, $msg) = @_;
      if (my $room = $self->{rooms}->{$jid}) {
        $room->make_message(body => $msg)->send;
      }

    }
  );
  $self->client->start;
}

1;

=head1 NAME

Marvin::Adapter::XMPP - XMPP Adapter for Marvin.

=head1 SYNOPSIS

  adapters => [{
    type  => 'XMPP',
    user  => 'marcusr@chat.uio.no/marvin',
    pass  => undef,
    host  => 'chat.uio.no',
    nick  => 'marvin',
    rooms => [ 'w3d-chatops@conference.chat.uio.no' ],
    tagline => undef,
  }],

=head1 DESCRIPTION

=head1 METHODS
