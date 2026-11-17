# Phone and computer webpages

Home always uses the official web interface. The bottom-right This phone or Connect computer label identifies the runtime destination, not a switch between native and web chat interfaces.

## Use this phone

1. Tap the bottom-right control and choose This phone.
2. If the runtime is missing, install it as prompted. Otherwise wait for one startup attempt and webpage loading.
3. Use Retry after an error appears. The local webpage is for in-app use; do not treat its phone-local address as a computer-accessible service address.

Local accounts, workspaces and conversations belong to the phone environment. Returning to this phone does not import computer history.

## Connect a computer

Run DeepSeek harness on the computer first. Its web service or remote-access plugin must provide an HTTP/HTTPS address reachable from the phone. The shell opens that webpage; it does not install, start or configure the computer's service.

1. Tap the bottom-right control and choose Connect computer.
2. Enter the complete HTTP/HTTPS address provided by the computer, or open QR scanning to scan its webpage-address code.
3. Review the protocol, host and port in the connection preview. Confirm that this is the intended computer, then confirm connection. Reading a QR code does not automatically execute its contents.
4. Complete any PIN, login or other verification inside the webpage. Shell confirmation does not mean web authentication has succeeded.

The address must be reachable. `127.0.0.1` on the phone refers to the phone, not the computer; different networks may need computer-side access configuration. Follow actual HTTPS certificate or webpage errors rather than guessing success by changing protocols.

## Recent connections

Recent computer addresses appear on the connection page and still require confirmation when selected. Displayed records omit login query parameters and fragments. Login-bearing URLs use the app's separate credential storage; do not share complete login links.

Removing a record deletes that connection and its associated login URL saved on this phone. It does not delete the computer engine, workspaces or conversations, and does not sign out every computer webpage session.

## Connection boundaries

Phone permissions, local drafts and local notifications do not automatically take over computer conversations. Computer plugins, models and features follow that computer's webpage. After a failed switch, verify the bottom label and address before changing settings on the wrong destination; see [Troubleshooting](11-faq.md).
