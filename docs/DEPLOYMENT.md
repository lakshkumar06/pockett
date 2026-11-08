# Current deployment

Verified November 8, 2026.

- Public gateway: `https://pockett.orkis.tech`
- Health check: `https://pockett.orkis.tech/health`
- Vultr instance: `pockett` in Dallas (`vc2-1c-1gb`, 1 vCPU, 1 GB RAM, 25 GB disk)
- Instance price: `$0.007/hour`, capped at `$5/month` while provisioned
- Spacetime host: `https://maincloud.spacetimedb.com`
- Spacetime database: `pockett-hackutd-laksh`
- Photon: disabled

The gateway and NVIDIA worker run as Docker Compose services with automatic restart. Caddy terminates HTTPS. The private server `.env` is mode `0600`; NVIDIA and Spacetime credentials are not shipped in the iPhone app or committed to Git.

Pocket now defaults to `https://pockett.orkis.tech`. Existing installs that saved another address can select **Connection**, enter that URL, and tap **Use this server**.

## Verified flows

- Real public signup and login.
- A real NVIDIA build reached `ready` through `build_app`, `test_app`, and `finish`, then published successfully.
- Generated-app records persisted and were visible to both the owner and a shared user.
- Login, both saved rows, and sharing still worked after the local Mac gateway and worker were stopped.
- The same checks still passed after a clean Vultr reboot, confirming service restart and durable Spacetime data.
- The signed iPhone simulator build logged in through the public endpoint and listed the shared `Trip Pack` app.
- Updating the Spacetime module used `--delete-data=never`; user, app, job, and item counts were unchanged across publication.

The iOS simulator's embedded WebKit view did not render the generated app body even though native login/listing and the generated-app HTTP data API succeeded. Verify that final rendering once on a physical iPhone. APNs push was not tested.

## Billing

The Vultr account has a `$100` promotional credit applied October 25, 2026. At final verification it had `$93.93` of credit remaining and `$0.04` in pending deployment charges. No paid upgrade or automatic credit purchase was enabled. Vultr's API does not expose the promotional credit's exact expiration date, so that date remains unverified.

Vultr continues billing a stopped instance. To stop billing, destroy instance `20b6dd1e-71ec-43eb-97f3-0b45b5551ade` (`pockett`) in the Vultr dashboard or API. Destroying it removes the gateway/worker VM but does not delete the Spacetime database.

## Local simulator build

```sh
xcodebuild -project Pocket.xcodeproj -scheme Pocket -configuration Debug \
  -sdk iphonesimulator -derivedDataPath .build/Xcode \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
```
