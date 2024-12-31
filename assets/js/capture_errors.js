function showErrorMessage (message, type='error') {
  let color;
  if( type === 'error'){
    color = 'red-5';
    console.error( message);
  }else{
    color = 'amber-8';
    console.warn( message);
  }
  Quasar.Notify.create( {
      message: message,
      position: 'bottom-right',
      color,
      timeout: 0,
      actions: [
        { icon: 'close', color: 'white', round: true, handler: () => { /* ... */ } }
      ]
  })
}

function registerErrorHandlers(){
  Vue.config.errorHandler = (err, vm, info) => {
    showErrorMessage( err, 'error');
  };

  Vue.config.warnHandler = (message, vm, trace) => {
    showErrorMessage( message, 'warn');
  };

  window.addEventListener('error', (e) => {
    showErrorMessage( e.message, 'error');
  })
}

registerErrorHandlers();