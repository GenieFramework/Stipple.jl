/*
** keepalive.js // v1.0.0 // 6th January 2022
** Keeps alive the websocket connection by sending a ping every x seconds
** where x = Genie.config.webchannels_keepalive_frequency
*/

function keepalive() {
  console.log("keepalive");
  Genie.WebChannels.sendMessageTo(CHANNEL, 'keepalive', {
    'payload': {}
  });
}