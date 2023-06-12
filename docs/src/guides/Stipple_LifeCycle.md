# life-cycle and the various events of a Stipple app

## 1. Sync request -- server side response
- browser makes request to a URL
- the request is handled by the corresponding `route` and the `route` handler is executed
- the initial response/payload is prepared, meaning composing the HTML page and injecting all the JS scripts/files
- here we create a new instance of the model, we attach the handlers, and we call `Stipple.init(ModelType)` (because effectively the result of `Stipple.init` is a JS file that contains the JS/Vue.js version of our model)
- at this stage the developer can customise the HTML response by adding all sorts of conditional logic as needed
- the JS/Vue.js version of the model generated by `Stipple.init` is based on the Julia model type and not on an instance because the JS assets are designed to be cached and served from a CDN, so we do not want the JS/Vue.js model file to be customised -- it will always reflect the default state of the Julia model and it's the same for all the users.
- when all these steps are done, the resulting HTML response is sent to the browser

## 2. Client side rendering
- the browser receives the HTML response and renders it
- the browser loads all the JS files bundled with the initial response and executes them

## 3. JS execution -- client side
- as the browser renders the page, the JS included with the HTML response is executed
- Vue.js is loaded and the data passed in the JS/Vue.js model is applied to the HTML elements on the page (ex all the bindings like `@text`, `@bind`; logic like `@iif`, `@recur`, etc and all the dynamic props of the various elements)
- a connection back to the server is established (over WebSockets if available or using Ajax push/pull if WebSockets are not available)
- when the connection is successfully established the `isready` event is triggered, causing the `isready` property of the Julia model to be switched to true

## 4. Async requests -- server side responses
- as data is exchanged over the async connection with the frontend, various properties of the Julia model are changed, causing their handlers to be triggered -- starting with the automatically triggered `isready` event
- the developer implements the logic around these change handlers, responding to events and exchanging data with the frontend
- at this point we can no longer send HTML payloads (because that was part of the initial HTML response at 1 and that connection has closed) - we can only update properties of the model (over the async connection) which are pushed to the frontend causing the UI to update to reflect these changes.
- however, this is not necessarily a limitation as we can bind the HTML content of an element to be dynamic and we can update it -- or even we can send a JS payload to be executed on the frontend (so we can effectively inject and execute JS logic into the page from the Julia backend).