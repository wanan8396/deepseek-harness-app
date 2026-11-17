# Sign-in and models

Accounts, models and providers are managed through the official web settings. The phone shell has no separate native provider editor and does not automatically copy keys from old native settings into the current official profile.

## Sign in to DeepSeek

1. Open the sidebar, then Account through its account menu or Settings.
2. Choose Sign in and follow the official page into your browser. If it does not open automatically, use the page's copy-sign-in-link action.
3. Return to DeepSeek harness and wait for the webpage to report that you are signed in. Start a new sign-in after expiry or failure rather than repeatedly reusing an old link.
4. Read the confirmation before signing out. Signing out does not delete projects or files, but may interrupt work that uses the account.

## Add or select a model

1. Open Models in the official settings.
2. Select an existing provider, or use the available add action. Enter its protocol, Base URL, model ID and API key according to the service's documentation.
3. Save when the page requires it, then return to the conversation's model control and check availability.
4. Set context, output limits, image input and reasoning levels only to capabilities supported by the service and current page. A displayed model name does not establish a successful API call.

Phone and computer provider configurations are independent. After switching to a computer, you edit that computer's current profile, not the phone's previous model list.

## API keys, tokens and cookies are different

- An API key is a model service credential. Enter it only in the designated field on the official model or account page.
- A web launch token opens a particular engine's webpage; it is not a model API key. A login URL containing a token is also a credential.
- Cookies hold web login state. A browser and WebView may have different states: signing in in an external browser does not necessarily sign in the in-app page.
- None belongs in a conversation, screenshot, log or feedback report. This guide includes no sample secret, complete token or cookie.

For model errors, check the destination, login state, provider address and service-side model access. A successful save does not verify balance, networking or model access. For a computer webpage's PIN or login flow, see [Web connections](05-web.md).
