# Solana Pay requests

Generated lists, trackers, and polls can include an optional fixed SOL payment
request. For example, ask the builder:

> Build a club dues tracker with a 0.01 SOL payment request to MY_PUBLIC_ADDRESS.

Replace `MY_PUBLIC_ADDRESS` with the intended recipient's Solana public address.
The builder rejects newly introduced recipients that are absent from the prompt.
Never supply private keys or seed phrases.

The generated spec adds:

```json
"payment": { "recipient": "YOUR_PUBLIC_ADDRESS", "amount": "0.01" }
```

The app displays the amount and recipient, then offers **Open wallet** using a
[Solana Pay transfer request](https://docs.solanapay.com/spec). On iPhone, Pocket
requires a user tap and confirmation before handing the request to an installed
wallet. The wallet reviews and signs the transfer. Pocket holds no signing keys.

Amounts are positive decimal strings with at most nine fractional digits. This
version supports native SOL only. Transfer links do not select a network; check
the wallet's network before approving. Use a devnet wallet for initial testing.

These are payment requests, not verified receipts. Pocket does not submit
transactions, confirm settlement, mark entries paid, prevent repeat payments,
or gate access. There is no per-entry payment reference or RPC integration yet.

Validation:

```sh
npm --prefix Runtime run check
npm --prefix Runtime test
node Runtime/test/solana-browser.ts
```

The browser check intercepts requests locally and uses a format-only address
fixture. It sends no funds. Native wallet signing must be tested separately on
an iPhone with a compatible wallet. Deploy the updated Spacetime module and
runtime together, and rebuild the iPhone app to enable its wallet handoff.
