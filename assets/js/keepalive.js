/*
** keepalive.js // v1.0.0 // 6th January 2022
** Keeps alive the websocket connection by sending a ping every x seconds
** where x = Genie.config.webchannels_keepalive_frequency
*/

function keepalive() {
  if (window._lastMessageAt !== undefined) {
    if (Date.now() - window._lastMessageAt < Genie.Settings.webchannels_keepalive_frequency) {
      return
    }
  }

  if (Genie.Settings.env == 'dev') {
    console.info('Keeping connection alive');
  }

  Genie.WebChannels.sendMessageTo(CHANNEL, 'keepalive', {
    'payload': {}
  });
}