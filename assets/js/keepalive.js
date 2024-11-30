/*
** keepalive.js // v1.1.0 // 11 November 2024
** Keeps alive the websocket connection by sending a ping every x seconds
** where x = Genie.config.webchannels_keepalive_frequency
*/

function keepalive(WebChannel) {
  if (WebChannel.lastMessageAt !== undefined) {
    dt = Date.now() - WebChannel.lastMessageAt;
    // allow for a 200ms buffer
    if (dt + 200 < Genie.Settings.webchannels_keepalive_frequency) {
      keepaliveTimer(WebChannel, Genie.Settings.webchannels_keepalive_frequency - dt);
      return;
    }
  }

  if (!WebChannel.ws_disconnected) {
    if (Genie.Settings.env == 'dev') {
      console.info('Keeping connection alive');
    }
    WebChannel.sendMessageTo(WebChannel.channel, 'keepalive', {
      'payload': {}
    });
  }
}

function keepaliveTimer(WebChannel, startDelay = Genie.Settings.webchannels_keepalive_frequency) {
  clearInterval(WebChannel.keepalive_interval);
  setTimeout(() => {
    keepalive(WebChannel);
    WebChannel.keepalive_interval = setInterval(() => keepalive(WebChannel), Genie.Settings.webchannels_keepalive_frequency);
  }, startDelay)
}