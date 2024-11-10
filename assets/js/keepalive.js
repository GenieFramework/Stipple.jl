/*
** keepalive.js // v1.0.0 // 6th January 2022
** Keeps alive the websocket connection by sending a ping every x seconds
** where x = Genie.config.webchannels_keepalive_frequency
*/

function keepalive(WebChannel) {
  if (WebChannel.lastMessageAt !== undefined) {
    if (Date.now() - WebChannel.lastMessageAt + 200 < Genie.Settings.webchannels_keepalive_frequency) {
      return
    }
  }

  if (Genie.Settings.env == 'dev') {
    console.info('Keeping connection alive');
    console.log(WebChannel.parent.i)
  }

  WebChannel.sendMessageTo(WebChannel.channel, 'keepalive', {
    'payload': {}
  });
}
